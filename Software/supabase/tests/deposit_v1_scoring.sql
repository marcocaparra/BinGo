begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(40);

select extensions.is(
    (select count(*)::integer from public.waste_categories),
    6,
    'catalogo de producao possui as seis categorias canonicas'
);
select extensions.hasnt_column('public', 'deposits', 'size', 'deposits.size foi removido');
select extensions.hasnt_column('public', 'school_settings', 'points_small_student', 'pontuacao por tamanho foi removida');
select extensions.has_function(
    'public',
    'register_deposit_v1',
    array['uuid', 'uuid', 'uuid', 'boolean', 'uuid', 'text', 'text', 'text'],
    'RPC atomica existe com a assinatura esperada'
);

insert into public.schools (id, name)
values ('91000000-0000-4000-8000-000000000001', 'Escola teste RPC');

insert into public.school_settings (school_id)
values ('91000000-0000-4000-8000-000000000001');

insert into public.classes (id, school_id, segment, grade, name)
values (
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    'TESTE',
    '1',
    'Turma RPC'
);

insert into public.students (id, school_id, class_id, name, status)
values (
    '93000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000001',
    'Aluno RPC',
    'ACTIVE'
);

insert into public.machines (id, school_id, name, status)
values (
    '94000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    'Totem RPC',
    'ONLINE'
);

update public.waste_categories
set bonus_rate = case code
    when 'BATTERY' then 1.0000
    when 'MOBILE_DEVICE' then 0.5000
    when 'CABLE_WIRE' then 0.2500
    else 0
end;

select extensions.lives_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000001',
        '94000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000001',
        true,
        '93000000-0000-4000-8000-000000000001',
        'pilha',
        'BATTERY',
        'AI_CONFIRMED'
    )
    $$,
    'descarte de bateria e registrado'
);
select extensions.is(
    (select points_awarded_student from public.deposits where event_id = '95000000-0000-4000-8000-000000000001'),
    1600,
    'bateria concede 800 BinCoins base e 800 de bonus'
);
select extensions.is(
    (select bonus_bincoins_awarded from public.deposits where event_id = '95000000-0000-4000-8000-000000000001'),
    800,
    'bonus concedido fica persistido separadamente'
);
select extensions.is(
    (
        select result.category_source
        from public.register_deposit_v1(
            '95000000-0000-4000-8000-000000000001',
            '94000000-0000-4000-8000-000000000001',
            '92000000-0000-4000-8000-000000000001',
            true,
            '93000000-0000-4000-8000-000000000001',
            'pilha',
            'BATTERY',
            'AI_CONFIRMED'
        ) as result
    ),
    'AI_CONFIRMED',
    'RPC retorna category_source da fotografia persistida'
);
select extensions.is(
    (select points_awarded_class from public.deposits where event_id = '95000000-0000-4000-8000-000000000001'),
    1900,
    'categoria nao altera o XP da turma'
);

select * from public.register_deposit_v1(
    '95000000-0000-4000-8000-000000000001',
    '94000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000001',
    true,
    '93000000-0000-4000-8000-000000000001',
    'pilha',
    'BATTERY',
    'AI_CONFIRMED'
);

select extensions.is(
    (select count(*)::integer from public.deposits where event_id = '95000000-0000-4000-8000-000000000001'),
    1,
    'retry nao duplica o evento'
);
select extensions.is(
    (select points_student_balance from public.students where id = '93000000-0000-4000-8000-000000000001'),
    1600,
    'retry nao duplica BinCoins'
);
select extensions.is(
    (select points_class_balance from public.classes where id = '92000000-0000-4000-8000-000000000001'),
    1900,
    'retry nao duplica XP'
);
select extensions.is(
    (select count(*)::integer from public.audit_logs where action = 'DEPOSIT_REGISTERED'),
    1,
    'retry nao duplica auditoria'
);

select extensions.lives_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000004',
        '94000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000001',
        true,
        '93000000-0000-4000-8000-000000000001',
        'celular',
        'MOBILE_DEVICE',
        'AI_CONFIRMED'
    )
    $$,
    'descarte de dispositivo movel e registrado'
);
select extensions.is(
    (select points_awarded_student from public.deposits where event_id = '95000000-0000-4000-8000-000000000004'),
    1200,
    'dispositivo movel concede 800 BinCoins base e 400 de bonus'
);
select extensions.is(
    (select bonus_bincoins_awarded from public.deposits where event_id = '95000000-0000-4000-8000-000000000004'),
    400,
    'dispositivo movel preserva bonus de 50 por cento'
);
select extensions.is(
    (select points_awarded_class from public.deposits where event_id = '95000000-0000-4000-8000-000000000004'),
    1900,
    'dispositivo movel nao multiplica XP pela categoria'
);

select extensions.lives_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000005',
        '94000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000001',
        true,
        '93000000-0000-4000-8000-000000000001',
        'cabo',
        'CABLE_WIRE',
        'USER_CORRECTED'
    )
    $$,
    'descarte de cabo e registrado'
);
select extensions.is(
    (select points_awarded_student from public.deposits where event_id = '95000000-0000-4000-8000-000000000005'),
    1000,
    'cabo concede 800 BinCoins base e 200 de bonus'
);
select extensions.is(
    (select bonus_bincoins_awarded from public.deposits where event_id = '95000000-0000-4000-8000-000000000005'),
    200,
    'cabo preserva bonus de 25 por cento'
);
select extensions.is(
    (select points_awarded_class from public.deposits where event_id = '95000000-0000-4000-8000-000000000005'),
    1900,
    'cabo nao multiplica XP pela categoria'
);

