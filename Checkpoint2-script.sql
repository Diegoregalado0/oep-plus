-- ============================================================================
-- CSE 111 Fall 2026: Project Checkpoint 2 Script
-- Project Title: OEP+: UC Merced Outdoor Experience Program
-- Team Members: Cameron Nguyen, Diego Regalado
-- File: Checkpoint2-script.sql
-- ============================================================================

-- ============================================================================
-- SCHEMA MODIFICATIONS SINCE CHECKPOINT 1
-- ============================================================================
-- 1. DBMS conversion: the Checkpoint 1 PostgreSQL schema was fully migrated
--    to SQLite3 as required. ENUM types were replaced with TEXT columns plus
--    CHECK constraints; SERIAL/IDENTITY keys became INTEGER PRIMARY KEY.
-- 2. Timestamp storage: TIMESTAMPTZ columns are stored as ISO-8601 TEXT so
--    SQLite can compare dates without Postgres-specific types.
-- 3. Lookup indexes: added trips(status) and registrations(member_id) to
--    speed status filters and member-history joins used in this script.
-- ============================================================================

-- ============================================================================
-- MEMBER CONTRIBUTIONS SUMMARY (GROUPED AT THE TOP)
-- ============================================================================
-- SECTION 1: SIMPLE STATEMENTS
-- Statement 01: Cameron Nguyen: 100%, Diego Regalado: 0%
-- Statement 02: Diego Regalado: 100%, Cameron Nguyen: 0%
-- Statement 03: Cameron Nguyen: 50%, Diego Regalado: 50%
-- Statement 04: Diego Regalado: 70%, Cameron Nguyen: 30%
-- Statement 05: Cameron Nguyen: 60%, Diego Regalado: 40%
-- Statement 06: Diego Regalado: 100%, Cameron Nguyen: 0%
-- Statement 07: Cameron Nguyen: 100%, Diego Regalado: 0%
-- Statement 08: Diego Regalado: 50%, Cameron Nguyen: 50%
-- Statement 09: Cameron Nguyen: 80%, Diego Regalado: 20%
-- Statement 10: Diego Regalado: 60%, Cameron Nguyen: 40%
--
-- SECTION 2: INTERMEDIATE STATEMENTS
-- Statement 11: Cameron Nguyen: 50%, Diego Regalado: 50%
-- Statement 12: Diego Regalado: 70%, Cameron Nguyen: 30%
-- Statement 13: Cameron Nguyen: 60%, Diego Regalado: 40%
-- Statement 14: Diego Regalado: 50%, Cameron Nguyen: 50%
-- Statement 15: Cameron Nguyen: 70%, Diego Regalado: 30%
-- Statement 16: Diego Regalado: 60%, Cameron Nguyen: 40%
-- Statement 17: Cameron Nguyen: 80%, Diego Regalado: 20%
-- Statement 18: Diego Regalado: 50%, Cameron Nguyen: 50%
-- Statement 19: Cameron Nguyen: 50%, Diego Regalado: 50%
-- Statement 20: Diego Regalado: 100%, Cameron Nguyen: 0%
-- Statement 21: Cameron Nguyen: 60%, Diego Regalado: 40%
--
-- SECTION 3: COMPLEX STATEMENTS
-- Statement 22: Cameron Nguyen: 50%, Diego Regalado: 50%
-- Statement 23: Diego Regalado: 70%, Cameron Nguyen: 30%
-- Statement 24: Cameron Nguyen: 70%, Diego Regalado: 30%
-- Statement 25: Diego Regalado: 50%, Cameron Nguyen: 50%
-- Statement 26: Cameron Nguyen: 60%, Diego Regalado: 40%
-- Statement 27: Diego Regalado: 80%, Cameron Nguyen: 20%
-- Statement 28: Cameron Nguyen: 50%, Diego Regalado: 50%
-- Statement 29: Diego Regalado: 50%, Cameron Nguyen: 50%
-- Statement 30: Cameron Nguyen: 70%, Diego Regalado: 30%
-- Statement 31: Diego Regalado: 60%, Cameron Nguyen: 40%
-- Statement 32: Cameron Nguyen: 50%, Diego Regalado: 50%
-- ============================================================================

