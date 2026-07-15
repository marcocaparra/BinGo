BEGIN;

-- Necessária para gerar UUIDs com gen_random_uuid().
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- PENDING não é persistido: pendências são calculadas pela ausência de relatório.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type AS t
        INNER JOIN pg_namespace AS n
            ON n.oid = t.typnamespace
        WHERE t.typname = 'diary_report_status'
          AND n.nspname = current_schema()
    ) THEN
        CREATE TYPE diary_report_status AS ENUM (
            'SUBMITTED',
            'SUBMITTED_LATE',
            'NO_ACTIVITY'
        );
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION diary_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS diary_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(120) NOT NULL,
    default_area VARCHAR(80),
    role VARCHAR(80),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_diary_members_name_not_blank
        CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_diary_members_default_area_not_blank
        CHECK (default_area IS NULL OR BTRIM(default_area) <> ''),
    CONSTRAINT ck_diary_members_role_not_blank
        CHECK (role IS NULL OR BTRIM(role) <> '')
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_diary_members_name_lower
    ON diary_members (LOWER(name));

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'trg_diary_members_set_updated_at'
          AND tgrelid = 'diary_members'::regclass
          AND NOT tgisinternal
    ) THEN
        EXECUTE '
            CREATE TRIGGER trg_diary_members_set_updated_at
            BEFORE UPDATE ON diary_members
            FOR EACH ROW
            EXECUTE FUNCTION diary_set_updated_at()
        ';
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS diary_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL,
    report_date DATE NOT NULL,
    area VARCHAR(80) NOT NULL,
    title VARCHAR(160) NOT NULL,
    description TEXT NOT NULL,
    problems TEXT,
    solution TEXT,
    next_steps TEXT,
    evidence_links TEXT,
    time_spent_minutes INTEGER,
    status diary_report_status NOT NULL,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_diary_reports_member
        FOREIGN KEY (member_id)
        REFERENCES diary_members (id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_diary_reports_member_report_date
        UNIQUE (member_id, report_date),
    CONSTRAINT ck_diary_reports_area_not_blank
        CHECK (BTRIM(area) <> ''),
    CONSTRAINT ck_diary_reports_title_not_blank
        CHECK (BTRIM(title) <> ''),
    CONSTRAINT ck_diary_reports_description_not_blank
        CHECK (BTRIM(description) <> ''),
    CONSTRAINT ck_diary_reports_time_spent_non_negative
        CHECK (time_spent_minutes IS NULL OR time_spent_minutes >= 0)
);

CREATE INDEX IF NOT EXISTS idx_diary_reports_report_date
    ON diary_reports (report_date DESC);

CREATE INDEX IF NOT EXISTS idx_diary_reports_member_date
    ON diary_reports (member_id, report_date DESC);

CREATE INDEX IF NOT EXISTS idx_diary_reports_status
    ON diary_reports (status);

CREATE INDEX IF NOT EXISTS idx_diary_reports_area
    ON diary_reports (area);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'trg_diary_reports_set_updated_at'
          AND tgrelid = 'diary_reports'::regclass
          AND NOT tgisinternal
    ) THEN
        EXECUTE '
            CREATE TRIGGER trg_diary_reports_set_updated_at
            BEFORE UPDATE ON diary_reports
            FOR EACH ROW
            EXECUTE FUNCTION diary_set_updated_at()
        ';
    END IF;
END;
$$;

COMMIT;
