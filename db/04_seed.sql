-- Seed data. "Today" for this dataset is 2026-09-12.
-- Includes past trips (history/revenue reporting), upcoming trips, a full trip
-- with a live waitlist, and a trip whose pre-trip meeting has already passed.
BEGIN;
SET search_path TO oep, public;

TRUNCATE registrations, trip_equipment, trip_guides, guide_certifications,
         trips, equipment, certifications, guides, members RESTART IDENTITY CASCADE;

-- ------------------------------------------------------ certification catalog
INSERT INTO certifications (code, name, issuing_body, description, validity_months) VALUES
 ('WFR',        'Wilderness First Responder',  'NOLS / SOLO',  '80-hour backcountry medicine certification', 24),
 ('WFA',        'Wilderness First Aid',        'NOLS',         '16-hour front-country first aid', 24),
 ('CPR',        'CPR / AED',                   'American Red Cross', 'Basic life support', 24),
 ('SWIFTWATER', 'Swiftwater Rescue Technician','ACA',          'Moving-water rescue for paddling trips', 36),
 ('SPI',        'Single Pitch Instructor',     'AMGA',         'Top-rope and single-pitch climbing instruction', 36),
 ('AVY1',       'Avalanche Level 1',           'AIARE',        'Winter travel in avalanche terrain', NULL);

-- ------------------------------------------------------------------- guides
INSERT INTO guides (first_name, last_name, email, phone, hired_on) VALUES
 ('Maya',   'Ortiz',      'mortiz@ucmerced.edu',    '209-555-0101', '2023-08-14'),
 ('Devon',  'Chen',       'dchen@ucmerced.edu',     '209-555-0102', '2024-01-09'),
 ('Priya',  'Raman',      'praman@ucmerced.edu',    '209-555-0103', '2024-09-03'),
 ('Sam',    'Whitfield',  'swhitfield@ucmerced.edu','209-555-0104', '2025-08-25'),
 ('Jordan', 'Blake',      'jblake@ucmerced.edu',    '209-555-0105', '2022-06-01');

-- guide_id, cert code, issued, expires
INSERT INTO guide_certifications (guide_id, certification_id, issued_on, expires_on, certificate_no)
SELECT g.id, c.id, v.issued, v.expires, v.cert_no
FROM (VALUES
 -- Maya: fully current
 ('mortiz@ucmerced.edu',    'WFR',        DATE '2025-06-01', DATE '2027-06-01', 'WFR-88201'),
 ('mortiz@ucmerced.edu',    'CPR',        DATE '2025-06-01', DATE '2027-06-01', 'CPR-11904'),
 ('mortiz@ucmerced.edu',    'WFR',        DATE '2023-05-20', DATE '2025-05-20', 'WFR-70118'), -- prior cycle
 -- Devon: WFR expires in three weeks -> shows up as "critical" in the expiry report
 ('dchen@ucmerced.edu',     'WFR',        DATE '2024-10-04', DATE '2026-10-04', 'WFR-90233'),
 ('dchen@ucmerced.edu',     'CPR',        DATE '2026-02-11', DATE '2028-02-11', 'CPR-12877'),
 -- Priya: swiftwater current, WFR lapsed in June
 ('praman@ucmerced.edu',    'SWIFTWATER', DATE '2025-04-18', DATE '2028-04-18', 'SWR-4410'),
 ('praman@ucmerced.edu',    'WFR',        DATE '2024-06-30', DATE '2026-06-30', 'WFR-89044'),
 ('praman@ucmerced.edu',    'CPR',        DATE '2025-04-18', DATE '2027-04-18', 'CPR-12011'),
 -- Sam: CPR and WFA only, no WFR
 ('swhitfield@ucmerced.edu','CPR',        DATE '2026-01-20', DATE '2028-01-20', 'CPR-13320'),
 ('swhitfield@ucmerced.edu','WFA',        DATE '2026-01-20', DATE '2028-01-20', 'WFA-2298'),
 -- Jordan: climbing instructor, WFR current
 ('jblake@ucmerced.edu',    'SPI',        DATE '2024-03-02', DATE '2027-03-02', 'SPI-7781'),
 ('jblake@ucmerced.edu',    'WFR',        DATE '2025-09-15', DATE '2027-09-15', 'WFR-90881'),
 ('jblake@ucmerced.edu',    'AVY1',       DATE '2023-12-08', DATE '2030-12-08', 'AVY-3310')
) AS v(email, code, issued, expires, cert_no)
JOIN guides g         ON g.email = v.email
JOIN certifications c ON c.code  = v.code;

