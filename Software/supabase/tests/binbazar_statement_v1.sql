begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

create function pg_temp.raises_state(command text, expected_state text)
returns boolean
language plpgsql
as $$
begin
    execute command;
    return false;
exception
    when others then
        return sqlstate = expected_state;
end;
$$;

select extensions.ok(
    to_regprocedure('public.request_redemption_v1(uuid,uuid)') is not null
    and to_regprocedure('public.cancel_my_redemption_v1(uuid)') is not null
    and to_regprocedure('public.get_my_binbazar_catalog_v1()') is not null
    and to_regprocedure('public.get_my_redemptions_v1()') is not null
    and to_regprocedure('public.get_my_bincoin_statement_v1()') is not null,
    'RPCs BinBazar e Extrato V1 existem'
);

select extensions.ok(
    not has_function_privilege('anon', 'public.request_redemption_v1(uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.cancel_my_redemption_v1(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.get_my_binbazar_catalog_v1()', 'execute')
    and not has_function_privilege('anon', 'public.get_my_redemptions_v1()', 'execute')
    and not has_function_privilege('anon', 'public.get_my_bincoin_statement_v1()', 'execute')
    and has_function_privilege('authenticated', 'public.request_redemption_v1(uuid,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.cancel_my_redemption_v1(uuid)', 'execute'),
    'anon e recusado e authenticated recebe somente as RPCs'
);

select extensions.ok(
    pg_temp.raises_state(
        $$set local role anon; select * from public.get_my_binbazar_catalog_v1()$$,
        '42501'
    )
    and pg_temp.raises_state(
        $$set local role anon; select * from public.request_redemption_v1(gen_random_uuid(), gen_random_uuid())$$,
        '42501'
    ),
    'anon e recusado em leitura e mutacao reais'
);

select extensions.ok(
    exists (
        select 1
        from pg_indexes
        where schemaname = 'public'
          and tablename = 'redemptions'
          and indexname = 'redemptions_client_request_id_unique'
          and indexdef ilike '%where (client_request_id is not null)%'
    ),
    'client_request_id possui unicidade parcial sem afetar linhas legadas nulas'
);

insert into public.schools (id, name)
values
    ('b1000000-0000-4000-8000-000000000001', 'Escola Bazaar A'),
    ('b1000000-0000-4000-8000-000000000002', 'Escola Bazaar B');