select extensions.lives_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000006',
        '94000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000001',
        true,
        '93000000-0000-4000-8000-000000000001',
        'mouse',
        'PERIPHERAL',
        'AI_CONFIRMED'
    )
    $$,
    'descarte sem bonus e registrado'
);
select extensions.is(
    (select points_awarded_student from public.deposits where event_id = '95000000-0000-4000-8000-000000000006'),
    800,
    'categoria sem bonus concede somente 800 BinCoins base'
);
select extensions.is(
    (select bonus_bincoins_awarded from public.deposits where event_id = '95000000-0000-4000-8000-000000000006'),
    0,
    'categoria sem bonus persiste bonus zero'
);
select extensions.is(
    (select points_awarded_class from public.deposits where event_id = '95000000-0000-4000-8000-000000000006'),
    1900,
    'categoria sem bonus concede 1900 XP'
);

select extensions.lives_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000007',
        '94000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000001',
        false,
        '93000000-0000-4000-8000-000000000001',
        'objeto invalido',
        null,
        null
    )
    $$,
    'descarte invalido e registrado sem recompensa'
);
select extensions.is(
    (select points_awarded_student from public.deposits where event_id = '95000000-0000-4000-8000-000000000007'),
    0,
    'descarte invalido nao concede BinCoins'
);
select extensions.is(
    (select bonus_bincoins_awarded from public.deposits where event_id = '95000000-0000-4000-8000-000000000007'),
    0,
    'descarte invalido nao concede bonus'
);
select extensions.is(
    (select points_awarded_class from public.deposits where event_id = '95000000-0000-4000-8000-000000000007'),
    0,
    'descarte invalido nao concede XP'
);

select extensions.throws_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000001',
        '94000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000001',
        true,
        '93000000-0000-4000-8000-000000000001',
        'pilha',
        'CABLE_WIRE',
        'AI_CONFIRMED'
    )
    $$,
    '23505',
    'event_id reutilizado com dados diferentes.',
    'colisao semantica de event_id e rejeitada'
);

select extensions.throws_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000011',
        '94000000-0000-4000-8000-000000000001',
        '92999999-9999-4999-8999-999999999999',
        true,
        null,
        'pilha',
        'BATTERY',
        'AI_CONFIRMED'
    )
    $$,
    '23503',
    'Turma invalida para a escola da maquina.',
    'turma fora do contexto emite SQLSTATE 23503'
);

select extensions.throws_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000012',
        '94000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000001',
        true,
        '93999999-9999-4999-8999-999999999999',
        'pilha',
        'BATTERY',
        'AI_CONFIRMED'
    )
    $$,
    '23503',
    'Aluno invalido para a escola e turma informadas.',
    'aluno fora do contexto emite SQLSTATE 23503'
);

select extensions.throws_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000013',
        '94000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000001',
        true,
        null,
        'pilha',
        'UNKNOWN',
        'AI_CONFIRMED'
    )
    $$,
    '23514',
    'A categoria UNKNOWN exige origem UNIDENTIFIED.',
    'categoria e origem incompatíveis emitem SQLSTATE 23514'
);

select extensions.lives_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000002',
        '94000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000001',
        true,
        null,
        'pilha',
        'BATTERY',
        'USER_CORRECTED'
    )
    $$,
    'descarte sem aluno e aceito'
);
select extensions.is(
    (select points_awarded_student from public.deposits where event_id = '95000000-0000-4000-8000-000000000002'),
    0,
    'descarte sem aluno nao concede BinCoins nem bonus'
);
select extensions.is(
    (select points_awarded_class from public.deposits where event_id = '95000000-0000-4000-8000-000000000002'),
    1900,
    'descarte sem aluno ainda concede XP'
);

update public.waste_categories set is_active = false where code = 'CABLE_WIRE';
select extensions.throws_ok(
    $$
    select * from public.register_deposit_v1(
        '95000000-0000-4000-8000-000000000003',
        '94000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000001',
        true,
        '93000000-0000-4000-8000-000000000001',
        'cabo',
        'CABLE_WIRE',
        'AI_CONFIRMED'
    )
    $$,
    'P0002',
    'Categoria de lixo eletronico inexistente ou inativa.',
    'categoria inativa e rejeitada'
);

select extensions.ok(
    not has_function_privilege(
        'anon',
        'public.register_deposit_v1(uuid,uuid,uuid,boolean,uuid,text,text,text)',
        'EXECUTE'
    ),
    'anon nao executa a RPC'
);
select extensions.ok(
    not has_function_privilege(
        'authenticated',
        'public.register_deposit_v1(uuid,uuid,uuid,boolean,uuid,text,text,text)',
        'EXECUTE'
    ),
    'authenticated nao executa a RPC'
);
select extensions.ok(
    has_function_privilege(
        'service_role',
        'public.register_deposit_v1(uuid,uuid,uuid,boolean,uuid,text,text,text)',
        'EXECUTE'
    ),
    'service_role executa a RPC'
);

select * from extensions.finish();
rollback;
