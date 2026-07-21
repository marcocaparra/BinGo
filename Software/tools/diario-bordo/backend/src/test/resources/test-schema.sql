BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE diary_report_status AS ENUM (
    'SUBMITTED',
    'SUBMITTED_LATE',
    'NO_ACTIVITY'
);

CREATE TABLE diary_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(120) NOT NULL,
    default_area VARCHAR(80),
    role VARCHAR(80),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX ux_diary_members_name_lower
    ON diary_members (LOWER(name));

CREATE TABLE diary_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES diary_members (id) ON DELETE RESTRICT,
    report_date DATE NOT NULL,
    area VARCHAR(80) NOT NULL,
    title VARCHAR(160) NOT NULL,
    description TEXT NOT NULL,
    problems TEXT,
    solution TEXT,
    next_steps TEXT,
    evidence_links TEXT,
    time_spent_minutes INTEGER,
    approximate_time VARCHAR(40),
    participants TEXT,
    environment VARCHAR(120),
    record_type VARCHAR(80),
    decisions TEXT,
    tests_and_observations TEXT,
    tools_used TEXT,
    pending_items TEXT,
    next_step_owner VARCHAR(120),
    next_step_due_date DATE,
    final_notes TEXT,
    status diary_report_status NOT NULL,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_diary_reports_member_report_date UNIQUE (member_id, report_date)
);

CREATE TABLE diary_report_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES diary_reports (id) ON DELETE CASCADE,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(120) NOT NULL,
    size_bytes BIGINT NOT NULL,
    category VARCHAR(40) NOT NULL,
    storage_path VARCHAR(600) NOT NULL,
    download_token VARCHAR(80) NOT NULL,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMIT;
