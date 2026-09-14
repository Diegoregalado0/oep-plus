-- Reporting views (brief section 7).
BEGIN;
SET search_path TO oep, public;

-- Capacity / waitlist status per trip.
CREATE VIEW v_trip_capacity AS
SELECT t.id                AS trip_id,
       t.name,
       t.destination,
       t.difficulty,
       t.start_date,
       t.end_date,
       t.status,
       t.capacity,
       (count(*) FILTER (WHERE r.status = 'confirmed'))::int  AS confirmed,
       GREATEST(t.capacity - (count(*) FILTER (WHERE r.status = 'confirmed'))::int, 0) AS spots_open,
       (count(*) FILTER (WHERE r.status = 'waitlisted'))::int AS waitlisted,
       (count(*) FILTER (WHERE r.status = 'cancelled'))::int  AS cancelled,
       (count(*) FILTER (WHERE r.status = 'no_show'))::int    AS no_shows,
       ((count(*) FILTER (WHERE r.status = 'confirmed'))::int) >= t.capacity AS is_full
FROM trips t
LEFT JOIN registrations r ON r.trip_id = t.id
GROUP BY t.id;

-- Live waitlist position per waitlisted registration.
CREATE VIEW v_waitlist AS
SELECT r.id AS registration_id,
       r.trip_id,
       t.name AS trip_name,
       r.member_id,
       m.first_name || ' ' || m.last_name AS member_name,
       r.registered_at,
       (row_number() OVER (PARTITION BY r.trip_id ORDER BY r.registered_at, r.id))::int AS position
FROM registrations r
JOIN trips   t ON t.id = r.trip_id
JOIN members m ON m.id = r.member_id
WHERE r.status = 'waitlisted';

-- Certifications expiring soon (or already expired), latest issue per pair.
CREATE VIEW v_certification_expiry AS
SELECT g.id AS guide_id,
       g.first_name || ' ' || g.last_name AS guide_name,
       g.email,
       c.code,
       c.name AS certification,
       gc.issued_on,
       gc.expires_on,
       (gc.expires_on - CURRENT_DATE) AS days_until_expiry,
       CASE WHEN gc.expires_on < CURRENT_DATE               THEN 'expired'
            WHEN gc.expires_on < CURRENT_DATE + 30          THEN 'critical'
            WHEN gc.expires_on < CURRENT_DATE + 90          THEN 'warning'
            ELSE 'ok' END AS urgency
FROM guide_certifications gc
JOIN guides g         ON g.id = gc.guide_id
JOIN certifications c  ON c.id = gc.certification_id
WHERE gc.expires_on = (
        SELECT max(expires_on) FROM guide_certifications x
        WHERE x.guide_id = gc.guide_id AND x.certification_id = gc.certification_id);

-- Damage / loss rate per item, from returned checkouts.
CREATE VIEW v_equipment_health AS
SELECT e.id AS equipment_id,
       e.name,
       e.category,
       e.total_quantity,
       e.condition AS current_condition,
       (count(te.id) FILTER (WHERE te.checked_in_at IS NOT NULL))::int AS times_returned,
       (count(te.id) FILTER (WHERE te.return_condition = 'damaged'))::int AS times_damaged,
       (count(te.id) FILTER (WHERE te.return_condition = 'lost'))::int    AS times_lost,
       ROUND(100.0 * (count(te.id) FILTER (WHERE te.return_condition IN ('damaged','lost'))::int)
             / NULLIF((count(te.id) FILTER (WHERE te.checked_in_at IS NOT NULL))::int, 0), 1)
           AS damage_loss_rate_pct
FROM equipment e
LEFT JOIN trip_equipment te ON te.equipment_id = e.id
GROUP BY e.id;

-- Units of each item free over a window, per trip that wants them.
CREATE VIEW v_equipment_commitments AS
SELECT te.id AS checkout_id, e.id AS equipment_id, e.name, e.total_quantity,
       t.id AS trip_id, t.name AS trip_name, t.start_date, t.end_date,
       te.quantity, te.checked_out_at, te.checked_in_at, te.return_condition,
       e.total_quantity - committed_quantity(e.id, t.start_date, t.end_date, NULL)
           AS free_during_trip
FROM trip_equipment te
JOIN equipment e ON e.id = te.equipment_id
JOIN trips     t ON t.id = te.trip_id;

-- Per-member history and payment totals.
CREATE VIEW v_member_history AS
SELECT m.id AS member_id,
       m.first_name || ' ' || m.last_name AS member_name,
       m.email,
       m.membership_type,
       m.membership_status,
       count(r.id)::int                                       AS registrations,
       (count(r.id) FILTER (WHERE r.status = 'completed'))::int  AS trips_completed,
       (count(r.id) FILTER (WHERE r.status = 'confirmed'))::int  AS upcoming_confirmed,
       (count(r.id) FILTER (WHERE r.status = 'waitlisted'))::int AS currently_waitlisted,
       (count(r.id) FILTER (WHERE r.status = 'cancelled'))::int  AS cancellations,
       (count(r.id) FILTER (WHERE r.status = 'no_show'))::int    AS no_shows,
       COALESCE(sum(r.amount_paid_cents) FILTER (
           WHERE r.payment_status = 'paid'), 0)            AS total_paid_cents,
       COALESCE(sum(r.amount_paid_cents) FILTER (
           WHERE r.payment_status = 'refunded'), 0)        AS refunded_cents
FROM members m
LEFT JOIN registrations r ON r.member_id = m.id
LEFT JOIN trips t        ON t.id = r.trip_id
GROUP BY m.id;

-- Revenue by month of trip start.
CREATE VIEW v_revenue_by_month AS
SELECT to_char(date_trunc('month', t.start_date), 'YYYY-MM') AS month,
       count(DISTINCT t.id)::int                                  AS trips,
       (count(r.id) FILTER (WHERE r.status IN ('confirmed','completed'))::int) AS seats_sold,
       COALESCE(sum(r.amount_paid_cents) FILTER (WHERE r.payment_status = 'paid'), 0)
           AS collected_cents,
       COALESCE(sum(r.amount_paid_cents) FILTER (WHERE r.payment_status = 'refunded'), 0)
           AS refunded_cents
FROM trips t
LEFT JOIN registrations r ON r.trip_id = t.id
GROUP BY 1
ORDER BY 1;

-- Trip roster, for guides and staff.
CREATE VIEW v_trip_roster AS
SELECT r.trip_id, t.name AS trip_name, r.id AS registration_id,
       m.id AS member_id, m.first_name || ' ' || m.last_name AS member_name,
       m.email, m.phone, r.status, r.payment_status, r.amount_paid_cents,
       r.attended_pre_trip_meeting, r.registered_at
FROM registrations r
JOIN trips   t ON t.id = r.trip_id
JOIN members m ON m.id = r.member_id;

COMMIT;
