CREATE TABLE image_validations (
    id UUID PRIMARY KEY,
    image_id UUID NOT NULL UNIQUE REFERENCES images(id) ON DELETE CASCADE,
    validation_status VARCHAR(40) NOT NULL,
    human_is_ewaste BOOLEAN,
    human_confirmed_class_id UUID REFERENCES classification_categories(id),
    human_note TEXT,
    validated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_image_validation_truth
        CHECK (
            (validation_status = 'INVALID'
                AND human_is_ewaste IS NULL
                AND human_confirmed_class_id IS NULL)
            OR
            (validation_status = 'VALID'
                AND human_is_ewaste IS NOT NULL
                AND (human_is_ewaste OR human_confirmed_class_id IS NULL))
        )
);

ALTER TABLE provider_runs
    ADD COLUMN eligibility_correct BOOLEAN,
    ADD COLUMN classification_correct BOOLEAN;

INSERT INTO image_validations (
    id,
    image_id,
    validation_status,
    human_is_ewaste,
    human_confirmed_class_id,
    human_note,
    validated_at
)
SELECT
    md5(pr.image_id::text || ':image-validation')::uuid,
    pr.image_id,
    'VALID',
    bool_or(he.is_target_object),
    CASE
        WHEN bool_or(he.is_target_object) THEN min(he.correct_class_id::text)::uuid
        ELSE NULL
    END,
    NULL,
    max(he.evaluated_at)
FROM human_evaluations he
JOIN provider_runs pr ON pr.id = he.provider_run_id
GROUP BY pr.image_id
HAVING bool_and(he.is_target_object) = bool_or(he.is_target_object)
   AND count(DISTINCT he.correct_class_id) = 1
ON CONFLICT (image_id) DO NOTHING;

UPDATE provider_runs pr
SET eligibility_correct = CASE
        WHEN pr.ewaste_eligibility = 'REVIEW' THEN NULL
        WHEN pr.ewaste_eligibility = 'ELIGIBLE' THEN iv.human_is_ewaste
        WHEN pr.ewaste_eligibility = 'NOT_ELIGIBLE' THEN NOT iv.human_is_ewaste
        ELSE NULL
    END,
    classification_correct = CASE
        WHEN iv.human_is_ewaste
             AND iv.human_confirmed_class_id IS NOT NULL
            THEN COALESCE(pr.suggested_class_id = iv.human_confirmed_class_id, FALSE)
        ELSE NULL
    END
FROM image_validations iv
WHERE iv.image_id = pr.image_id
  AND iv.validation_status = 'VALID';

CREATE INDEX idx_image_validations_image_id ON image_validations(image_id);
CREATE INDEX idx_image_validations_status ON image_validations(validation_status);
CREATE INDEX idx_provider_runs_eligibility_correct ON provider_runs(eligibility_correct);
CREATE INDEX idx_provider_runs_classification_correct ON provider_runs(classification_correct);
