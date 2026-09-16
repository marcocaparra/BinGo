CREATE TABLE classification_categories (
    id UUID PRIMARY KEY,
    code VARCHAR(80) NOT NULL UNIQUE,
    name VARCHAR(160) NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO classification_categories (id, code, name, display_order, is_active) VALUES
    ('00000000-0000-0000-0000-000000000001', 'BATTERY', 'Battery', 10, TRUE),
    ('00000000-0000-0000-0000-000000000002', 'MOUSE', 'Mouse', 20, TRUE),
    ('00000000-0000-0000-0000-000000000003', 'KEYBOARD', 'Keyboard', 30, TRUE),
    ('00000000-0000-0000-0000-000000000004', 'CABLE', 'Cable', 40, TRUE),
    ('00000000-0000-0000-0000-000000000005', 'CHARGER', 'Charger', 50, TRUE),
    ('00000000-0000-0000-0000-000000000006', 'PCB', 'Printed Circuit Board', 60, TRUE),
    ('00000000-0000-0000-0000-000000000007', 'PHONE', 'Phone', 70, TRUE),
    ('00000000-0000-0000-0000-000000000008', 'HEADPHONES', 'Headphones', 80, TRUE),
    ('00000000-0000-0000-0000-000000000009', 'REMOTE_CONTROL', 'Remote Control', 90, TRUE),
    ('00000000-0000-0000-0000-000000000010', 'INVALID', 'Invalid', 100, TRUE),
    ('00000000-0000-0000-0000-000000000011', 'OTHER', 'Other', 110, TRUE);

ALTER TABLE provider_runs
    ADD COLUMN suggested_class_id UUID REFERENCES classification_categories(id);

ALTER TABLE human_evaluations
    RENAME COLUMN correct_class TO legacy_correct_class;

ALTER TABLE human_evaluations
    ADD COLUMN correct_class_id UUID;

UPDATE human_evaluations he
SET correct_class_id = cc.id
FROM classification_categories cc
WHERE he.legacy_correct_class = cc.code;

UPDATE human_evaluations
SET correct_class_id = '00000000-0000-0000-0000-000000000011'
WHERE correct_class_id IS NULL;

ALTER TABLE human_evaluations
    ALTER COLUMN correct_class_id SET NOT NULL,
    ADD CONSTRAINT fk_human_evaluations_correct_class
        FOREIGN KEY (correct_class_id) REFERENCES classification_categories(id);

CREATE INDEX idx_classification_categories_code ON classification_categories(code);
CREATE INDEX idx_classification_categories_active_order ON classification_categories(is_active, display_order, name);
CREATE INDEX idx_provider_runs_suggested_class_id ON provider_runs(suggested_class_id);
CREATE INDEX idx_human_evaluations_correct_class_id ON human_evaluations(correct_class_id);
