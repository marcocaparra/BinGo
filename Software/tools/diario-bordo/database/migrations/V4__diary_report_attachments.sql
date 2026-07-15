BEGIN;

CREATE TABLE IF NOT EXISTS diary_report_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(120) NOT NULL,
    size_bytes BIGINT NOT NULL,
    category VARCHAR(40) NOT NULL,
    storage_path VARCHAR(600) NOT NULL,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_diary_report_attachments_report
        FOREIGN KEY (report_id)
        REFERENCES diary_reports (id)
        ON DELETE CASCADE,
    CONSTRAINT ck_diary_report_attachments_original_filename_not_blank
        CHECK (BTRIM(original_filename) <> ''),
    CONSTRAINT ck_diary_report_attachments_stored_filename_not_blank
        CHECK (BTRIM(stored_filename) <> ''),
    CONSTRAINT ck_diary_report_attachments_size_positive
        CHECK (size_bytes > 0),
    CONSTRAINT ck_diary_report_attachments_category
        CHECK (category IN ('imagem', 'video', 'documento'))
);

CREATE INDEX IF NOT EXISTS idx_diary_report_attachments_report
    ON diary_report_attachments (report_id, uploaded_at);

COMMIT;
