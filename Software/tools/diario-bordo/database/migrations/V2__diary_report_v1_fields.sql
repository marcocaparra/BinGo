BEGIN;

ALTER TABLE diary_reports
    ADD COLUMN IF NOT EXISTS approximate_time VARCHAR(40),
    ADD COLUMN IF NOT EXISTS participants TEXT,
    ADD COLUMN IF NOT EXISTS environment VARCHAR(120),
    ADD COLUMN IF NOT EXISTS record_type VARCHAR(80),
    ADD COLUMN IF NOT EXISTS decisions TEXT,
    ADD COLUMN IF NOT EXISTS tests_and_observations TEXT,
    ADD COLUMN IF NOT EXISTS tools_used TEXT,
    ADD COLUMN IF NOT EXISTS pending_items TEXT,
    ADD COLUMN IF NOT EXISTS next_step_owner VARCHAR(120),
    ADD COLUMN IF NOT EXISTS next_step_due_date DATE,
    ADD COLUMN IF NOT EXISTS final_notes TEXT;

COMMIT;
