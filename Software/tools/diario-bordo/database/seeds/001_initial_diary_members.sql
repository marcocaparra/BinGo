BEGIN;

INSERT INTO diary_members (name, default_area, role)
VALUES
    ('Marco Caparra', 'Gestão / Operações', 'CEO / Integrador'),
    ('Gustavo Bretas', 'Hardware / CAD / Eletrônica', 'Hardware'),
    ('Gustavo Borrego', 'Mecânica / Estrutura', 'Mecânica'),
    ('João Predeus', 'Backend / Software', 'Backend'),
    ('Gustavo Alencar', 'Frontend / UX / IA', 'Frontend / UX')
ON CONFLICT DO NOTHING;

COMMIT;
