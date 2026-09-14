-- Business-rule enforcement (brief section 5).
-- Implemented as triggers + constraint triggers so the rules hold for every
-- client of the database, not just the API.

BEGIN;
SET search_path TO oep, public;

-- =====================================================================
-- helpers
-- =====================================================================

CREATE OR REPLACE FUNCTION confirmed_count(p_trip_id INT) RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT count(*)::INT FROM registrations
    WHERE trip_id = p_trip_id AND status = 'confirmed';
$$;

-- Does the guide hold this certification for the whole window [p_from, p_to]?
CREATE OR REPLACE FUNCTION guide_holds_certification(
    p_guide_id INT, p_certification_id INT, p_from DATE, p_to DATE
) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM guide_certifications gc
        WHERE gc.guide_id = p_guide_id
          AND gc.certification_id = p_certification_id
          AND gc.issued_on  <= p_from
          AND gc.expires_on >= p_to
    );
$$;

-- Units of an item already committed to trips overlapping [p_from, p_to],
-- ignoring one trip_equipment row (the one being inserted/updated).
CREATE OR REPLACE FUNCTION committed_quantity(
    p_equipment_id INT, p_from DATE, p_to DATE, p_exclude_id INT DEFAULT NULL
) RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(sum(te.quantity), 0)::INT
    FROM trip_equipment te
    JOIN trips t ON t.id = te.trip_id
    WHERE te.equipment_id = p_equipment_id
      AND (p_exclude_id IS NULL OR te.id <> p_exclude_id)
      AND te.checked_in_at IS NULL          -- returned gear is back in the pool
      AND t.status <> 'cancelled'
      AND daterange(t.start_date, t.end_date, '[]')
          && daterange(p_from, p_to, '[]');
$$;

-- =====================================================================
-- RULE 1 -- capacity: confirmed registrations may never exceed capacity;
--           overflow is waitlisted automatically.
-- =====================================================================

CREATE OR REPLACE FUNCTION reg_before_insert() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_trip   trips;
    v_member members;
BEGIN
    -- Serialises concurrent registrations for the same trip: two clients
    -- racing for the last spot cannot both read "capacity - 1".
    SELECT * INTO v_trip FROM trips WHERE id = NEW.trip_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'trip % does not exist', NEW.trip_id;
    END IF;

    IF v_trip.status <> 'open' THEN
        RAISE EXCEPTION 'trip % is % and is not accepting registrations',
            v_trip.id, v_trip.status USING ERRCODE = 'check_violation';
    END IF;

    SELECT * INTO v_member FROM members WHERE id = NEW.member_id;
    IF v_member.membership_status <> 'active' THEN
        RAISE EXCEPTION 'member % has a % membership and cannot register',
            NEW.member_id, v_member.membership_status USING ERRCODE = 'check_violation';
    END IF;

    -- Registering for a trip pays for it: the fee is taken here rather than
    -- being a second step staff have to remember.
    IF NEW.amount_paid_cents = 0 AND NEW.payment_status = 'paid' THEN
        NEW.amount_paid_cents := v_trip.fee_cents;
    END IF;

    IF NEW.status = 'confirmed' THEN
        IF confirmed_count(NEW.trip_id) >= v_trip.capacity THEN
            NEW.status := 'waitlisted';       -- trip is full: join the queue
            NEW.confirmed_at := NULL;
        ELSE
            NEW.confirmed_at := COALESCE(NEW.confirmed_at, clock_timestamp());
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER t10_reg_capacity BEFORE INSERT ON registrations
FOR EACH ROW EXECUTE FUNCTION reg_before_insert();

CREATE OR REPLACE FUNCTION reg_before_update() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_capacity INT;
BEGIN
    IF NEW.status = 'confirmed' AND OLD.status <> 'confirmed' THEN
        SELECT capacity INTO v_capacity FROM trips WHERE id = NEW.trip_id FOR UPDATE;
        IF confirmed_count(NEW.trip_id) >= v_capacity THEN
            RAISE EXCEPTION
                'cannot confirm registration %: trip % is at capacity (%)',
                NEW.id, NEW.trip_id, v_capacity USING ERRCODE = 'check_violation';
        END IF;
        NEW.confirmed_at := COALESCE(NEW.confirmed_at, clock_timestamp());
    END IF;

    IF NEW.status IN ('cancelled', 'no_show') AND OLD.status NOT IN ('cancelled', 'no_show') THEN
        NEW.cancelled_at := COALESCE(NEW.cancelled_at, clock_timestamp());
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER t10_reg_capacity_update BEFORE UPDATE ON registrations
FOR EACH ROW EXECUTE FUNCTION reg_before_update();

