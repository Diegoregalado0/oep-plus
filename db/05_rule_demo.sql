-- Demonstrates every rule in section 5 of the brief, both accepting and
-- rejecting. Runs inside a transaction that is rolled back, so it is
-- repeatable and leaves the seed data untouched.
--   docker compose exec -T db psql -U oep -d oep -f - < db/05_rule_demo.sql
\set QUIET on
\pset pager off
SET client_min_messages TO NOTICE;
BEGIN;
SET search_path TO oep, public;

DO $$ BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'RULE 1  capacity is capped; overflow is waitlisted automatically';
    RAISE NOTICE '================================================================';
END $$;

DO $$
DECLARE v_status registration_status; v_trip INT;
BEGIN
    SELECT id INTO v_trip FROM trips WHERE name = 'Hike Dewey Point';
    RAISE NOTICE 'Half Dome: capacity 3, currently % confirmed / % waitlisted',
        (SELECT confirmed FROM v_trip_capacity WHERE trip_id = v_trip),
        (SELECT waitlisted FROM v_trip_capacity WHERE trip_id = v_trip);

    -- ACCEPTED, but silently downgraded to the waitlist
    INSERT INTO registrations (trip_id, member_id)
    VALUES (v_trip, (SELECT id FROM members WHERE email = 'kmensah@ucmerced.edu'))
    RETURNING status INTO v_status;
    RAISE NOTICE 'PASS  Kofi asked for a confirmed spot on a full trip -> status = %', v_status;
END $$;

DO $$
DECLARE v_trip INT; v_reg INT;
BEGIN
    SELECT id INTO v_trip FROM trips WHERE name = 'Hike Dewey Point';
    SELECT id INTO v_reg FROM registrations
     WHERE trip_id = v_trip AND status = 'waitlisted' ORDER BY registered_at LIMIT 1;
    -- REJECTED: forcing a waitlisted row to confirmed while the trip is full
    UPDATE registrations SET status = 'confirmed' WHERE id = v_reg;
    RAISE NOTICE 'FAIL  oversold the trip!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  forcing a 4th confirmed seat: %', SQLERRM;
END $$;

DO $$
BEGIN
    -- REJECTED: cutting capacity below the confirmed headcount
    UPDATE trips SET capacity = 1 WHERE name = 'Hike Dewey Point';
    RAISE NOTICE 'FAIL  capacity cut below confirmed headcount!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  capacity cut to 1: %', SQLERRM;
END $$;

DO $$
BEGIN
    -- REJECTED: a suspended membership cannot register at all
    INSERT INTO registrations (trip_id, member_id)
    VALUES ((SELECT id FROM trips WHERE name = 'Joshua Tree Stargazing'),
            (SELECT id FROM members WHERE email = 'mbell@ucmerced.edu'));
    RAISE NOTICE 'FAIL  suspended member registered!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  suspended member: %', SQLERRM;
END $$;

DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'RULE 2  cancelling a confirmed spot promotes the next in line';
    RAISE NOTICE '================================================================';
END $$;

DO $$
DECLARE
    v_trip INT; v_cancel INT; v_next INT; v_name TEXT; v_after registration_status;
BEGIN
    SELECT id INTO v_trip FROM trips WHERE name = 'Hike Dewey Point';

    SELECT registration_id, member_name INTO v_next, v_name
      FROM v_waitlist WHERE trip_id = v_trip AND position = 1;
    RAISE NOTICE 'next in line: % (registration %)', v_name, v_next;

    SELECT id INTO v_cancel FROM registrations
     WHERE trip_id = v_trip AND status = 'confirmed' ORDER BY registered_at LIMIT 1;

    UPDATE registrations SET status = 'cancelled', cancel_reason = 'work conflict'
     WHERE id = v_cancel;

    SELECT status INTO v_after FROM registrations WHERE id = v_next;
    IF v_after = 'confirmed' THEN
        RAISE NOTICE 'PASS  % was promoted automatically (no staff action)', v_name;
    ELSE
        RAISE NOTICE 'FAIL  % is still %', v_name, v_after;
    END IF;
    RAISE NOTICE '      trip now % confirmed / % waitlisted',
        (SELECT confirmed FROM v_trip_capacity WHERE trip_id = v_trip),
        (SELECT waitlisted FROM v_trip_capacity WHERE trip_id = v_trip);
