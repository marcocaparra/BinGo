ALTER TABLE provider_runs
    ADD COLUMN ewaste_eligibility VARCHAR(40);

UPDATE provider_runs
SET ewaste_eligibility = CASE
    WHEN classification_status = 'CLASSIFIED'
         AND suggested_class_id IN (
             SELECT id
             FROM classification_categories
             WHERE code IN (
                 'ELECTRONIC_DEVICE',
                 'BATTERY',
                 'MOUSE',
                 'KEYBOARD',
                 'CABLE',
                 'CHARGER',
                 'PCB',
                 'PHONE',
                 'HEADPHONES',
                 'REMOTE_CONTROL'
             )
         )
        THEN 'ELIGIBLE'
    WHEN classification_status = 'CLASSIFIED'
         AND suggested_class_id IN (
             SELECT id
             FROM classification_categories
             WHERE code = 'INVALID'
         )
        THEN 'NOT_ELIGIBLE'
    ELSE 'REVIEW'
END;

ALTER TABLE provider_runs
    ALTER COLUMN ewaste_eligibility SET DEFAULT 'REVIEW',
    ALTER COLUMN ewaste_eligibility SET NOT NULL;