insert into public.classes (id, school_id, segment, grade, name)
values
    ('b2000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'TEST', '1', 'Turma A'),
    ('b2000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000002', 'TEST', '1', 'Turma B');

insert into public.students (
    id, school_id, class_id, name, points_student_balance, status, auth_user_id
)
values
    ('b3000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001', 'Aluno A', 1000, 'ACTIVE', 'b9000000-0000-4000-8000-000000000001'),
    ('b3000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000002', 'Aluno B', 1000, 'ACTIVE', 'b9000000-0000-4000-8000-000000000002'),
    ('b3000000-0000-4000-8000-000000000003', 'b1000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001', 'Aluno inativo', 1000, 'INACTIVE', 'b9000000-0000-4000-8000-000000000003');

insert into public.rewards (
    id, school_id, name, description, cost_points, is_active, status, stock_qty
)
values
    ('b5000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'Produto finito', 'Uma unidade', 300, true, 'DISABLED', 1),
    ('b5000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000001', 'Produto ilimitado', null, 200, true, 'OUT_OF_STOCK', null),
    ('b5000000-0000-4000-8000-000000000003', 'b1000000-0000-4000-8000-000000000001', 'Produto esgotado', null, 100, true, 'AVAILABLE', 0),
    ('b5000000-0000-4000-8000-000000000004', 'b1000000-0000-4000-8000-000000000001', 'Produto inativo', null, 100, false, 'AVAILABLE', 5),
    ('b5000000-0000-4000-8000-000000000005', 'b1000000-0000-4000-8000-000000000001', 'Produto caro', null, 900, true, 'AVAILABLE', null),
    ('b5000000-0000-4000-8000-000000000006', 'b1000000-0000-4000-8000-000000000001', 'Produto entrega', null, 100, true, 'AVAILABLE', null),
    ('b5000000-0000-4000-8000-000000000007', 'b1000000-0000-4000-8000-000000000002', 'Produto outra escola', null, 100, true, 'AVAILABLE', 2),
    ('b5000000-0000-4000-8000-000000000008', 'b1000000-0000-4000-8000-000000000001', 'Produto muda para ilimitado', null, 50, true, 'AVAILABLE', 1);

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select extensions.results_eq(
    $$select reward_id from public.get_my_binbazar_catalog_v1() order by reward_id$$,
    $$values
        ('b5000000-0000-4000-8000-000000000001'::uuid),
        ('b5000000-0000-4000-8000-000000000002'::uuid),
        ('b5000000-0000-4000-8000-000000000003'::uuid),
        ('b5000000-0000-4000-8000-000000000005'::uuid),
        ('b5000000-0000-4000-8000-000000000006'::uuid),
        ('b5000000-0000-4000-8000-000000000008'::uuid)$$,
    'catalogo usa escola e is_active, preserva esgotado e ignora rewards.status legado'
);

select * from public.request_redemption_v1(
    'ba000000-0000-4000-8000-000000000001',
    'b5000000-0000-4000-8000-000000000001'
);
reset role;

select extensions.is(
    (select points_student_balance from public.students where id = 'b3000000-0000-4000-8000-000000000001'),
    700,
    'criacao debita saldo imediatamente'
);
select extensions.is(
    (select stock_qty from public.rewards where id = 'b5000000-0000-4000-8000-000000000001'),
    0,
    'criacao reserva estoque finito imediatamente'
);
select extensions.ok(
    exists (
        select 1 from public.redemptions
        where client_request_id = 'ba000000-0000-4000-8000-000000000001'
          and reward_name_snapshot = 'Produto finito'
          and cost_points_snapshot = 300
          and stock_was_finite
          and status = 'PENDING'
          and request_channel = 'MOBILE'
          and expires_at is null
    ),
    'pedido novo fotografa produto e nasce PENDING/MOBILE sem expiracao'
);

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select extensions.is(
    (select replayed from public.request_redemption_v1('ba000000-0000-4000-8000-000000000001', 'b5000000-0000-4000-8000-000000000001')),
    true,
    'replay do mesmo request_id devolve o mesmo pedido'
);
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.request_redemption_v1('ba000000-0000-4000-8000-000000000001', 'b5000000-0000-4000-8000-000000000002')$$,
        '23505'
    ),
    'request_id com semantica diferente e conflito'
);
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.request_redemption_v1('ba000000-0000-4000-8000-000000000003', 'b5000000-0000-4000-8000-000000000003')$$,
        '23514'
    ),
    'estoque zero e recusado'
);
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.request_redemption_v1('ba000000-0000-4000-8000-000000000004', 'b5000000-0000-4000-8000-000000000004')$$,
        '23514'
    ),
    'produto inativo e recusado'
);
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.request_redemption_v1('ba000000-0000-4000-8000-000000000005', 'b5000000-0000-4000-8000-000000000005')$$,
        '23514'
    ),
    'saldo insuficiente e recusado'
);
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.request_redemption_v1('ba000000-0000-4000-8000-000000000007', 'b5000000-0000-4000-8000-000000000007')$$,
        '23503'
    ),
    'produto de outra escola e recusado'
);
select * from public.request_redemption_v1(
    'ba000000-0000-4000-8000-000000000002',
    'b5000000-0000-4000-8000-000000000002'
);
reset role;

select extensions.ok(
    (select stock_qty is null from public.rewards where id = 'b5000000-0000-4000-8000-000000000002')
    and (select points_student_balance = 500 from public.students where id = 'b3000000-0000-4000-8000-000000000001'),
    'estoque ilimitado permanece nulo e saldo e cobrado'
);

update public.rewards
set name = 'Nome alterado', cost_points = 777
where id = 'b5000000-0000-4000-8000-000000000001';

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select extensions.ok(
    exists (
        select 1 from public.get_my_redemptions_v1()
        where reward_id = 'b5000000-0000-4000-8000-000000000001'
          and reward_name = 'Produto finito'
          and cost_points = 300
    ),
    'leitura historica usa snapshots mesmo apos alteracao do produto'
);
select * from public.cancel_my_redemption_v1(
    (select redemption_id from public.get_my_redemptions_v1() where reward_id = 'b5000000-0000-4000-8000-000000000001')
);
reset role;