-- ------------------------------------------------------------------ members
INSERT INTO members (first_name, last_name, email, phone, membership_type, membership_status, joined_on) VALUES
 ('Alex',   'Nguyen',  'anguyen@ucmerced.edu', '209-555-0201', 'student', 'active', '2025-08-20'),
 ('Bianca', 'Lopez',   'blopez@ucmerced.edu',  '209-555-0202', 'student', 'active', '2025-08-21'),
 ('Chris',  'Okafor',  'cokafor@ucmerced.edu', '209-555-0203', 'student', 'active', '2025-09-02'),
 ('Dana',   'Kim',     'dkim@ucmerced.edu',    '209-555-0204', 'student', 'active', '2025-09-04'),
 ('Eli',    'Torres',  'etorres@ucmerced.edu', '209-555-0205', 'student', 'active', '2026-01-12'),
 ('Farah',  'Haddad',  'fhaddad@ucmerced.edu', '209-555-0206', 'faculty', 'active', '2024-02-19'),
 ('Gabe',   'Molina',  'gmolina@ucmerced.edu', '209-555-0207', 'staff',   'active', '2024-05-30'),
 ('Hana',   'Sato',    'hsato@ucmerced.edu',   '209-555-0208', 'student', 'active', '2026-01-15'),
 ('Ivan',   'Petrov',  'ipetrov@ucmerced.edu', '209-555-0209', 'student', 'active', '2026-02-01'),
 ('Kofi',   'Mensah',  'kmensah@ucmerced.edu', '209-555-0211', 'student', 'active', '2026-08-28');

-- ---------------------------------------------------------------- equipment
INSERT INTO equipment (name, category, total_quantity, condition, purchased_on, notes) VALUES
 ('4-Person Tent',        'shelter',    6,  'good', '2024-05-02', NULL),
 ('2-Person Tent',        'shelter',    8,  'good', '2023-04-18', NULL),
 ('65L Backpack',         'packs',      20, 'good', '2023-04-18', NULL),
 ('Sleeping Bag 20F',     'sleep',      18, 'fair', '2022-09-30', 'oldest batch due for replacement'),
 ('Bear Canister',        'storage',    10, 'good', '2024-05-02', NULL),
 ('Whitewater Kayak',     'paddling',   8,  'good', '2025-03-11', NULL),
 ('PFD Type V',           'paddling',   14, 'good', '2025-03-11', NULL),
 ('Climbing Helmet',      'climbing',   12, 'good', '2024-08-15', NULL),
 ('Top-Rope Kit',         'climbing',   3,  'good', '2024-08-15', 'rope, quickdraws, anchor material'),
 ('Satellite Messenger',  'safety',     2,  'good', '2025-01-20', 'one per group, mandatory backcountry'),
 ('Group First Aid Kit',  'safety',     4,  'good', '2025-01-20', NULL),
 ('Trekking Poles (pair)','packs',      10, 'poor', '2021-10-05', 'frequently bent');

-- -------------------------------------------------------------------- trips
INSERT INTO trips (name, destination, difficulty, start_date, end_date, capacity,
                   fee_cents, required_certification_id, pre_trip_meeting_at, status)
SELECT v.name, v.dest, v.diff::difficulty_level, v.sd, v.ed, v.cap, v.fee,
       (SELECT id FROM certifications WHERE code = v.cert), v.meeting, v.st::trip_status