-- Ensure SQLite foreign key constraints are enforced
PRAGMA foreign_keys = ON;

-- Set output format for readability during evaluation
.headers on
.mode column


-- ============================================================================
-- SECTION 1: SIMPLE STATEMENTS (Statements 1 to 10)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Statement 01: Active Student Members
-- Explanation: List the name, email, and join date of every member whose
--              membership type is student and whose status is still active.
-- ----------------------------------------------------------------------------
SELECT first_name, last_name, email, joined_on
FROM members
WHERE membership_type = 'student' AND membership_status = 'active'
ORDER BY last_name, first_name;

-- ----------------------------------------------------------------------------
-- Statement 02: Strenuous Upcoming Trips
-- Explanation: Find the name, destination, dates, and fee of open trips whose
--              difficulty is strenuous so staff can advertise harder outings.
-- ----------------------------------------------------------------------------
SELECT name, destination, start_date, end_date, fee_cents, capacity
FROM trips
WHERE difficulty = 'strenuous' AND status = 'open'
ORDER BY start_date;

-- ----------------------------------------------------------------------------
-- Statement 03: Distinct Registration Status Values
-- Explanation: List every unique registration status currently stored so we
--              can verify the allowed workflow states against the CHECK list.
-- ----------------------------------------------------------------------------
SELECT DISTINCT status
FROM registrations
ORDER BY status;

-- ----------------------------------------------------------------------------
-- Statement 04: Campus Email Pattern Search
-- Explanation: Find members whose email is a UC Merced address, using LIKE
--              pattern matching on the domain.
-- ----------------------------------------------------------------------------
SELECT first_name, last_name, email, phone
FROM members
WHERE email LIKE '%@ucmerced.edu'
ORDER BY last_name;

-- ----------------------------------------------------------------------------
-- Statement 05: Aggregate Trip Fee Metrics
-- Explanation: Compute how many trips exist, the total of all listed fees,
--              and the average fee in cents across the catalog.
-- ----------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_trips,
    SUM(fee_cents) AS catalog_fee_cents,
    ROUND(AVG(fee_cents), 2) AS average_fee_cents
FROM trips;

-- ----------------------------------------------------------------------------
-- Statement 06: Insert New Community Member
-- Explanation: Add Luz Fernandez as a new community member so staff can
--              register her for future trips.
-- ----------------------------------------------------------------------------
INSERT INTO members (id, first_name, last_name, email, phone, membership_type, membership_status, joined_on)
VALUES (12, 'Luz', 'Fernandez', 'lfernandez@ucmerced.edu', '209-555-0212', 'community', 'active', '2026-09-12');

-- ----------------------------------------------------------------------------
-- Statement 07: Insert New Equipment Item
-- Explanation: Record a new camp stove in the cooking category with five
--              units on hand and a new-condition rating.
-- ----------------------------------------------------------------------------
INSERT INTO equipment (id, name, category, total_quantity, condition, purchased_on, notes)
VALUES (13, 'Camp Stove', 'cooking', 5, 'new', '2026-09-01', 'canister stoves for backpacking clinics');

-- ----------------------------------------------------------------------------
-- Statement 08: Update Member Phone Number
-- Explanation: Correct Alex Nguyen's phone number after he reported a new
--              campus contact line.
-- ----------------------------------------------------------------------------
UPDATE members
SET phone = '209-555-0299'
WHERE email = 'anguyen@ucmerced.edu';

-- ----------------------------------------------------------------------------
-- Statement 09: Flag Poor-Condition Gear for Replacement
-- Explanation: Append a replacement note onto every equipment row whose
--              current condition is poor so inventory staff can pull it.
-- ----------------------------------------------------------------------------
UPDATE equipment
SET notes = COALESCE(notes || '; ', '') || 'flagged for replacement review'
WHERE condition = 'poor';