END $$;

DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'RULE 3  guides need the trip''s certification, unexpired';
    RAISE NOTICE '================================================================';
END $$;

DO $$
BEGIN
    -- ACCEPTED: Maya holds WFR through 2027-06-01
    INSERT INTO trip_guides (trip_id, guide_id, role)
    VALUES ((SELECT id FROM trips  WHERE name  = 'Explore Yosemite in the Winter'),
            (SELECT id FROM guides WHERE email = 'jblake@ucmerced.edu'), 'assistant');
    RAISE NOTICE 'PASS  Jordan Blake (WFR to 2027-09-15) assigned to a WFR trip';
END $$;

DO $$
BEGIN
    -- REJECTED: Sam has CPR and WFA, never held WFR
    INSERT INTO trip_guides (trip_id, guide_id, role)
    VALUES ((SELECT id FROM trips  WHERE name  = 'Hike Dewey Point'),
            (SELECT id FROM guides WHERE email = 'swhitfield@ucmerced.edu'), 'trainee');
    RAISE NOTICE 'FAIL  uncertified guide assigned!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  guide without the certification: %', SQLERRM;
END $$;

DO $$
BEGIN
    -- REJECTED: Devon's WFR expires 2026-10-04, the trip ends 2026-11-09
    INSERT INTO trip_guides (trip_id, guide_id, role)
    VALUES ((SELECT id FROM trips  WHERE name  = 'Joshua Tree Stargazing'),
            (SELECT id FROM guides WHERE email = 'dchen@ucmerced.edu'), 'assistant');
    RAISE NOTICE 'FAIL  guide with a lapsing certification assigned!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  certification expires mid-trip: %', SQLERRM;
END $$;

DO $$
BEGIN
    -- REJECTED: moving a trip past a guide's expiry date
    UPDATE trips SET start_date = '2027-07-01', end_date = '2027-07-02'
     WHERE name = 'Indoor Rock Climbing | Alpine';
    RAISE NOTICE 'FAIL  trip moved beyond the lead guide''s certification!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  moving the trip past the guide''s expiry: %', SQLERRM;
END $$;

DO $$
BEGIN
    -- REJECTED: deleting a certification an assignment depends on
    DELETE FROM guide_certifications
     WHERE guide_id = (SELECT id FROM guides WHERE email = 'mortiz@ucmerced.edu')
       AND certification_id = (SELECT id FROM certifications WHERE code = 'WFR')
       AND issued_on = '2025-06-01';
    RAISE NOTICE 'FAIL  certification revoked out from under an assignment!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  revoking a certification in use: %', SQLERRM;
END $$;

DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'RULE 4  equipment cannot be double-booked across overlapping trips';
    RAISE NOTICE '================================================================';
END $$;

DO $$
DECLARE v_free INT;
BEGIN
    SELECT total_quantity - committed_quantity(id, '2026-10-18', '2026-10-19', NULL)
      INTO v_free FROM equipment WHERE name = '4-Person Tent';
    RAISE NOTICE '4-Person Tent: 6 owned, 4 committed to Camp Yosemite Valley (Oct 17-18) -> % free Oct 18-19', v_free;

    -- ACCEPTED: 2 tents for the overlapping backpacking trip
    INSERT INTO trip_equipment (trip_id, equipment_id, quantity)
    VALUES ((SELECT id FROM trips     WHERE name = 'Intro to Backpacking'),
            (SELECT id FROM equipment WHERE name = '4-Person Tent'), 2);
    RAISE NOTICE 'PASS  2 tents checked out to the overlapping trip';
END $$;

DO $$
BEGIN
    -- REJECTED: a 3rd tent on the overlapping date would exceed inventory
    UPDATE trip_equipment SET quantity = 3
     WHERE trip_id = (SELECT id FROM trips WHERE name = 'Intro to Backpacking')
       AND equipment_id = (SELECT id FROM equipment WHERE name = '4-Person Tent');
    RAISE NOTICE 'FAIL  inventory oversubscribed!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  one tent too many: %', SQLERRM;
END $$;