FROM (VALUES
 -- completed, spring 2026 (history + revenue + equipment wear)
 ('Explore Yosemite in the Winter','Yosemite NP',     'moderate', DATE '2026-03-14', DATE '2026-03-16', 10, 8500,  'WFR',        TIMESTAMPTZ '2026-03-10 18:00-07', 'open'),
 ('Explore Santa Cruz',            'Santa Cruz',      'easy',     DATE '2026-04-11', DATE '2026-04-11', 12, 3000,  NULL,         NULL,                             'open'),
 ('Hike Gaylor Lakes',             'Tuolumne Meadows','strenuous',DATE '2026-05-02', DATE '2026-05-04', 8,  11000, 'WFR',        TIMESTAMPTZ '2026-04-28 18:00-07', 'open'),
 -- open, meeting already in the past (feeds the no-show sweep)
 ('Whale Watching Kayak Tour',     'Monterey Bay',    'easy',     DATE '2026-09-19', DATE '2026-09-19', 2,  4000,  'SWIFTWATER', TIMESTAMPTZ '2026-09-10 18:00-07', 'open'),
 -- open, upcoming
 ('Hike Dewey Point',              'Yosemite NP',     'strenuous',DATE '2026-10-10', DATE '2026-10-10', 3,  4500,  'WFR',        TIMESTAMPTZ '2026-10-06 18:00-07', 'open'),
 ('Camp Yosemite Valley',          'Yosemite Valley', 'moderate', DATE '2026-10-17', DATE '2026-10-18', 8,  6000,  'WFR',        TIMESTAMPTZ '2026-10-13 18:00-07', 'open'),
 ('Intro to Backpacking',          'Merced River',    'moderate', DATE '2026-10-18', DATE '2026-10-19', 6,  2500,  'WFR',        NULL,                             'open'),
 ('Indoor Rock Climbing | Alpine', 'Alpine, Modesto', 'moderate', DATE '2026-10-24', DATE '2026-10-25', 6,  7500,  'SPI',        TIMESTAMPTZ '2026-10-20 18:00-07', 'open'),
 ('Joshua Tree Stargazing',        'Joshua Tree NP',  'strenuous',DATE '2026-11-06', DATE '2026-11-09', 10, 13500, 'WFR',        TIMESTAMPTZ '2026-11-02 18:00-07', 'open'),
 ('Hike Lembert Dome and Dog Lake','Tuolumne Meadows','moderate', DATE '2027-01-16', DATE '2027-01-17', 8,  9000,  'AVY1',       TIMESTAMPTZ '2027-01-12 18:00-08', 'draft')
) AS v(name, dest, diff, sd, ed, cap, fee, cert, meeting, st);

-- Past trips are seeded as 'open' so that historical registrations pass the
-- same triggers a live registration would; they are closed out at the end.

-- ------------------------------------------------------- guide assignments
INSERT INTO trip_guides (trip_id, guide_id, role)
SELECT t.id, g.id, v.role::guide_role
FROM (VALUES
 ('Explore Yosemite in the Winter','mortiz@ucmerced.edu',    'lead'),
 ('Explore Santa Cruz',            'swhitfield@ucmerced.edu','lead'),      -- no certification required
 ('Explore Santa Cruz',            'dchen@ucmerced.edu',     'assistant'),
 ('Hike Gaylor Lakes',             'jblake@ucmerced.edu',    'lead'),
 ('Whale Watching Kayak Tour',     'praman@ucmerced.edu',    'lead'),      -- swiftwater, current
 ('Hike Dewey Point',              'mortiz@ucmerced.edu',    'lead'),
 ('Camp Yosemite Valley',          'jblake@ucmerced.edu',    'lead'),
 ('Intro to Backpacking',          'mortiz@ucmerced.edu',    'lead'),
 ('Indoor Rock Climbing | Alpine', 'jblake@ucmerced.edu',    'lead'),      -- single pitch instructor
 ('Joshua Tree Stargazing',        'mortiz@ucmerced.edu',    'lead'),
 ('Joshua Tree Stargazing',        'jblake@ucmerced.edu',    'assistant')
) AS v(trip, email, role)
JOIN trips  t ON t.name  = v.trip
JOIN guides g ON g.email = v.email;

