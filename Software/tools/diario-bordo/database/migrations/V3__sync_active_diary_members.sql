BEGIN;

INSERT INTO diary_members (name, default_area, role, is_active)
VALUES
    ('Marco Caparra', 'Gestão / Operações', 'CEO / Integrador', TRUE),
    ('Gustavo Bretas', 'Hardware / CAD / Eletrônica', 'Hardware', TRUE),
    ('Gustavo Borrego', 'Mecânica / Estrutura', 'Mecânica', TRUE),
    ('João Predeus', 'Backend / Software', 'Backend', TRUE),
    ('Gustavo Alencar', 'Frontend / UX / IA', 'Frontend / UX', TRUE)
ON CONFLICT ((LOWER(name)))
DO UPDATE SET
    default_area = EXCLUDED.default_area,
    role = EXCLUDED.role,
    is_active = TRUE,
    updated_at = NOW();

UPDATE diary_members
SET is_active = FALSE,
    updated_at = NOW()
WHERE LOWER(name) NOT IN (
    LOWER('Marco Caparra'),
    LOWER('Gustavo Bretas'),
    LOWER('Gustavo Borrego'),
    LOWER('João Predeus'),
    LOWER('Gustavo Alencar')
);

COMMIT;
