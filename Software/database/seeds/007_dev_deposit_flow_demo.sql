-- BinGo V1
-- Seed: 007_dev_deposit_flow_demo.sql
--
-- Seed de desenvolvimento para o fluxo de descarte.
-- Cria uma única escola demo com turmas, alunos, máquina, configurações
-- operacionais e recompensas simples para testes locais.
--
-- Uso futuro esperado:
-- aluno descarta item -> backend registra depósito -> saldo do aluno aumenta
-- -> saldo da turma aumenta.
--
-- Não contém dados reais nem sensíveis.
-- API key demo da máquina "Totem Demo 01": edge-demo-key

insert into schools (
    id,
    name
)
values (
    '10000000-0000-4000-8000-000000000001',
    'Escola Demo BinGo'
)
on conflict (id) do update
set
    name = excluded.name,
    updated_at = now();

insert into school_settings (
    school_id,
    small_item_daily_limit,
    points_small_student,
    points_small_class,
    points_medium_student,
    points_medium_class,
    points_large_student,
    points_large_class,
    redemption_expiration_hours,
    redemption_daily_limit,
    redemption_max_pending
)
values (
    '10000000-0000-4000-8000-000000000001',
    5,
    10,
    10,
    25,
    25,
    50,
    50,
    72,
    3,
    3
)
on conflict (school_id) do update
set
    small_item_daily_limit = excluded.small_item_daily_limit,
    points_small_student = excluded.points_small_student,
    points_small_class = excluded.points_small_class,
    points_medium_student = excluded.points_medium_student,
    points_medium_class = excluded.points_medium_class,
    points_large_student = excluded.points_large_student,
    points_large_class = excluded.points_large_class,
    redemption_expiration_hours = excluded.redemption_expiration_hours,
    redemption_daily_limit = excluded.redemption_daily_limit,
    redemption_max_pending = excluded.redemption_max_pending,
    updated_at = now();

insert into classes (
    id,
    school_id,
    segment,
    grade,
    name,
    points_class_balance
)
values
(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'FUNDAMENTAL_2',
    '6',
    U&'6\00BA Ano A',
    0
),
(
    '20000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    'FUNDAMENTAL_2',
    '7',
    U&'7\00BA Ano B',
    0
),
(
    '20000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    'ENSINO_MEDIO',
    '1',
    U&'1\00AA S\00E9rie A',
    0
)
on conflict (id) do update
set
    school_id = excluded.school_id,
    segment = excluded.segment,
    grade = excluded.grade,
    name = excluded.name,
    points_class_balance = excluded.points_class_balance,
    updated_at = now();

insert into students (
    id,
    school_id,
    class_id,
    name,
    pin_hash,
    is_activated,
    points_student_balance,
    status
)
values
(
    '30000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'Ana Silva',
    null,
    false,
    0,
    'ACTIVE'
),
(
    '30000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'Lucas Costa',
    null,
    false,
    0,
    'ACTIVE'
),
(
    '30000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'Pedro Santos',
    null,
    false,
    0,
    'ACTIVE'
),
(
    '30000000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    U&'Jo\00E3o Teste',
    null,
    false,
    0,
    'ACTIVE'
),
(
    '30000000-0000-4000-8000-000000000005',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000003',
    'Maria Oliveira',
    null,
    false,
    0,
    'ACTIVE'
)
on conflict (id) do update
set
    school_id = excluded.school_id,
    class_id = excluded.class_id,
    name = excluded.name,
    pin_hash = excluded.pin_hash,
    is_activated = excluded.is_activated,
    points_student_balance = excluded.points_student_balance,
    status = excluded.status,
    updated_at = now();

insert into machines (
    id,
    school_id,
    name,
    status,
    firmware_version,
    bin_full,
    camera_ok,
    net_ok,
    api_key_hash
)
values (
    '40000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'Totem Demo 01',
    'ONLINE',
    'demo-v0',
    false,
    true,
    true,
    'YmluZ28tZGVtby1zYWx0IQ==$M1Bg8EYwAODbcgGwHjImY/4O48MTxxKyE7Vn8BdOMJI='
)
on conflict (id) do update
set
    school_id = excluded.school_id,
    name = excluded.name,
    status = excluded.status,
    firmware_version = excluded.firmware_version,
    bin_full = excluded.bin_full,
    camera_ok = excluded.camera_ok,
    net_ok = excluded.net_ok,
    api_key_hash = excluded.api_key_hash,
    updated_at = now();

insert into rewards (
    id,
    school_id,
    name,
    description,
    cost_points,
    category,
    is_active,
    status,
    stock_qty
)
values
(
    '50000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    U&'\00C1gua/Suco',
    'Bebida simples para teste de resgate futuro',
    30,
    'CANTINA',
    true,
    'AVAILABLE',
    20
),
(
    '50000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    'Doce simples',
    'Recompensa simples para teste de resgate futuro',
    50,
    'CANTINA',
    true,
    'AVAILABLE',
    15
),
(
    '50000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    'Brinde BinGo',
    'Brinde escolar para teste de resgate futuro',
    40,
    'ESCOLAR',
    true,
    'AVAILABLE',
    10
)
on conflict (id) do update
set
    school_id = excluded.school_id,
    name = excluded.name,
    description = excluded.description,
    cost_points = excluded.cost_points,
    category = excluded.category,
    is_active = excluded.is_active,
    status = excluded.status,
    stock_qty = excluded.stock_qty,
    updated_at = now();
