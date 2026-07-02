BEGIN;

INSERT INTO diary_members (name, default_area, role)
VALUES
    ('Marco Caparra', 'Gestão / Operações', 'CEO / Integrador'),
    ('Gustavo Bretas', 'Hardware / CAD / Eletrônica', 'Hardware'),
    ('Gustavo Borrego', 'Mecânica / Estrutura', 'Mecânica'),
    ('João Predeus', 'Backend / Software', 'Backend'),
    ('Gustavo Alencar', 'Frontend / UX / IA', 'Frontend / UX'),
    ('Guilherme Albano', 'Apoio pontual', 'Apoio')
ON CONFLICT DO NOTHING;

COMMIT;
