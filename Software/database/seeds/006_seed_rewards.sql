insert into rewards (
    id,
    school_id,
    name,
    description,
    cost_points,
    category,
    is_active,
    stock_qty
)
values
(
    '66666666-6666-6666-6666-666666666661',
    '11111111-1111-1111-1111-111111111111',
    'Água 200ml',
    'Recompensa básica de teste',
    3000,
    'CANTINA',
    true,
    20
),
(
    '66666666-6666-6666-6666-666666666662',
    '11111111-1111-1111-1111-111111111111',
    'Doce simples',
    'Recompensa doce para teste',
    5000,
    'CANTINA',
    true,
    15
),
(
    '66666666-6666-6666-6666-666666666663',
    '11111111-1111-1111-1111-111111111111',
    'Caneta',
    'Item escolar de teste',
    7000,
    'ESCOLAR',
    true,
    10
);