select extensions.ok(
    (select points_student_balance = 800 from public.students where id = 'b3000000-0000-4000-8000-000000000001')
    and (select stock_qty = 1 from public.rewards where id = 'b5000000-0000-4000-8000-000000000001')
    and (select canceled_at is not null from public.redemptions where client_request_id = 'ba000000-0000-4000-8000-000000000001')
    and exists (
        select 1
        from public.audit_logs
        where action = 'REDEMPTION_CANCELED_V1'
          and metadata ->> 'redemption_id' = (
              select id::text from public.redemptions
              where client_request_id = 'ba000000-0000-4000-8000-000000000001'
          )
          and metadata ->> 'finite_stock_reserved' = 'true'
          and metadata ->> 'finite_stock_restored' = 'true'
    ),
    'primeiro cancelamento devolve snapshot e restaura uma unidade finita'
);

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select extensions.is(
    (select replayed from public.cancel_my_redemption_v1((select redemption_id from public.get_my_redemptions_v1() where reward_id = 'b5000000-0000-4000-8000-000000000001'))),
    true,
    'retry de cancelamento e idempotente'
);
reset role;
select extensions.ok(
    (select points_student_balance = 800 from public.students where id = 'b3000000-0000-4000-8000-000000000001')
    and (select stock_qty = 1 from public.rewards where id = 'b5000000-0000-4000-8000-000000000001'),
    'retry de cancelamento nao credita nem restaura novamente'
);

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select * from public.request_redemption_v1('ba000000-0000-4000-8000-000000000006', 'b5000000-0000-4000-8000-000000000006');
reset role;
update public.redemptions set status = 'DELIVERED', delivered_at = now()
where client_request_id = 'ba000000-0000-4000-8000-000000000006';
select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.cancel_my_redemption_v1((select redemption_id from public.get_my_redemptions_v1() where reward_id = 'b5000000-0000-4000-8000-000000000006'))$$,
        '55000'
    ),
    'cancelamento apos entrega e recusado'
);
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select * from public.request_redemption_v1(
    'ba000000-0000-4000-8000-00000000000b',
    'b5000000-0000-4000-8000-000000000008'
);
reset role;
update public.rewards
set stock_qty = null
where id = 'b5000000-0000-4000-8000-000000000008';
select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select * from public.cancel_my_redemption_v1(
    (select redemption_id from public.get_my_redemptions_v1()
     where reward_id = 'b5000000-0000-4000-8000-000000000008')
);
reset role;
select extensions.ok(
    (select points_student_balance = 700 from public.students where id = 'b3000000-0000-4000-8000-000000000001')
    and (select stock_qty is null from public.rewards where id = 'b5000000-0000-4000-8000-000000000008')
    and exists (
        select 1
        from public.audit_logs
        where action = 'REDEMPTION_CANCELED_V1'
          and metadata ->> 'redemption_id' = (
              select id::text from public.redemptions
              where client_request_id = 'ba000000-0000-4000-8000-00000000000b'
          )
          and metadata ->> 'finite_stock_reserved' = 'true'
          and metadata ->> 'finite_stock_restored' = 'false'
    ),
    'cancelamento preserva estoque ilimitado atual e audita que nenhuma unidade foi incrementada'
);

insert into public.redemptions (
    id, school_id, student_id, reward_id, code, status, request_channel,
    client_request_id, reward_name_snapshot, cost_points_snapshot,
    stock_was_finite
)
values (
    'b8000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'b3000000-0000-4000-8000-000000000001',
    'b5000000-0000-4000-8000-000000000002',
    'BGO-ISOLATION', 'PENDING', 'MOBILE',
    'ba000000-0000-4000-8000-00000000000a',
    'Produto isolado', 200, false
);

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select extensions.is((select count(*) from public.get_my_redemptions_v1()), 0::bigint, 'historico isola aluno');
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.cancel_my_redemption_v1('b8000000-0000-4000-8000-000000000001')$$,
        'P0002'
    ),
    'aluno nao cancela pedido de outro aluno'
);
reset role;
delete from public.redemptions where id = 'b8000000-0000-4000-8000-000000000001';

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000003', true);
set local role authenticated;
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.request_redemption_v1('ba000000-0000-4000-8000-000000000008', 'b5000000-0000-4000-8000-000000000002')$$,
        '23514'
    ),
    'aluno inativo e recusado'
);
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-00000000ffff', true);
set local role authenticated;
select extensions.is((select count(*) from public.get_my_binbazar_catalog_v1()), 0::bigint, 'Auth sem vinculo nao recebe catalogo');
select extensions.is((select count(*) from public.get_my_redemptions_v1()), 0::bigint, 'Auth sem vinculo nao recebe pedidos');
select extensions.is((select count(*) from public.get_my_bincoin_statement_v1()), 0::bigint, 'Auth sem vinculo nao recebe Extrato');
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.request_redemption_v1('ba000000-0000-4000-8000-000000000009', 'b5000000-0000-4000-8000-000000000002')$$,
        'P0002'
    ),
    'Auth sem vinculo nao cria resgate'
);
reset role;