-- ----------------------------------------------------------------------------
-- Statement 10: Delete the Newly Added Member
-- Explanation: Remove the Luz Fernandez test row inserted in Statement 06
--              because she has no registrations and was added only for DML.
-- ----------------------------------------------------------------------------
DELETE FROM members
WHERE id = 12;


-- ============================================================================
-- SECTION 2: INTERMEDIATE STATEMENTS (Statements 11 to 21)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Statement 11: Registrations with Member and Trip Names (Multi-Table Join)
-- Explanation: Join registrations to members and trips so each signup shows
--              the person, the outing, status, and amount paid.
-- ----------------------------------------------------------------------------
SELECT
    M.first_name || ' ' || M.last_name AS member_name,
    T.name AS trip_name,
    R.status,
    R.payment_status,
    R.amount_paid_cents,
    R.registered_at
FROM registrations R
JOIN members M ON R.member_id = M.id
JOIN trips T ON R.trip_id = T.id
ORDER BY T.start_date, member_name;

-- ----------------------------------------------------------------------------
-- Statement 12: Guide Roster per Trip (Join through Junction Table)
-- Explanation: List every trip-guide assignment with the guide's name and
--              role, including the certification the trip requires if any.
-- ----------------------------------------------------------------------------
SELECT
    T.name AS trip_name,
    G.first_name || ' ' || G.last_name AS guide_name,
    TG.role,
    C.code AS required_cert
FROM trip_guides TG
JOIN trips T ON TG.trip_id = T.id
JOIN guides G ON TG.guide_id = G.id
LEFT JOIN certifications C ON T.required_certification_id = C.id
ORDER BY T.start_date, TG.role;

-- ----------------------------------------------------------------------------
-- Statement 13: Registration Counts by Trip (GROUP BY)
-- Explanation: Count how many registration rows exist for each trip and
--              total the collected cents, grouped by trip name and status.
-- ----------------------------------------------------------------------------
SELECT
    T.id AS trip_id,
    T.name AS trip_name,
    T.status AS trip_status,
    COUNT(R.id) AS registration_rows,
    SUM(R.amount_paid_cents) AS amount_recorded_cents
FROM trips T
JOIN registrations R ON T.id = R.trip_id
GROUP BY T.id, T.name, T.status
ORDER BY T.start_date;

-- ----------------------------------------------------------------------------
-- Statement 14: Guides Holding Several Certification Types (HAVING)
-- Explanation: Identify guides who hold at least two distinct certification
--              types and report how many types they currently have on file.
-- ----------------------------------------------------------------------------
SELECT
    G.id AS guide_id,
    G.first_name || ' ' || G.last_name AS guide_name,
    COUNT(DISTINCT GC.certification_id) AS distinct_certs
FROM guides G
JOIN guide_certifications GC ON G.id = GC.guide_id
GROUP BY G.id, guide_name
HAVING COUNT(DISTINCT GC.certification_id) >= 2
ORDER BY distinct_certs DESC, guide_name;

-- ----------------------------------------------------------------------------
-- Statement 15: Trips That Currently Have a Waitlist (HAVING)
-- Explanation: Find open trips whose waitlisted registration count is at
--              least 1 so staff can monitor overflow demand.
-- ----------------------------------------------------------------------------
SELECT
    T.id AS trip_id,
    T.name AS trip_name,
    T.capacity,
    COUNT(R.id) AS waitlisted_count
FROM trips T
JOIN registrations R ON T.id = R.trip_id
WHERE R.status = 'waitlisted'
GROUP BY T.id, T.name, T.capacity
HAVING COUNT(R.id) >= 1
ORDER BY waitlisted_count DESC;

-- ----------------------------------------------------------------------------
-- Statement 16: Members With No Registrations (LEFT OUTER JOIN)
-- Explanation: Use a left join and a NULL filter to find members who have
--              never signed up for any trip.
-- ----------------------------------------------------------------------------
SELECT
    M.id,
    M.first_name,
    M.last_name,
    M.email,
    M.membership_status
FROM members M
LEFT JOIN registrations R ON M.id = R.member_id
WHERE R.id IS NULL;