-- ----------------------------------------------------- equipment checkouts
INSERT INTO trip_equipment (trip_id, equipment_id, quantity, checked_out_at, checked_in_at, return_condition, notes)
SELECT t.id, e.id, v.qty, v.out_at, v.in_at, v.cond::equipment_condition, v.notes
FROM (VALUES
 -- past trips, gear returned (drives the damage/loss report)
 ('Explore Yosemite in the Winter','2-Person Tent',        5, TIMESTAMPTZ '2026-03-13 09:00-07', TIMESTAMPTZ '2026-03-17 16:00-07', 'good',    NULL),
 ('Explore Yosemite in the Winter','65L Backpack',        10, TIMESTAMPTZ '2026-03-13 09:00-07', TIMESTAMPTZ '2026-03-17 16:00-07', 'fair',    NULL),
 ('Explore Yosemite in the Winter','Trekking Poles (pair)',6, TIMESTAMPTZ '2026-03-13 09:00-07', TIMESTAMPTZ '2026-03-17 16:00-07', 'damaged', 'two pairs bent beyond repair'),
 ('Explore Yosemite in the Winter','Satellite Messenger',  1, TIMESTAMPTZ '2026-03-13 09:00-07', TIMESTAMPTZ '2026-03-17 16:00-07', 'good',    NULL),
 ('Explore Santa Cruz',    'Group First Aid Kit',  2, TIMESTAMPTZ '2026-04-10 12:00-07', TIMESTAMPTZ '2026-04-12 10:00-07', 'good',    NULL),
 ('Explore Santa Cruz',    'Trekking Poles (pair)',4, TIMESTAMPTZ '2026-04-10 12:00-07', TIMESTAMPTZ '2026-04-12 10:00-07', 'damaged', 'one pair snapped'),
 ('Hike Gaylor Lakes',      '4-Person Tent',        3, TIMESTAMPTZ '2026-05-01 08:00-07', TIMESTAMPTZ '2026-05-05 17:00-07', 'good',    NULL),
 ('Hike Gaylor Lakes',      'Sleeping Bag 20F',     8, TIMESTAMPTZ '2026-05-01 08:00-07', TIMESTAMPTZ '2026-05-05 17:00-07', 'fair',    NULL),
 ('Hike Gaylor Lakes',      'Satellite Messenger',  1, TIMESTAMPTZ '2026-05-01 08:00-07', TIMESTAMPTZ '2026-05-05 17:00-07', 'lost',    'dropped in a creek crossing'),
 ('Hike Gaylor Lakes',      'Trekking Poles (pair)',5, TIMESTAMPTZ '2026-05-01 08:00-07', TIMESTAMPTZ '2026-05-05 17:00-07', 'good',    NULL),
 -- upcoming trips, gear committed but not yet returned
 ('Whale Watching Kayak Tour',    'Whitewater Kayak',     2, NULL, NULL, NULL, NULL),
 ('Whale Watching Kayak Tour',    'PFD Type V',           3, NULL, NULL, NULL, NULL),
 ('Hike Dewey Point',             'Group First Aid Kit',  1, NULL, NULL, NULL, NULL),
 ('Camp Yosemite Valley',         '4-Person Tent',        4, NULL, NULL, NULL, NULL),
 ('Camp Yosemite Valley',         'Sleeping Bag 20F',     8, NULL, NULL, NULL, NULL),
 ('Indoor Rock Climbing | Alpine','Climbing Helmet',      6, NULL, NULL, NULL, NULL),
 ('Indoor Rock Climbing | Alpine','Top-Rope Kit',         2, NULL, NULL, NULL, NULL),
 ('Joshua Tree Stargazing',       '4-Person Tent',        3, NULL, NULL, NULL, NULL),
 ('Joshua Tree Stargazing',       'Bear Canister',        8, NULL, NULL, NULL, NULL),
 ('Joshua Tree Stargazing',       'Satellite Messenger',  1, NULL, NULL, NULL, NULL)
) AS v(trip, item, qty, out_at, in_at, cond, notes)
JOIN trips     t ON t.name = v.trip
JOIN equipment e ON e.name = v.item;

