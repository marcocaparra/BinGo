-- Fixture de desenvolvimento V1 reescrita explicitamente como A/B/C.
-- Nao e um mapa de conversao dos papeis historicos nem uma seed de usuarios Auth.
insert into admins (
    id,
    school_id,
    name,
    email,
    role
)
values
(
    '44444444-4444-4444-4444-444444444441',
    '11111111-1111-1111-1111-111111111111',
    'Admin Principal',
    'admin@bingo.local',
    'ADMIN_B'
),
(
    '44444444-4444-4444-4444-444444444442',
    '11111111-1111-1111-1111-111111111111',
    'Admin Operacional V1',
    'operacional@bingo.local',
    'ADMIN_C'
),
(
    '44444444-4444-4444-4444-444444444443',
    null,
    'Admin Global V1',
    'global@bingo.local',
    'ADMIN_A'
);