-- ----------------------------------------------------------------------------
-- Statement 17: Trips Priced Above the Catalog Average (Scalar Subquery)
-- Explanation: Return trips whose fee is strictly higher than the average
--              fee_cents of all trips in the catalog.
-- ----------------------------------------------------------------------------
SELECT
    T.id,
    T.name,
    T.fee_cents,
    T.difficulty
FROM trips T
WHERE T.fee_cents > (
    SELECT AVG(T2.fee_cents)
    FROM trips T2
)
ORDER BY T.fee_cents DESC;

-- ----------------------------------------------------------------------------
-- Statement 18: Paid Revenue by Completed Trip
-- Explanation: Calculate collected cents (status completed or confirmed and
--              payment paid) for each trip that already has registrations.
-- ----------------------------------------------------------------------------
SELECT
    T.id AS trip_id,
    T.name AS trip_name,
    COUNT(R.id) AS paid_seats,
    SUM(R.amount_paid_cents) AS collected_cents
FROM trips T
JOIN registrations R ON T.id = R.trip_id
WHERE R.payment_status = 'paid'
  AND R.status IN ('confirmed', 'completed')
GROUP BY T.id, T.name
ORDER BY collected_cents DESC;

-- ----------------------------------------------------------------------------
-- Statement 19: Guide Workload Including Unassigned Guides (LEFT JOIN)
-- Explanation: Count how many trip assignments each guide has, keeping
--              guides who have zero assignments via a left join.
-- ----------------------------------------------------------------------------
SELECT
    G.id AS guide_id,
    G.first_name || ' ' || G.last_name AS guide_name,
    COUNT(TG.trip_id) AS trips_assigned
FROM guides G
LEFT JOIN trip_guides TG ON G.id = TG.guide_id
GROUP BY G.id, guide_name
ORDER BY trips_assigned DESC, guide_name;

-- ----------------------------------------------------------------------------
-- Statement 20: Record Meeting Attendance (Conditional UPDATE)
-- Explanation: Mark Bianca Lopez as having attended the pre-trip meeting for
--              the whale-watching tour, which is required before departure.
-- ----------------------------------------------------------------------------
UPDATE registrations
SET attended_pre_trip_meeting = 1
WHERE trip_id = (
        SELECT id FROM trips WHERE name = 'Whale Watching Kayak Tour'
      )
  AND member_id = (
        SELECT id FROM members WHERE email = 'blopez@ucmerced.edu'
      );

-- ----------------------------------------------------------------------------
-- Statement 21: Members Never Registered for Dewey Point (NOT IN Subquery)
-- Explanation: List members who do not appear on the Hike Dewey Point
--              registration list, using a NOT IN subquery on member_id.
-- ----------------------------------------------------------------------------
SELECT id, first_name, last_name, email
FROM members
WHERE id NOT IN (
    SELECT R.member_id
    FROM registrations R
    JOIN trips T ON R.trip_id = T.id
    WHERE T.name = 'Hike Dewey Point'
)
ORDER BY last_name;


-- ============================================================================
-- SECTION 3: COMPLEX STATEMENTS (Statements 22 to 32)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Statement 22: Correlated Subquery with EXISTS (Waitlisted on a Full Trip)
-- Explanation: Find members who have at least one waitlisted registration on
--              a trip that already has as many confirmed seats as its capacity.
-- ----------------------------------------------------------------------------
SELECT M.id, M.first_name, M.last_name, M.email
FROM members M
WHERE EXISTS (
    SELECT 1
    FROM registrations R
    JOIN trips T ON R.trip_id = T.id
    WHERE R.member_id = M.id
      AND R.status = 'waitlisted'
      AND (
            SELECT COUNT(*)
            FROM registrations R2
            WHERE R2.trip_id = T.id AND R2.status = 'confirmed'
          ) >= T.capacity
)
ORDER BY M.last_name;

