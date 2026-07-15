BEGIN;

ALTER TABLE diary_report_attachments
    ADD COLUMN IF NOT EXISTS download_token VARCHAR(80);

UPDATE diary_report_attachments
SET download_token = gen_random_uuid()::text
WHERE download_token IS NULL OR BTRIM(download_token) = '';

ALTER TABLE diary_report_attachments
    ALTER COLUMN download_token SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_diary_report_attachments_download_token
    ON diary_report_attachments (download_token);

COMMIT;