-- Belt and braces: the invariant is re-checked after the fact, so no path
-- (including a direct UPDATE by a superuser client) can leave a trip oversold.
CREATE OR REPLACE FUNCTION reg_assert_capacity() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_trip_id INT := COALESCE(NEW.trip_id, OLD.trip_id);
    v_capacity INT;
    v_count INT;
BEGIN
    SELECT capacity INTO v_capacity FROM trips WHERE id = v_trip_id;
    v_count := confirmed_count(v_trip_id);
    IF v_count > v_capacity THEN
        RAISE EXCEPTION 'trip % oversold: % confirmed registrations for capacity %',
            v_trip_id, v_count, v_capacity USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER t99_reg_assert_capacity
AFTER INSERT OR UPDATE ON registrations
DEFERRABLE INITIALLY IMMEDIATE
FOR EACH ROW EXECUTE FUNCTION reg_assert_capacity();

-- Capacity cannot be cut below the number of people already confirmed.
CREATE OR REPLACE FUNCTION trip_capacity_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE v_count INT;
BEGIN
    IF NEW.capacity < OLD.capacity THEN
        v_count := confirmed_count(NEW.id);
        IF NEW.capacity < v_count THEN
            RAISE EXCEPTION
                'cannot reduce capacity of trip % to %: % registrations are confirmed',
                NEW.id, NEW.capacity, v_count USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER t10_trip_capacity_guard BEFORE UPDATE OF capacity ON trips
FOR EACH ROW EXECUTE FUNCTION trip_capacity_guard();

-- =====================================================================
-- RULE 2 -- when a confirmed spot is given up, the longest-waiting
--           waitlisted registration is promoted automatically.
-- =====================================================================

CREATE OR REPLACE FUNCTION promote_from_waitlist(p_trip_id INT) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_id       INT;
    v_capacity INT;
BEGIN
    SELECT capacity INTO v_capacity FROM trips WHERE id = p_trip_id FOR UPDATE;
    IF v_capacity IS NULL OR confirmed_count(p_trip_id) >= v_capacity THEN
        RETURN NULL;
    END IF;

    SELECT id INTO v_id
    FROM registrations
    WHERE trip_id = p_trip_id AND status = 'waitlisted'
    ORDER BY registered_at, id          -- registration order
    LIMIT 1
    FOR UPDATE;

    IF v_id IS NULL THEN
        RETURN NULL;
    END IF;

    UPDATE registrations
       SET status = 'confirmed', confirmed_at = clock_timestamp()
     WHERE id = v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION reg_after_release() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'confirmed' THEN
            PERFORM promote_from_waitlist(OLD.trip_id);
        END IF;
    ELSIF OLD.status = 'confirmed' AND NEW.status IN ('cancelled', 'no_show') THEN
        PERFORM promote_from_waitlist(NEW.trip_id);
    END IF;
    RETURN NULL;
END;
$$;

-- Fires only on a released confirmed seat, so promotion cannot recurse
-- (the promoted row moves waitlisted -> confirmed).
CREATE TRIGGER t20_reg_promote AFTER UPDATE OR DELETE ON registrations
FOR EACH ROW EXECUTE FUNCTION reg_after_release();

-- =====================================================================
-- RULE 3 -- a guide may only be assigned to a trip whose required
--           certification they hold, valid for the whole trip.
-- =====================================================================

CREATE OR REPLACE FUNCTION trip_guide_cert_check() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_trip trips;
    v_code TEXT;
