ALTER TABLE classification_categories
    ADD COLUMN category_type VARCHAR(40) NOT NULL DEFAULT 'SPECIFIC',
    ADD COLUMN default_ewaste_eligibility VARCHAR(40) NOT NULL DEFAULT 'REVIEW';

UPDATE classification_categories
SET category_type = 'GENERIC',
    default_ewaste_eligibility = 'ELIGIBLE'
WHERE code IN (
    'ELECTRONIC_DEVICE',
    'COMPUTER_HARDWARE',
    'ELECTRONIC_COMPONENT'
);

UPDATE classification_categories
SET category_type = 'SPECIFIC',
    default_ewaste_eligibility = 'ELIGIBLE'
WHERE code IN (
    'BATTERY',
    'MOUSE',
    'KEYBOARD',
    'CABLE',
    'CHARGER',
    'PCB',
    'PHONE',
    'HEADPHONES',
    'REMOTE_CONTROL'
);

UPDATE classification_categories
SET category_type = 'FALLBACK',
    default_ewaste_eligibility = 'NOT_ELIGIBLE'
WHERE code = 'INVALID';

UPDATE classification_categories
SET category_type = 'FALLBACK',
    default_ewaste_eligibility = 'REVIEW'
WHERE code = 'OTHER';
