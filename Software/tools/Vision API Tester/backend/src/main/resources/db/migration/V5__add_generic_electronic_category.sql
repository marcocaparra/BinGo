INSERT INTO classification_categories (id, code, name, display_order, is_active) VALUES
    ('00000000-0000-0000-0000-000000000012', 'ELECTRONIC_DEVICE', 'Electronic Device', 95, TRUE);

INSERT INTO classification_category_aliases (id, category_id, alias, normalized_alias) VALUES
    ('10000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000012', 'Electronics', 'electronics'),
    ('10000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000012', 'Electronic device', 'electronic device'),
    ('10000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-000000000012', 'Electronic component', 'electronic component'),
    ('10000000-0000-0000-0000-000000000034', '00000000-0000-0000-0000-000000000012', 'Electronic equipment', 'electronic equipment'),
    ('10000000-0000-0000-0000-000000000035', '00000000-0000-0000-0000-000000000012', 'Computer hardware', 'computer hardware'),
    ('10000000-0000-0000-0000-000000000036', '00000000-0000-0000-0000-000000000012', 'Consumer electronics', 'consumer electronics'),
    ('10000000-0000-0000-0000-000000000037', '00000000-0000-0000-0000-000000000012', 'Eletrônico', 'eletronico'),
    ('10000000-0000-0000-0000-000000000038', '00000000-0000-0000-0000-000000000012', 'Dispositivo eletrônico', 'dispositivo eletronico'),
    ('10000000-0000-0000-0000-000000000039', '00000000-0000-0000-0000-000000000012', 'Componente eletrônico', 'componente eletronico'),
    ('10000000-0000-0000-0000-000000000040', '00000000-0000-0000-0000-000000000012', 'Equipamento eletrônico', 'equipamento eletronico'),
    ('10000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000012', 'Hardware de computador', 'hardware de computador'),
    ('10000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000012', 'Eletrônicos', 'eletronicos');
