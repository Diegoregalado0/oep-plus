-- OEP+ : UC Merced Outdoor Experience Program
-- Schema, constraints and business-rule enforcement.
-- Every rule in Section 5 of the brief is enforced here, in the database,
-- so no client can bypass it.

BEGIN;

DROP SCHEMA IF EXISTS oep CASCADE;
CREATE SCHEMA oep;
SET search_path TO oep, public;

-- ---------------------------------------------------------------- enum types

CREATE TYPE membership_type AS ENUM ('student', 'faculty', 'staff', 'alumni', 'community');
CREATE TYPE membership_status AS ENUM ('active', 'suspended', 'expired');
CREATE TYPE difficulty_level AS ENUM ('easy', 'moderate', 'strenuous');
CREATE TYPE trip_status AS ENUM ('draft', 'open', 'cancelled', 'completed');
CREATE TYPE registration_status AS ENUM ('confirmed', 'waitlisted', 'cancelled', 'completed', 'no_show');
-- Registering for a trip pays for it, so there is no unpaid state.
CREATE TYPE payment_status AS ENUM ('paid', 'refunded', 'waived');
CREATE TYPE equipment_condition AS ENUM ('new', 'good', 'fair', 'poor', 'damaged', 'lost', 'retired');
CREATE TYPE guide_role AS ENUM ('lead', 'assistant', 'trainee');

-- ------------------------------------------------------------------- members

CREATE TABLE members (
    id                SERIAL PRIMARY KEY,
    first_name        TEXT NOT NULL CHECK (length(trim(first_name)) > 0),
    last_name         TEXT NOT NULL CHECK (length(trim(last_name)) > 0),
    email             TEXT NOT NULL UNIQUE CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    phone             TEXT,
    membership_type   membership_type   NOT NULL,
    membership_status membership_status NOT NULL DEFAULT 'active',
    joined_on         DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------------- guides

CREATE TABLE guides (
    id         SERIAL PRIMARY KEY,
    first_name TEXT NOT NULL CHECK (length(trim(first_name)) > 0),
    last_name  TEXT NOT NULL CHECK (length(trim(last_name)) > 0),
    email      TEXT NOT NULL UNIQUE,
    phone      TEXT,
    hired_on   DATE NOT NULL DEFAULT CURRENT_DATE,
    active     BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reusable catalog of certification types. Not tied to any guide.
CREATE TABLE certifications (
    id               SERIAL PRIMARY KEY,
    code             TEXT NOT NULL UNIQUE,   -- 'WFR', 'CPR', 'SWIFTWATER'
    name             TEXT NOT NULL,
    issuing_body     TEXT,
    description      TEXT,
    validity_months  INT CHECK (validity_months IS NULL OR validity_months > 0)
);

-- M:N -- many guides hold the same certification; a guide holds many.
-- Re-certification history is kept: the PK includes issued_on.
CREATE TABLE guide_certifications (
    guide_id         INT NOT NULL REFERENCES guides(id) ON DELETE CASCADE,
    certification_id INT NOT NULL REFERENCES certifications(id) ON DELETE RESTRICT,
    issued_on        DATE NOT NULL,
    expires_on       DATE NOT NULL,
    certificate_no   TEXT,
    PRIMARY KEY (guide_id, certification_id, issued_on),
    CHECK (expires_on > issued_on)
);
CREATE INDEX gc_lookup ON guide_certifications (certification_id, guide_id, expires_on);

-- --------------------------------------------------------------------- trips

CREATE TABLE trips (
    id                        SERIAL PRIMARY KEY,
    name                      TEXT NOT NULL CHECK (length(trim(name)) > 0),
    destination               TEXT,
    description               TEXT,
    difficulty                difficulty_level NOT NULL,
    start_date                DATE NOT NULL,
    end_date                  DATE NOT NULL,
    capacity                  INT  NOT NULL CHECK (capacity > 0),
    fee_cents                 INT  NOT NULL DEFAULT 0 CHECK (fee_cents >= 0),
    required_certification_id INT REFERENCES certifications(id) ON DELETE RESTRICT,
    pre_trip_meeting_at       TIMESTAMPTZ,     -- NULL = no mandatory meeting
    meeting_processed_at      TIMESTAMPTZ,     -- set by the no-show sweep
    status                    trip_status NOT NULL DEFAULT 'open',
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_date >= start_date)
);
CREATE INDEX trips_dates ON trips (start_date, end_date);

-- M:N -- a trip needs several guides, a guide leads several trips.
CREATE TABLE trip_guides (
    trip_id     INT NOT NULL REFERENCES trips(id)  ON DELETE CASCADE,
    guide_id    INT NOT NULL REFERENCES guides(id) ON DELETE RESTRICT,
    role        guide_role NOT NULL DEFAULT 'assistant',
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (trip_id, guide_id)
);
-- At most one lead guide per trip.
CREATE UNIQUE INDEX trip_one_lead ON trip_guides (trip_id) WHERE role = 'lead';

-- ----------------------------------------------------------------- equipment

CREATE TABLE equipment (
    id             SERIAL PRIMARY KEY,
    name           TEXT NOT NULL,
    category       TEXT NOT NULL,
    total_quantity INT NOT NULL CHECK (total_quantity >= 0),
    condition      equipment_condition NOT NULL DEFAULT 'good',
    purchased_on   DATE,
    notes          TEXT,
    UNIQUE (name, category)
);

-- M:N with attributes -- gear is committed to a trip for that trip's dates.
CREATE TABLE trip_equipment (
    id                INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    trip_id           INT NOT NULL REFERENCES trips(id)     ON DELETE CASCADE,
    equipment_id      INT NOT NULL REFERENCES equipment(id) ON DELETE RESTRICT,
    quantity          INT NOT NULL CHECK (quantity > 0),
    checked_out_at    TIMESTAMPTZ,
    checked_in_at     TIMESTAMPTZ,
    return_condition  equipment_condition,
    notes             TEXT,
    UNIQUE (trip_id, equipment_id),
    CHECK (checked_in_at IS NULL OR checked_out_at IS NOT NULL),
    CHECK (checked_in_at IS NULL OR checked_in_at >= checked_out_at),
    CHECK (return_condition IS NULL OR checked_in_at IS NOT NULL)
);
CREATE INDEX te_equipment ON trip_equipment (equipment_id, trip_id);

-- ------------------------------------------------------------- registrations

CREATE TABLE registrations (
    id                         SERIAL PRIMARY KEY,
    trip_id                    INT NOT NULL REFERENCES trips(id)   ON DELETE CASCADE,
    member_id                  INT NOT NULL REFERENCES members(id) ON DELETE RESTRICT,
    status                     registration_status NOT NULL DEFAULT 'confirmed',
    registered_at              TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    confirmed_at               TIMESTAMPTZ,
    cancelled_at               TIMESTAMPTZ,
    cancel_reason              TEXT,
    payment_status             payment_status NOT NULL DEFAULT 'paid',
    amount_paid_cents          INT NOT NULL DEFAULT 0 CHECK (amount_paid_cents >= 0),
    attended_pre_trip_meeting  BOOLEAN NOT NULL DEFAULT false,
    UNIQUE (trip_id, member_id)   -- one registration per member per trip
);
CREATE INDEX reg_queue ON registrations (trip_id, status, registered_at, id);

COMMIT;