insert into public.machines (id, school_id, name, status)
values ('b4000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'Totem extrato', 'ONLINE');
insert into public.deposits (
    id, event_id, school_id, machine_id, class_id, student_id, is_valid,
    detected_type, points_awarded_student, points_awarded_class,
    waste_category_id, category_source, bonus_rate_applied,
    bonus_bincoins_awarded, created_at
)
values (
    'b6000000-0000-4000-8000-000000000001', gen_random_uuid(),
    'b1000000-0000-4000-8000-000000000001',
    'b4000000-0000-4000-8000-000000000001',
    'b2000000-0000-4000-8000-000000000001',
    'b3000000-0000-4000-8000-000000000001', true, 'test', 120, 999,
    (select id from public.waste_categories where code = 'BATTERY'),
    'AI_CONFIRMED', 0, 0, '2026-09-10 12:00:01+00'
);
insert into public.mission_definitions (
    id, code, title, scope, metric, recurrence, target, reward_bincoins, reward_xp
)
values (
    'b7000000-0000-4000-8000-000000000001', 'BAZAAR_STATEMENT_TEST', 'Missao extrato',
    'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 50, 0
);
insert into public.mission_cycles (
    id, definition_id, school_id, starts_at, ends_at, timezone, scope,
    metric, recurrence, target, reward_bincoins, reward_xp
)
values (
    'b7100000-0000-4000-8000-000000000001',
    'b7000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    '2026-09-01 03:00:00+00', '2026-10-01 03:00:00+00', 'America/Sao_Paulo',
    'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 50, 0
);
insert into public.mission_completions (
    id, cycle_id, participant_scope, student_id, progress_at_completion,
    achieved_at, materialized_at
)
values (
    'b7200000-0000-4000-8000-000000000001',
    'b7100000-0000-4000-8000-000000000001', 'STUDENT',
    'b3000000-0000-4000-8000-000000000001', 1,
    '2026-09-10 12:00:00+00', '2026-09-10 12:00:01+00'
);
insert into public.mission_reward_applications (
    id, completion_id, reward_type, amount_applied, recipient_student_id, applied_at
)
values (
    'b7300000-0000-4000-8000-000000000001',
    'b7200000-0000-4000-8000-000000000001', 'BINCOINS', 50,
    'b3000000-0000-4000-8000-000000000001', '2026-09-10 12:00:01+00'
);

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select extensions.ok(
    (select count(*) = 1 from public.get_my_bincoin_statement_v1() where movement_type = 'DEPOSIT' and amount = 120)
    and (select count(*) = 1 from public.get_my_bincoin_statement_v1() where movement_type = 'MISSION_REWARD' and amount = 50)
    and (select count(*) = 4 from public.get_my_bincoin_statement_v1() where movement_type = 'REDEMPTION' and amount < 0)
    and (select count(*) = 1 from public.get_my_bincoin_statement_v1() where movement_type = 'REDEMPTION_REFUND' and amount = 300),
    'Extrato consolida descarte, missao, resgates e refund sem XP'
);
select extensions.results_eq(
    $$select movement_type
      from public.get_my_bincoin_statement_v1()
      where occurred_at = '2026-09-10 12:00:01+00'::timestamptz$$,
    $$values ('DEPOSIT'::text), ('MISSION_REWARD'::text)$$,
    'Extrato desempata occurred_at por origem de forma deterministica'
);
select extensions.ok(
    (select bool_and(previous_at >= occurred_at)
     from (
        select occurred_at, lag(occurred_at) over () as previous_at
        from public.get_my_bincoin_statement_v1()
     ) ordered
     where previous_at is not null),
    'Extrato e ordenado do mais recente para o mais antigo'
);
create temporary table statement_before_delivery as
select count(*) as movements from public.get_my_bincoin_statement_v1();
reset role;
update public.redemptions set delivered_at = delivered_at + interval '1 second'
where client_request_id = 'ba000000-0000-4000-8000-000000000006';
select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select extensions.is(
    (select count(*) from public.get_my_bincoin_statement_v1()),
    (select movements from statement_before_delivery),
    'entrega nao cria movimento no Extrato'
);
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'b9000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select extensions.is(
    (select count(*) from public.get_my_bincoin_statement_v1()),
    0::bigint,
    'Extrato isola explicitamente movimentos entre dois alunos'
);
reset role;

select extensions.is(
    (select count(*) from public.audit_logs where action = 'REDEMPTION_REQUESTED_V1'),
    4::bigint,
    'criacao registra uma auditoria por novo pedido, sem auditar replay'
);
select extensions.is(
    (select count(*) from public.audit_logs where action = 'REDEMPTION_CANCELED_V1'),
    2::bigint,
    'cancelamento registra auditoria somente na primeira transicao'
);

select * from extensions.finish();
rollback;
