-- Rebuild Checkpoint2-dbase.sqlite3 from scratch.
--   sqlite3 Checkpoint2-dbase.sqlite3 < checkpoint2/build-db.sql
--
-- SQLite conversion of the OEP+ PostgreSQL schema and seed.
-- Enums become TEXT + CHECK. SERIAL becomes INTEGER PRIMARY KEY.
-- Business-rule PL/pgSQL triggers are not loaded here so the graded
-- script can INSERT/UPDATE/DELETE without Postgres-only functions.
-- Waitlist/capacity outcomes from the original seed are stored as data.

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS registrations;
DROP TABLE IF EXISTS trip_equipment;
DROP TABLE IF EXISTS trip_guides;
DROP TABLE IF EXISTS guide_certifications;
DROP TABLE IF EXISTS trips;
DROP TABLE IF EXISTS equipment;
DROP TABLE IF EXISTS certifications;
DROP TABLE IF EXISTS guides;
DROP TABLE IF EXISTS members;

CREATE TABLE members (
    id                INTEGER PRIMARY KEY,
    first_name        TEXT NOT NULL CHECK (length(trim(first_name)) > 0),
    last_name         TEXT NOT NULL CHECK (length(trim(last_name)) > 0),
    email             TEXT NOT NULL UNIQUE
                      CHECK (email LIKE '%_@_%.%' AND instr(email, ' ') = 0),
    phone             TEXT,
    membership_type   TEXT NOT NULL
                      CHECK (membership_type IN ('student', 'faculty', 'staff', 'alumni', 'community')),
    membership_status TEXT NOT NULL DEFAULT 'active'
                      CHECK (membership_status IN ('active', 'suspended', 'expired')),
    joined_on         TEXT NOT NULL DEFAULT (date('now')),
    created_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE guides (
    id         INTEGER PRIMARY KEY,
    first_name TEXT NOT NULL CHECK (length(trim(first_name)) > 0),
    last_name  TEXT NOT NULL CHECK (length(trim(last_name)) > 0),
    email      TEXT NOT NULL UNIQUE,
    phone      TEXT,
    hired_on   TEXT NOT NULL DEFAULT (date('now')),
    active     INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE certifications (
    id               INTEGER PRIMARY KEY,
    code             TEXT NOT NULL UNIQUE,
    name             TEXT NOT NULL,
    issuing_body     TEXT,
    description      TEXT,
    validity_months  INTEGER CHECK (validity_months IS NULL OR validity_months > 0)
);

CREATE TABLE guide_certifications (
    guide_id         INTEGER NOT NULL REFERENCES guides(id) ON DELETE CASCADE,
    certification_id INTEGER NOT NULL REFERENCES certifications(id) ON DELETE RESTRICT,
    issued_on        TEXT NOT NULL,
    expires_on       TEXT NOT NULL,
    certificate_no   TEXT,
    PRIMARY KEY (guide_id, certification_id, issued_on),
    CHECK (expires_on > issued_on)
);
CREATE INDEX gc_lookup ON guide_certifications (certification_id, guide_id, expires_on);

CREATE TABLE trips (
    id                        INTEGER PRIMARY KEY,
    name                      TEXT NOT NULL CHECK (length(trim(name)) > 0),
    destination               TEXT,
    description               TEXT,
    difficulty                TEXT NOT NULL CHECK (difficulty IN ('easy', 'moderate', 'strenuous')),
    start_date                TEXT NOT NULL,
    end_date                  TEXT NOT NULL,
    capacity                  INTEGER NOT NULL CHECK (capacity > 0),
    fee_cents                 INTEGER NOT NULL DEFAULT 0 CHECK (fee_cents >= 0),
    required_certification_id INTEGER REFERENCES certifications(id) ON DELETE RESTRICT,
    pre_trip_meeting_at       TEXT,
    meeting_processed_at      TEXT,
    status                    TEXT NOT NULL DEFAULT 'open'
                              CHECK (status IN ('draft', 'open', 'cancelled', 'completed')),
    created_at                TEXT NOT NULL DEFAULT (datetime('now')),
    CHECK (end_date >= start_date)
);
CREATE INDEX trips_dates ON trips (start_date, end_date);
CREATE INDEX trips_status ON trips (status);

CREATE TABLE trip_guides (
    trip_id     INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    guide_id    INTEGER NOT NULL REFERENCES guides(id) ON DELETE RESTRICT,
    role        TEXT NOT NULL DEFAULT 'assistant'
                CHECK (role IN ('lead', 'assistant', 'trainee')),
    assigned_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (trip_id, guide_id)
);
CREATE UNIQUE INDEX trip_one_lead ON trip_guides (trip_id) WHERE role = 'lead';

CREATE TABLE equipment (
    id             INTEGER PRIMARY KEY,
    name           TEXT NOT NULL,
    category       TEXT NOT NULL,
    total_quantity INTEGER NOT NULL CHECK (total_quantity >= 0),
    condition      TEXT NOT NULL DEFAULT 'good'
                   CHECK (condition IN ('new', 'good', 'fair', 'poor', 'damaged', 'lost', 'retired')),
    purchased_on   TEXT,
    notes          TEXT,
    UNIQUE (name, category)
);

CREATE TABLE trip_equipment (
    id               INTEGER PRIMARY KEY,
    trip_id          INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    equipment_id     INTEGER NOT NULL REFERENCES equipment(id) ON DELETE RESTRICT,
    quantity         INTEGER NOT NULL CHECK (quantity > 0),
    checked_out_at   TEXT,
    checked_in_at    TEXT,
    return_condition TEXT CHECK (
        return_condition IS NULL OR
        return_condition IN ('new', 'good', 'fair', 'poor', 'damaged', 'lost', 'retired')
    ),
    notes            TEXT,
    UNIQUE (trip_id, equipment_id),
    CHECK (checked_in_at IS NULL OR checked_out_at IS NOT NULL),
    CHECK (checked_in_at IS NULL OR checked_in_at >= checked_out_at),
    CHECK (return_condition IS NULL OR checked_in_at IS NOT NULL)
);
CREATE INDEX te_equipment ON trip_equipment (equipment_id, trip_id);

CREATE TABLE registrations (
    id                        INTEGER PRIMARY KEY,
    trip_id                   INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    member_id                 INTEGER NOT NULL REFERENCES members(id) ON DELETE RESTRICT,
    status                    TEXT NOT NULL DEFAULT 'confirmed'
                              CHECK (status IN ('confirmed', 'waitlisted', 'cancelled', 'completed', 'no_show')),
    registered_at             TEXT NOT NULL DEFAULT (datetime('now')),
    confirmed_at              TEXT,
    cancelled_at              TEXT,
    cancel_reason             TEXT,
    payment_status            TEXT NOT NULL DEFAULT 'paid'
                              CHECK (payment_status IN ('paid', 'refunded', 'waived')),
    amount_paid_cents         INTEGER NOT NULL DEFAULT 0 CHECK (amount_paid_cents >= 0),
    attended_pre_trip_meeting INTEGER NOT NULL DEFAULT 0 CHECK (attended_pre_trip_meeting IN (0, 1)),
    UNIQUE (trip_id, member_id)
);
CREATE INDEX reg_queue ON registrations (trip_id, status, registered_at, id);
CREATE INDEX reg_member ON registrations (member_id);

-- ------------------------------------------------------------------ seed
-- "Today" for this dataset is 2026-09-12.

INSERT INTO certifications (id, code, name, issuing_body, description, validity_months) VALUES
 (1, 'WFR',        'Wilderness First Responder',  'NOLS / SOLO',        '80-hour backcountry medicine certification', 24),
 (2, 'WFA',        'Wilderness First Aid',        'NOLS',               '16-hour front-country first aid', 24),
 (3, 'CPR',        'CPR / AED',                   'American Red Cross', 'Basic life support', 24),
 (4, 'SWIFTWATER', 'Swiftwater Rescue Technician','ACA',                'Moving-water rescue for paddling trips', 36),
 (5, 'SPI',        'Single Pitch Instructor',     'AMGA',               'Top-rope and single-pitch climbing instruction', 36),
 (6, 'AVY1',       'Avalanche Level 1',           'AIARE',              'Winter travel in avalanche terrain', NULL);

INSERT INTO guides (id, first_name, last_name, email, phone, hired_on, active) VALUES
 (1, 'Maya',   'Ortiz',     'mortiz@ucmerced.edu',     '209-555-0101', '2023-08-14', 1),
 (2, 'Devon',  'Chen',      'dchen@ucmerced.edu',      '209-555-0102', '2024-01-09', 1),
 (3, 'Priya',  'Raman',     'praman@ucmerced.edu',     '209-555-0103', '2024-09-03', 1),
 (4, 'Sam',    'Whitfield', 'swhitfield@ucmerced.edu', '209-555-0104', '2025-08-25', 1),
 (5, 'Jordan', 'Blake',     'jblake@ucmerced.edu',     '209-555-0105', '2022-06-01', 1);

INSERT INTO guide_certifications (guide_id, certification_id, issued_on, expires_on, certificate_no) VALUES
 (1, 1, '2025-06-01', '2027-06-01', 'WFR-88201'),
 (1, 3, '2025-06-01', '2027-06-01', 'CPR-11904'),
 (1, 1, '2023-05-20', '2025-05-20', 'WFR-70118'),
 (2, 1, '2024-10-04', '2026-10-04', 'WFR-90233'),
 (2, 3, '2026-02-11', '2028-02-11', 'CPR-12877'),
 (3, 4, '2025-04-18', '2028-04-18', 'SWR-4410'),
 (3, 1, '2024-06-30', '2026-06-30', 'WFR-89044'),
 (3, 3, '2025-04-18', '2027-04-18', 'CPR-12011'),
 (4, 3, '2026-01-20', '2028-01-20', 'CPR-13320'),
 (4, 2, '2026-01-20', '2028-01-20', 'WFA-2298'),
 (5, 5, '2024-03-02', '2027-03-02', 'SPI-7781'),
 (5, 1, '2025-09-15', '2027-09-15', 'WFR-90881'),
 (5, 6, '2023-12-08', '2030-12-08', 'AVY-3310');

INSERT INTO members (id, first_name, last_name, email, phone, membership_type, membership_status, joined_on) VALUES
 (1,  'Alex',   'Nguyen',    'anguyen@ucmerced.edu',     '209-555-0201', 'student',  'active',    '2025-08-20'),
 (2,  'Bianca', 'Lopez',     'blopez@ucmerced.edu',      '209-555-0202', 'student',  'active',    '2025-08-21'),
 (3,  'Chris',  'Okafor',    'cokafor@ucmerced.edu',     '209-555-0203', 'student',  'suspended', '2025-09-02'),
 (4,  'Dana',   'Kim',       'dkim@ucmerced.edu',        '209-555-0204', 'student',  'active',    '2025-09-04'),
 (5,  'Eli',    'Torres',    'etorres@ucmerced.edu',     '209-555-0205', 'student',  'active',    '2026-01-12'),
 (6,  'Farah',  'Haddad',    'fhaddad@ucmerced.edu',     '209-555-0206', 'faculty',  'active',    '2024-02-19'),
 (7,  'Gabe',   'Molina',    'gmolina@ucmerced.edu',     '209-555-0207', 'staff',    'active',    '2024-05-30'),
 (8,  'Hana',   'Sato',      'hsato@ucmerced.edu',       '209-555-0208', 'student',  'active',    '2026-01-15'),
 (9,  'Ivan',   'Petrov',    'ipetrov@ucmerced.edu',     '209-555-0209', 'student',  'active',    '2026-02-01'),
 (10, 'Kofi',   'Mensah',    'kmensah@ucmerced.edu',     '209-555-0211', 'student',  'active',    '2026-08-28'),
 (11, 'Jamie',  'Robinson',  'jrobinson@ucmerced.edu',   '209-555-0210', 'student',  'active',    '2026-09-01');

INSERT INTO equipment (id, name, category, total_quantity, condition, purchased_on, notes) VALUES
 (1,  '4-Person Tent',         'shelter',  6,  'good', '2024-05-02', NULL),
 (2,  '2-Person Tent',         'shelter',  8,  'good', '2023-04-18', NULL),
 (3,  '65L Backpack',          'packs',    20, 'good', '2023-04-18', NULL),
 (4,  'Sleeping Bag 20F',      'sleep',    18, 'fair', '2022-09-30', 'oldest batch due for replacement'),
 (5,  'Bear Canister',         'storage',  10, 'good', '2024-05-02', NULL),
 (6,  'Whitewater Kayak',      'paddling', 8,  'good', '2025-03-11', NULL),
 (7,  'PFD Type V',            'paddling', 14, 'good', '2025-03-11', NULL),
 (8,  'Climbing Helmet',       'climbing', 12, 'good', '2024-08-15', NULL),
 (9,  'Top-Rope Kit',          'climbing', 3,  'good', '2024-08-15', 'rope, quickdraws, anchor material'),
 (10, 'Satellite Messenger',   'safety',   2,  'good', '2025-01-20', 'one per group, mandatory backcountry'),
 (11, 'Group First Aid Kit',   'safety',   4,  'good', '2025-01-20', NULL),
 (12, 'Trekking Poles (pair)', 'packs',    10, 'poor', '2021-10-05', 'frequently bent');

INSERT INTO trips (id, name, destination, difficulty, start_date, end_date, capacity,
                   fee_cents, required_certification_id, pre_trip_meeting_at, meeting_processed_at, status) VALUES
 (1,  'Explore Yosemite in the Winter', 'Yosemite NP',      'moderate',  '2026-03-14', '2026-03-16', 10, 8500,  1,    '2026-03-10 18:00:00', '2026-03-10 18:00:00', 'completed'),
 (2,  'Explore Santa Cruz',             'Santa Cruz',       'easy',      '2026-04-11', '2026-04-11', 12, 3000,  NULL, NULL,                  NULL,                  'completed'),
 (3,  'Hike Gaylor Lakes',              'Tuolumne Meadows', 'strenuous', '2026-05-02', '2026-05-04', 8,  11000, 1,    '2026-04-28 18:00:00', '2026-04-28 18:00:00', 'completed'),
 (4,  'Whale Watching Kayak Tour',      'Monterey Bay',     'easy',      '2026-09-19', '2026-09-19', 2,  4000,  4,    '2026-09-10 18:00:00', NULL,                  'open'),
 (5,  'Hike Dewey Point',               'Yosemite NP',      'strenuous', '2026-10-10', '2026-10-10', 3,  4500,  1,    '2026-10-06 18:00:00', NULL,                  'open'),
 (6,  'Camp Yosemite Valley',           'Yosemite Valley',  'moderate',  '2026-10-17', '2026-10-18', 8,  6000,  1,    '2026-10-13 18:00:00', NULL,                  'open'),
 (7,  'Intro to Backpacking',           'Merced River',     'moderate',  '2026-10-18', '2026-10-19', 6,  2500,  1,    NULL,                  NULL,                  'open'),
 (8,  'Indoor Rock Climbing | Alpine',  'Alpine, Modesto',  'moderate',  '2026-10-24', '2026-10-25', 6,  7500,  5,    '2026-10-20 18:00:00', NULL,                  'open'),
 (9,  'Joshua Tree Stargazing',         'Joshua Tree NP',   'strenuous', '2026-11-06', '2026-11-09', 10, 13500, 1,    '2026-11-02 18:00:00', NULL,                  'open'),
 (10, 'Hike Lembert Dome and Dog Lake', 'Tuolumne Meadows', 'moderate',  '2027-01-16', '2027-01-17', 8,  9000,  6,    '2027-01-12 18:00:00', NULL,                  'draft');

INSERT INTO trip_guides (trip_id, guide_id, role) VALUES
 (1, 1, 'lead'),
 (2, 4, 'lead'),
 (2, 2, 'assistant'),
 (3, 5, 'lead'),
 (4, 3, 'lead'),
 (5, 1, 'lead'),
 (6, 5, 'lead'),
 (7, 1, 'lead'),
 (8, 5, 'lead'),
 (9, 1, 'lead'),
 (9, 5, 'assistant');

INSERT INTO trip_equipment (id, trip_id, equipment_id, quantity, checked_out_at, checked_in_at, return_condition, notes) VALUES
 (1,  1, 2,  5, '2026-03-13 09:00:00', '2026-03-17 16:00:00', 'good',    NULL),
 (2,  1, 3, 10, '2026-03-13 09:00:00', '2026-03-17 16:00:00', 'fair',    NULL),
 (3,  1, 12, 6, '2026-03-13 09:00:00', '2026-03-17 16:00:00', 'damaged', 'two pairs bent beyond repair'),
 (4,  1, 10, 1, '2026-03-13 09:00:00', '2026-03-17 16:00:00', 'good',    NULL),
 (5,  2, 11, 2, '2026-04-10 12:00:00', '2026-04-12 10:00:00', 'good',    NULL),
 (6,  2, 12, 4, '2026-04-10 12:00:00', '2026-04-12 10:00:00', 'damaged', 'one pair snapped'),
 (7,  3, 1,  3, '2026-05-01 08:00:00', '2026-05-05 17:00:00', 'good',    NULL),
 (8,  3, 4,  8, '2026-05-01 08:00:00', '2026-05-05 17:00:00', 'fair',    NULL),
 (9,  3, 10, 1, '2026-05-01 08:00:00', '2026-05-05 17:00:00', 'lost',    'dropped in a creek crossing'),
 (10, 3, 12, 5, '2026-05-01 08:00:00', '2026-05-05 17:00:00', 'good',    NULL),
 (11, 4, 6,  2, NULL, NULL, NULL, NULL),
 (12, 4, 7,  3, NULL, NULL, NULL, NULL),
 (13, 5, 11, 1, NULL, NULL, NULL, NULL),
 (14, 6, 1,  4, NULL, NULL, NULL, NULL),
 (15, 6, 4,  8, NULL, NULL, NULL, NULL),
 (16, 8, 8,  6, NULL, NULL, NULL, NULL),
 (17, 8, 9,  2, NULL, NULL, NULL, NULL),
 (18, 9, 1,  3, NULL, NULL, NULL, NULL),
 (19, 9, 5,  8, NULL, NULL, NULL, NULL),
 (20, 9, 10, 1, NULL, NULL, NULL, NULL);

-- Past trips
INSERT INTO registrations (id, trip_id, member_id, status, registered_at, confirmed_at, cancelled_at,
                           payment_status, amount_paid_cents, attended_pre_trip_meeting) VALUES
 (1,  1, 1, 'completed', '2026-02-10 09:12:00', '2026-02-10 09:12:00', NULL,                 'paid',     8500, 1),
 (2,  1, 2, 'completed', '2026-02-10 09:40:00', '2026-02-10 09:40:00', NULL,                 'paid',     8500, 1),
 (3,  1, 6, 'completed', '2026-02-11 14:05:00', '2026-02-11 14:05:00', NULL,                 'paid',     8500, 1),
 (4,  1, 4, 'completed', '2026-02-12 08:00:00', '2026-02-12 08:00:00', NULL,                 'paid',     8500, 1),
 (5,  1, 3, 'no_show',   '2026-02-13 17:22:00', '2026-02-13 17:22:00', '2026-02-13 17:22:00', 'paid',     8500, 0),
 (6,  2, 1, 'completed', '2026-03-20 10:00:00', '2026-03-20 10:00:00', NULL,                 'paid',     3000, 1),
 (7,  2, 4, 'completed', '2026-03-20 10:03:00', '2026-03-20 10:03:00', NULL,                 'paid',     3000, 1),
 (8,  2, 5, 'completed', '2026-03-21 19:44:00', '2026-03-21 19:44:00', NULL,                 'paid',     3000, 1),
 (9,  2, 7, 'completed', '2026-03-22 11:15:00', '2026-03-22 11:15:00', NULL,                 'waived',   0,    1),
 (10, 2, 8, 'cancelled', '2026-03-23 09:00:00', '2026-03-23 09:00:00', '2026-03-23 09:00:00', 'refunded', 3000, 0),
 (11, 3, 2, 'completed', '2026-04-05 12:30:00', '2026-04-05 12:30:00', NULL,                 'paid',     11000, 1),
 (12, 3, 6, 'completed', '2026-04-05 12:45:00', '2026-04-05 12:45:00', NULL,                 'paid',     11000, 1),
 (13, 3, 9, 'completed', '2026-04-06 08:20:00', '2026-04-06 08:20:00', NULL,                 'paid',     11000, 1);

-- Whale Watching: capacity 2. Alex and Bianca confirmed; Dana waitlisted.
INSERT INTO registrations (id, trip_id, member_id, status, registered_at, confirmed_at, cancelled_at,
                           payment_status, amount_paid_cents, attended_pre_trip_meeting) VALUES
 (14, 4, 1, 'confirmed',  '2026-08-30 09:00:00', '2026-08-30 09:00:00', NULL, 'paid', 4000, 1),
 (15, 4, 2, 'confirmed',  '2026-08-30 09:05:00', '2026-08-30 09:05:00', NULL, 'paid', 4000, 0),
 (16, 4, 4, 'waitlisted', '2026-08-31 16:40:00', NULL,                  NULL, 'paid', 4000, 0);

-- Dewey Point: capacity 3. Eli, Farah, Gabe confirmed; Hana and Ivan waitlisted.
INSERT INTO registrations (id, trip_id, member_id, status, registered_at, confirmed_at, cancelled_at,
                           payment_status, amount_paid_cents, attended_pre_trip_meeting) VALUES
 (17, 5, 5, 'confirmed',  '2026-09-01 07:00:00', '2026-09-01 07:00:00', NULL, 'paid', 4500, 0),
 (18, 5, 6, 'confirmed',  '2026-09-01 07:02:00', '2026-09-01 07:02:00', NULL, 'paid', 4500, 0),
 (19, 5, 7, 'confirmed',  '2026-09-01 07:09:00', '2026-09-01 07:09:00', NULL, 'paid', 4500, 0),
 (20, 5, 8, 'waitlisted', '2026-09-01 07:15:00', NULL,                  NULL, 'paid', 4500, 0),
 (21, 5, 9, 'waitlisted', '2026-09-02 21:30:00', NULL,                  NULL, 'paid', 4500, 0);

-- Other upcoming trips
INSERT INTO registrations (id, trip_id, member_id, status, registered_at, confirmed_at, cancelled_at,
                           payment_status, amount_paid_cents, attended_pre_trip_meeting) VALUES
 (22, 6, 1,  'confirmed', '2026-09-03 10:00:00', '2026-09-03 10:00:00', NULL, 'paid', 6000,  0),
 (23, 6, 10, 'confirmed', '2026-09-04 13:00:00', '2026-09-04 13:00:00', NULL, 'paid', 6000,  0),
 (24, 8, 4,  'confirmed', '2026-09-05 08:30:00', '2026-09-05 08:30:00', NULL, 'paid', 7500,  0),
 (25, 9, 2,  'confirmed', '2026-09-06 19:00:00', '2026-09-06 19:00:00', NULL, 'paid', 13500, 0),
 (26, 9, 6,  'confirmed', '2026-09-07 09:15:00', '2026-09-07 09:15:00', NULL, 'paid', 13500, 0),
 (27, 7, 10, 'confirmed', '2026-09-08 11:00:00', '2026-09-08 11:00:00', NULL, 'paid', 2500,  0);