-- ----------------------------------------------------------------------------
-- Statement 23: Set Difference (EXCEPT) for Completed vs No-Show Members
-- Explanation: Return members who have a completed trip registration but do
--              not appear in the no-show set, using EXCEPT.
-- ----------------------------------------------------------------------------
SELECT M.id, M.first_name || ' ' || M.last_name AS member_name
FROM members M
JOIN registrations R ON M.id = R.member_id
WHERE R.status = 'completed'
EXCEPT
SELECT M.id, M.first_name || ' ' || M.last_name AS member_name
FROM members M
JOIN registrations R ON M.id = R.member_id
WHERE R.status = 'no_show'
ORDER BY member_name;

-- ----------------------------------------------------------------------------
-- Statement 24: Set Intersection (INTERSECT) for Repeat Participants
-- Explanation: Find members who completed Explore Yosemite in the Winter and
--              also completed Explore Santa Cruz.
-- ----------------------------------------------------------------------------
SELECT M.id, M.first_name || ' ' || M.last_name AS member_name
FROM members M
JOIN registrations R ON M.id = R.member_id
JOIN trips T ON R.trip_id = T.id
WHERE T.name = 'Explore Yosemite in the Winter' AND R.status = 'completed'
INTERSECT
SELECT M.id, M.first_name || ' ' || M.last_name AS member_name
FROM members M
JOIN registrations R ON M.id = R.member_id
JOIN trips T ON R.trip_id = T.id
WHERE T.name = 'Explore Santa Cruz' AND R.status = 'completed';

-- ----------------------------------------------------------------------------
-- Statement 25: Set Union (UNION ALL) for Program Contact Directory
-- Explanation: Build a combined directory of member and guide emails with an
--              affiliation label so staff have one contact list.
-- ----------------------------------------------------------------------------
SELECT
    first_name || ' ' || last_name AS contact_name,
    email AS contact_email,
    'MEMBER' AS affiliation
FROM members
UNION ALL
SELECT
    first_name || ' ' || last_name AS contact_name,
    email AS contact_email,
    'GUIDE' AS affiliation
FROM guides
ORDER BY contact_name;

-- ----------------------------------------------------------------------------
-- Statement 26: Common Table Expression (CTE) for Trip Fill Rate
-- Explanation: Use a CTE to count confirmed seats per trip, then compute the
--              fill percentage against listed capacity.
-- ----------------------------------------------------------------------------
WITH TripFill AS (
    SELECT
        T.id AS trip_id,
        T.name AS trip_name,
        T.status,
        T.capacity,
        SUM(CASE WHEN R.status = 'confirmed' THEN 1 ELSE 0 END) AS confirmed_seats,
        SUM(CASE WHEN R.status = 'waitlisted' THEN 1 ELSE 0 END) AS waitlisted_seats
    FROM trips T
    LEFT JOIN registrations R ON T.id = R.trip_id
    GROUP BY T.id, T.name, T.status, T.capacity
)
SELECT
    trip_id,
    trip_name,
    status,
    capacity,
    confirmed_seats,
    waitlisted_seats,
    ROUND((confirmed_seats * 100.0) / capacity, 1) AS fill_pct
FROM TripFill
WHERE status IN ('open', 'completed')
ORDER BY fill_pct DESC, trip_name;

-- ----------------------------------------------------------------------------
-- Statement 27: Window Function (ROW_NUMBER) for Live Waitlist Position
-- Explanation: Rank waitlisted registrations per trip by signup time using
--              ROW_NUMBER so the next promotion candidate is position 1.
-- ----------------------------------------------------------------------------
SELECT
    T.name AS trip_name,
    M.first_name || ' ' || M.last_name AS member_name,
    R.registered_at,
    ROW_NUMBER() OVER (
        PARTITION BY R.trip_id
        ORDER BY R.registered_at, R.id
    ) AS waitlist_position
FROM registrations R
JOIN trips T ON R.trip_id = T.id
JOIN members M ON R.member_id = M.id
WHERE R.status = 'waitlisted'
ORDER BY trip_name, waitlist_position;

-- ----------------------------------------------------------------------------
-- Statement 28: DDL View Creation for Trip Capacity Dashboard
-- Explanation: Create a staff view that reports confirmed, waitlisted, and
--              remaining spots for every trip.
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS View_TripCapacityDashboard;