BEGIN
    SELECT * INTO v_trip FROM trips WHERE id = NEW.trip_id;

    IF v_trip.required_certification_id IS NOT NULL
       AND NOT guide_holds_certification(NEW.guide_id,
                v_trip.required_certification_id, v_trip.start_date, v_trip.end_date)
    THEN
        SELECT code INTO v_code FROM certifications
         WHERE id = v_trip.required_certification_id;
        RAISE EXCEPTION
            'guide % cannot lead trip % (%): requires % valid through %',
            NEW.guide_id, v_trip.id, v_trip.name, v_code, v_trip.end_date
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER t10_trip_guide_cert BEFORE INSERT OR UPDATE ON trip_guides
FOR EACH ROW EXECUTE FUNCTION trip_guide_cert_check();

-- Changing a trip's dates or requirement must not invalidate its roster.
CREATE OR REPLACE FUNCTION trip_revalidate_guides() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
    IF NEW.required_certification_id IS NULL THEN
        RETURN NEW;
    END IF;
    FOR r IN SELECT guide_id FROM trip_guides WHERE trip_id = NEW.id LOOP
        IF NOT guide_holds_certification(r.guide_id,
                NEW.required_certification_id, NEW.start_date, NEW.end_date) THEN
            RAISE EXCEPTION
                'cannot change trip %: assigned guide % would no longer hold the required certification',
                NEW.id, r.guide_id USING ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER t10_trip_revalidate_guides
BEFORE UPDATE OF required_certification_id, start_date, end_date ON trips
FOR EACH ROW EXECUTE FUNCTION trip_revalidate_guides();

-- A certification cannot be revoked or shortened out from under an assignment.
CREATE OR REPLACE FUNCTION guide_cert_change_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_guide INT := COALESCE(NEW.guide_id, OLD.guide_id);
    r RECORD;
BEGIN
    FOR r IN
        SELECT t.id, t.name, t.start_date, t.end_date, t.required_certification_id
        FROM trip_guides tg
        JOIN trips t ON t.id = tg.trip_id
        WHERE tg.guide_id = v_guide
          AND t.required_certification_id = OLD.certification_id
          AND t.status NOT IN ('cancelled', 'completed')
    LOOP
        IF NOT guide_holds_certification(v_guide, r.required_certification_id,
                                         r.start_date, r.end_date) THEN
            RAISE EXCEPTION
                'guide % is assigned to trip % (%) which requires this certification through %',
                v_guide, r.id, r.name, r.end_date USING ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE CONSTRAINT TRIGGER t99_guide_cert_guard
AFTER UPDATE OR DELETE ON guide_certifications
DEFERRABLE INITIALLY IMMEDIATE
FOR EACH ROW EXECUTE FUNCTION guide_cert_change_guard();

-- =====================================================================
-- RULE 4 -- equipment cannot be double-booked across overlapping trips.
-- =====================================================================

CREATE OR REPLACE FUNCTION trip_equipment_availability_check() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_trip  trips;
    v_item  equipment;
    v_committed INT;
BEGIN
    -- Lock the inventory row so two overlapping checkouts of the same item
    -- cannot both pass the availability test.
    SELECT * INTO v_item FROM equipment WHERE id = NEW.equipment_id FOR UPDATE;
    SELECT * INTO v_trip FROM trips WHERE id = NEW.trip_id;

    IF v_item.condition IN ('lost', 'retired') THEN
        RAISE EXCEPTION 'equipment % (%) is % and cannot be checked out',
            v_item.id, v_item.name, v_item.condition USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.checked_in_at IS NOT NULL THEN
        RETURN NEW;   -- returning gear never consumes availability
    END IF;

    v_committed := committed_quantity(NEW.equipment_id, v_trip.start_date,
                                      v_trip.end_date, NEW.id);

    IF v_committed + NEW.quantity > v_item.total_quantity THEN
        RAISE EXCEPTION
            'only % of % "%" available for % to %: % already committed to overlapping trips',
            v_item.total_quantity - v_committed, v_item.total_quantity, v_item.name,
            v_trip.start_date, v_trip.end_date, v_committed
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER t10_trip_equipment_availability
BEFORE INSERT OR UPDATE ON trip_equipment
FOR EACH ROW EXECUTE FUNCTION trip_equipment_availability_check();