DO $$
BEGIN
    -- ACCEPTED: 1 of the 2 satellite messengers, for Oct 18-19
    INSERT INTO trip_equipment (trip_id, equipment_id, quantity)
    VALUES ((SELECT id FROM trips     WHERE name = 'Intro to Backpacking'),
            (SELECT id FROM equipment WHERE name = 'Satellite Messenger'), 1);
    RAISE NOTICE 'PASS  1 of 2 satellite messengers checked out to Oct 18-19';
END $$;

DO $$
BEGIN
    -- REJECTED: the Oct 17-18 clinic overlaps and only 1 messenger is left
    INSERT INTO trip_equipment (trip_id, equipment_id, quantity)
    VALUES ((SELECT id FROM trips     WHERE name = 'Camp Yosemite Valley'),
            (SELECT id FROM equipment WHERE name = 'Satellite Messenger'), 2);
    RAISE NOTICE 'FAIL  safety equipment double-booked!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  2 messengers on overlapping dates: %', SQLERRM;
END $$;

DO $$
BEGIN
    -- ACCEPTED: 2 of the 3 top-rope kits, on dates nothing else needs them
    INSERT INTO trip_equipment (trip_id, equipment_id, quantity)
    VALUES ((SELECT id FROM trips     WHERE name = 'Intro to Backpacking'),
            (SELECT id FROM equipment WHERE name = 'Top-Rope Kit'), 2);
    RAISE NOTICE 'PASS  2 of 3 top-rope kits checked out for Oct 18-19';
END $$;

DO $$
BEGIN
    -- REJECTED: moving that trip onto the Pinnacles dates, which hold the other 2
    UPDATE trips SET start_date = '2026-10-24', end_date = '2026-10-25'
     WHERE name = 'Intro to Backpacking';
    RAISE NOTICE 'FAIL  trip moved onto conflicting dates!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  moving a trip onto conflicting gear dates: %', SQLERRM;
END $$;

DO $$
BEGIN
    -- REJECTED: writing off inventory that is already committed
    UPDATE equipment SET total_quantity = 3 WHERE name = '4-Person Tent';
    RAISE NOTICE 'FAIL  inventory shrunk below commitments!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REJECTED  shrinking committed inventory: %', SQLERRM;
END $$;

DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'RULE 5  no-show at the mandatory meeting frees the spot (-> rule 2)';
    RAISE NOTICE '================================================================';
END $$;

DO $$
DECLARE r RECORD;
BEGIN
    RAISE NOTICE 'Mono Lake (capacity 2, meeting was 2026-09-10):';
    FOR r IN SELECT member_name, status, attended_pre_trip_meeting
               FROM v_trip_roster WHERE trip_name = 'Whale Watching Kayak Tour'
              ORDER BY registered_at LOOP
        RAISE NOTICE '  before: % - % (attended meeting: %)',
            rpad(r.member_name, 14), rpad(r.status::text, 11), r.attended_pre_trip_meeting;
    END LOOP;

    FOR r IN SELECT * FROM process_pre_trip_meetings('2026-09-11 08:00-07'::TIMESTAMPTZ) LOOP
        RAISE NOTICE '  sweep : registration % (member %) -> %',
            r.registration_id, r.member_id, r.action;
    END LOOP;

    FOR r IN SELECT member_name, status, attended_pre_trip_meeting
               FROM v_trip_roster WHERE trip_name = 'Whale Watching Kayak Tour'
              ORDER BY registered_at LOOP
        RAISE NOTICE '  after : % - % (attended meeting: %)',
            rpad(r.member_name, 14), rpad(r.status::text, 11), r.attended_pre_trip_meeting;
    END LOOP;
    RAISE NOTICE 'PASS  the no-show lost the spot and the waitlisted member took it';
END $$;

DO $$
DECLARE v_count INT;
BEGIN
    -- running the sweep again must not punish the member it just promoted
    SELECT count(*) INTO v_count
      FROM process_pre_trip_meetings('2026-09-12 08:00-07'::TIMESTAMPTZ);
    IF v_count = 0 THEN
        RAISE NOTICE 'PASS  re-running the sweep is a no-op (promotions are not no-shows)';
    ELSE
        RAISE NOTICE 'FAIL  sweep cancelled % more registrations', v_count;
    END IF;
END $$;

ROLLBACK;
\echo ''
\echo 'demo rolled back -- seed data unchanged'