-- Equipment rented for the (already lost) satellite messenger is still on the
-- books at 2 units; one is out with Sequoia, leaving 1 for overlapping trips.

-- -------------------------------------------------------------registrations
-- Past trips: completed, paid.
INSERT INTO registrations (trip_id, member_id, status, registered_at, confirmed_at,
                           attended_pre_trip_meeting)
SELECT t.id, m.id, v.st::registration_status, v.reg_at, v.reg_at, true
FROM (VALUES
 ('Explore Yosemite in the Winter','anguyen@ucmerced.edu',   'completed', TIMESTAMPTZ '2026-02-10 09:12-08'),
 ('Explore Yosemite in the Winter','blopez@ucmerced.edu',    'completed', TIMESTAMPTZ '2026-02-10 09:40-08'),
 ('Explore Yosemite in the Winter','fhaddad@ucmerced.edu',   'completed', TIMESTAMPTZ '2026-02-11 14:05-08'),
 ('Explore Yosemite in the Winter','dkim@ucmerced.edu',      'completed', TIMESTAMPTZ '2026-02-12 08:00-08'),
 ('Explore Yosemite in the Winter','cokafor@ucmerced.edu',   'no_show',   TIMESTAMPTZ '2026-02-13 17:22-08'),
 ('Explore Santa Cruz',    'anguyen@ucmerced.edu',   'completed', TIMESTAMPTZ '2026-03-20 10:00-07'),
 ('Explore Santa Cruz',    'dkim@ucmerced.edu',      'completed', TIMESTAMPTZ '2026-03-20 10:03-07'),
 ('Explore Santa Cruz',    'etorres@ucmerced.edu',   'completed', TIMESTAMPTZ '2026-03-21 19:44-07'),
 ('Explore Santa Cruz',    'gmolina@ucmerced.edu',   'completed', TIMESTAMPTZ '2026-03-22 11:15-07'),
 ('Explore Santa Cruz',    'hsato@ucmerced.edu',     'cancelled', TIMESTAMPTZ '2026-03-23 09:00-07'),
 ('Hike Gaylor Lakes',      'blopez@ucmerced.edu',    'completed', TIMESTAMPTZ '2026-04-05 12:30-07'),
 ('Hike Gaylor Lakes',      'fhaddad@ucmerced.edu',   'completed', TIMESTAMPTZ '2026-04-05 12:45-07'),
 ('Hike Gaylor Lakes',      'ipetrov@ucmerced.edu',   'completed', TIMESTAMPTZ '2026-04-06 08:20-07')
) AS v(trip, email, st, reg_at)
JOIN trips   t ON t.name  = v.trip
JOIN members m ON m.email = v.email
ORDER BY v.reg_at;

-- Mono Lake (capacity 2, meeting on 2026-09-10 already passed).
-- Alex attended, Bianca did not, Chris is waiting.
INSERT INTO registrations (trip_id, member_id, registered_at, confirmed_at, attended_pre_trip_meeting)
SELECT t.id, m.id, v.reg_at, v.reg_at, v.attended
FROM (VALUES
 ('Whale Watching Kayak Tour','anguyen@ucmerced.edu', TIMESTAMPTZ '2026-08-30 09:00-07', true),
 ('Whale Watching Kayak Tour','blopez@ucmerced.edu',  TIMESTAMPTZ '2026-08-30 09:05-07', false),
 ('Whale Watching Kayak Tour','dkim@ucmerced.edu',    TIMESTAMPTZ '2026-08-31 16:40-07', false)
) AS v(trip, email, reg_at, attended)
JOIN trips   t ON t.name  = v.trip
JOIN members m ON m.email = v.email
ORDER BY v.reg_at;   -- rows must reach the capacity trigger in registration order