CREATE VIEW View_TripCapacityDashboard AS
SELECT
    T.id AS trip_id,
    T.name AS trip_name,
    T.destination,
    T.start_date,
    T.status,
    T.capacity,
    SUM(CASE WHEN R.status = 'confirmed' THEN 1 ELSE 0 END) AS confirmed,
    SUM(CASE WHEN R.status = 'waitlisted' THEN 1 ELSE 0 END) AS waitlisted,
    CASE
        WHEN T.capacity - SUM(CASE WHEN R.status = 'confirmed' THEN 1 ELSE 0 END) < 0
            THEN 0
        ELSE T.capacity - SUM(CASE WHEN R.status = 'confirmed' THEN 1 ELSE 0 END)
    END AS spots_open
FROM trips T
LEFT JOIN registrations R ON T.id = R.trip_id
GROUP BY T.id, T.name, T.destination, T.start_date, T.status, T.capacity;

-- ----------------------------------------------------------------------------
-- Statement 29: Query Against the Capacity Dashboard View
-- Explanation: Read View_TripCapacityDashboard for open trips that are full
--              or have a waitlist so staff can act on overflow.
-- ----------------------------------------------------------------------------
SELECT trip_id, trip_name, capacity, confirmed, waitlisted, spots_open
FROM View_TripCapacityDashboard
WHERE status = 'open' AND (spots_open = 0 OR waitlisted > 0)
ORDER BY start_date;

-- ----------------------------------------------------------------------------
-- Statement 30: Auto-Charge Trip Fee Trigger
-- Explanation: Create a trigger that copies the trip fee into amount_paid_cents
--              whenever a new paid registration is inserted with a zero amount.
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_SetRegistrationFeeOnInsert;

CREATE TRIGGER trg_SetRegistrationFeeOnInsert
AFTER INSERT ON registrations
FOR EACH ROW
WHEN NEW.amount_paid_cents = 0 AND NEW.payment_status = 'paid'
BEGIN
    UPDATE registrations
    SET amount_paid_cents = (
            SELECT fee_cents FROM trips WHERE id = NEW.trip_id
        )
    WHERE id = NEW.id;
END;

-- ----------------------------------------------------------------------------
-- Statement 31: Cancellation Timestamp Trigger
-- Explanation: Create a trigger that stamps cancelled_at when a registration
--              status changes to cancelled or no_show and the timestamp is empty.
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_StampCancellationTime;

CREATE TRIGGER trg_StampCancellationTime
AFTER UPDATE OF status ON registrations
FOR EACH ROW
WHEN NEW.status IN ('cancelled', 'no_show')
 AND OLD.status NOT IN ('cancelled', 'no_show')
 AND NEW.cancelled_at IS NULL
BEGIN
    UPDATE registrations
    SET cancelled_at = datetime('now')
    WHERE id = NEW.id;
END;

-- ----------------------------------------------------------------------------
-- Statement 32: Cross-Tab Analytics with CASE Expressions
-- Explanation: Pivot each trip's registrations into confirmed, waitlisted,
--              completed, cancelled, and no-show counts using CASE.
-- ----------------------------------------------------------------------------
SELECT
    T.id AS trip_id,
    T.name AS trip_name,
    T.status AS trip_status,
    SUM(CASE WHEN R.status = 'confirmed'  THEN 1 ELSE 0 END) AS confirmed,
    SUM(CASE WHEN R.status = 'waitlisted' THEN 1 ELSE 0 END) AS waitlisted,
    SUM(CASE WHEN R.status = 'completed'  THEN 1 ELSE 0 END) AS completed,
    SUM(CASE WHEN R.status = 'cancelled'  THEN 1 ELSE 0 END) AS cancelled,
    SUM(CASE WHEN R.status = 'no_show'    THEN 1 ELSE 0 END) AS no_shows,
    COUNT(R.id) AS total_registrations
FROM trips T
LEFT JOIN registrations R ON T.id = R.trip_id
GROUP BY T.id, T.name, T.status
ORDER BY T.start_date;