-- Moving a trip's dates must not create an overcommitment either.
CREATE OR REPLACE FUNCTION trip_dates_equipment_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT te.id, te.equipment_id, te.quantity, e.name, e.total_quantity
        FROM trip_equipment te JOIN equipment e ON e.id = te.equipment_id
        WHERE te.trip_id = NEW.id AND te.checked_in_at IS NULL
    LOOP
        IF committed_quantity(r.equipment_id, NEW.start_date, NEW.end_date, r.id)
             + r.quantity > r.total_quantity THEN
            RAISE EXCEPTION
                'cannot move trip % to % - %: "%" would be over-committed',
                NEW.id, NEW.start_date, NEW.end_date, r.name
                USING ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER t11_trip_dates_equipment
BEFORE UPDATE OF start_date, end_date ON trips
FOR EACH ROW EXECUTE FUNCTION trip_dates_equipment_guard();

-- Inventory cannot shrink below what is already committed.
CREATE OR REPLACE FUNCTION equipment_quantity_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE v_peak INT;
BEGIN
    IF NEW.total_quantity >= OLD.total_quantity THEN
        RETURN NEW;
    END IF;
    -- Peak concurrent commitment: worst case is measured at each trip's window.
    SELECT COALESCE(max(committed_quantity(NEW.id, t.start_date, t.end_date, NULL)), 0)
      INTO v_peak
      FROM trip_equipment te JOIN trips t ON t.id = te.trip_id
     WHERE te.equipment_id = NEW.id AND te.checked_in_at IS NULL
       AND t.status <> 'cancelled';

    IF NEW.total_quantity < v_peak THEN
        RAISE EXCEPTION
            'cannot reduce "%" to %: % units are committed to scheduled trips',
            NEW.name, NEW.total_quantity, v_peak USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER t10_equipment_quantity_guard BEFORE UPDATE OF total_quantity ON equipment
FOR EACH ROW EXECUTE FUNCTION equipment_quantity_guard();

-- =====================================================================
-- RULE 5 -- no-show sweep: a confirmed member who missed a mandatory
--           pre-trip meeting loses the spot, which feeds rule 2.
-- =====================================================================

CREATE OR REPLACE FUNCTION process_pre_trip_meetings(p_as_of TIMESTAMPTZ DEFAULT now())
RETURNS TABLE (trip_id INT, registration_id INT, member_id INT, action TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    r          RECORD;
    v_promoted INT;
    v_reported INT[] := '{}';
BEGIN
    FOR r IN
        SELECT rg.id, rg.trip_id, rg.member_id
        FROM registrations rg
        JOIN trips t ON t.id = rg.trip_id
        WHERE t.pre_trip_meeting_at IS NOT NULL
          AND t.pre_trip_meeting_at <= p_as_of
          AND t.status = 'open'
          AND rg.status = 'confirmed'
          AND rg.attended_pre_trip_meeting = false
          -- someone promoted after the meeting had already happened is not a no-show
          AND (rg.confirmed_at IS NULL OR rg.confirmed_at <= t.pre_trip_meeting_at)
        ORDER BY rg.trip_id, rg.registered_at, rg.id
    LOOP
        UPDATE registrations
           SET status = 'no_show',
               cancel_reason = 'missed mandatory pre-trip meeting'
         WHERE id = r.id;

        RETURN QUERY SELECT r.trip_id, r.id, r.member_id, 'no_show'::TEXT;

        -- the release trigger already promoted someone; report who
        SELECT rg.id INTO v_promoted
          FROM registrations AS rg
         WHERE rg.trip_id = r.trip_id AND rg.status = 'confirmed'
           AND rg.confirmed_at > (SELECT pre_trip_meeting_at FROM trips WHERE id = r.trip_id)
           AND NOT (rg.id = ANY(v_reported))
         ORDER BY rg.confirmed_at DESC LIMIT 1;
        IF v_promoted IS NOT NULL THEN
            v_reported := v_reported || v_promoted;
            RETURN QUERY SELECT r.trip_id, v_promoted,
                   (SELECT rg2.member_id FROM registrations rg2 WHERE rg2.id = v_promoted),
                   'promoted'::TEXT;
        END IF;
    END LOOP;

    UPDATE trips SET meeting_processed_at = p_as_of
     WHERE pre_trip_meeting_at IS NOT NULL
       AND pre_trip_meeting_at <= p_as_of
       AND status = 'open';
END;
$$;

COMMIT;