-- Half Dome (capacity 3): five people register in order. RULE 1 waitlists #4/#5.
INSERT INTO registrations (trip_id, member_id, registered_at, confirmed_at)
SELECT t.id, m.id, v.reg_at, v.reg_at
FROM (VALUES
 ('Hike Dewey Point','etorres@ucmerced.edu',   TIMESTAMPTZ '2026-09-01 07:00-07'),
 ('Hike Dewey Point','fhaddad@ucmerced.edu',   TIMESTAMPTZ '2026-09-01 07:02-07'),
 ('Hike Dewey Point','gmolina@ucmerced.edu',   TIMESTAMPTZ '2026-09-01 07:09-07'),
 ('Hike Dewey Point','hsato@ucmerced.edu',     TIMESTAMPTZ '2026-09-01 07:15-07'),
 ('Hike Dewey Point','ipetrov@ucmerced.edu',   TIMESTAMPTZ '2026-09-02 21:30-07')
) AS v(trip, email, reg_at)
JOIN trips   t ON t.name  = v.trip
JOIN members m ON m.email = v.email
ORDER BY v.reg_at;   -- rows must reach the capacity trigger in registration order

-- Other upcoming trips: partially filled.
INSERT INTO registrations (trip_id, member_id, registered_at, confirmed_at)
SELECT t.id, m.id, v.reg_at, v.reg_at
FROM (VALUES
 ('Camp Yosemite Valley',   'anguyen@ucmerced.edu',   TIMESTAMPTZ '2026-09-03 10:00-07'),
 ('Camp Yosemite Valley',   'jrobinson@ucmerced.edu', TIMESTAMPTZ '2026-09-03 10:12-07'),
 ('Camp Yosemite Valley',   'kmensah@ucmerced.edu',   TIMESTAMPTZ '2026-09-04 13:00-07'),
 ('Indoor Rock Climbing | Alpine',    'dkim@ucmerced.edu',      TIMESTAMPTZ '2026-09-05 08:30-07'),
 ('Indoor Rock Climbing | Alpine',    'lfernandez@ucmerced.edu',TIMESTAMPTZ '2026-09-05 08:45-07'),
 ('Joshua Tree Stargazing','blopez@ucmerced.edu',    TIMESTAMPTZ '2026-09-06 19:00-07'),
 ('Joshua Tree Stargazing','fhaddad@ucmerced.edu',   TIMESTAMPTZ '2026-09-07 09:15-07'),
 ('Intro to Backpacking',     'kmensah@ucmerced.edu',   TIMESTAMPTZ '2026-09-08 11:00-07')
) AS v(trip, email, reg_at)
JOIN trips   t ON t.name  = v.trip
JOIN members m ON m.email = v.email
ORDER BY v.reg_at;   -- rows must reach the capacity trigger in registration order

-- Close out the past trips now that their history is loaded.
UPDATE trips SET status = 'completed', meeting_processed_at = pre_trip_meeting_at
 WHERE name IN ('Explore Yosemite in the Winter','Explore Santa Cruz','Hike Gaylor Lakes');

UPDATE registrations SET cancelled_at = registered_at
 WHERE status IN ('cancelled','no_show') AND cancelled_at IS NULL;

-- Two exceptions to "registering pays for it": a staff fee waiver, and a refund
-- for the member who cancelled off Explore Santa Cruz.
UPDATE registrations r SET payment_status = 'waived', amount_paid_cents = 0
 FROM trips t, members m
 WHERE t.id = r.trip_id AND m.id = r.member_id
   AND t.name = 'Explore Santa Cruz' AND m.email = 'gmolina@ucmerced.edu';

UPDATE registrations r SET payment_status = 'refunded'
 FROM trips t, members m
 WHERE t.id = r.trip_id AND m.id = r.member_id
   AND t.name = 'Explore Santa Cruz' AND m.email = 'hsato@ucmerced.edu';

-- Chris no-showed in the spring and his membership has been suspended since.
UPDATE members SET membership_status = 'suspended' WHERE email = 'cokafor@ucmerced.edu';

COMMIT;
