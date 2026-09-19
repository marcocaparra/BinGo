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
    to_regprocedure('public.get_active_missions_v1()') is not null,
    'RPC get_active_missions_v1 sem parametros existe'
);

select extensions.ok(
    (
        select function_row.prosecdef
           and function_row.provolatile = 's'
           and function_row.proconfig = array['search_path=""']
        from pg_catalog.pg_proc as function_row
        where function_row.oid = 'public.get_active_missions_v1()'::regprocedure
    ),
    'RPC e STABLE, SECURITY DEFINER e possui search_path vazio'
);

select extensions.ok(
    not has_function_privilege(
        'anon', 'public.get_active_missions_v1()', 'execute'
    )
    and has_function_privilege(
        'authenticated', 'public.get_active_missions_v1()', 'execute'
    )
    and not has_function_privilege(
        'service_role', 'public.get_active_missions_v1()', 'execute'
    ),
    'somente authenticated recebe EXECUTE na RPC'
);

select extensions.ok(
    pg_temp.raises_state(
        $$set local role anon; select * from public.get_active_missions_v1()$$,
        '42501'
    ),
    'anon nao executa a RPC'
);

select extensions.ok(
    pg_get_function_result('public.get_active_missions_v1()'::regprocedure)
        ~ '^TABLE\(cycle_id uuid, definition_id uuid, definition_code text, definition_title text, scope text, metric text, starts_at timestamp with time zone, ends_at timestamp with time zone, target bigint, reward_bincoins integer, reward_xp integer, progress bigint, is_achieved boolean, achieved_at timestamp with time zone, is_completed boolean, materialized_at timestamp with time zone\)$',
    'contrato de retorno contem somente os dezesseis campos aprovados'
);

insert into public.schools (id, name)
values
    ('b1000000-0000-4000-8000-000000000001', 'Escola RPC A'),
    ('b1000000-0000-4000-8000-000000000002', 'Escola RPC B');

insert into public.classes (
    id, school_id, segment, grade, name, points_class_balance
)
values
    (
        'b2000000-0000-4000-8000-000000000001',
        'b1000000-0000-4000-8000-000000000001',
        'TESTE', '7', 'Turma historica', 111100
    ),
    (
        'b2000000-0000-4000-8000-000000000002',
        'b1000000-0000-4000-8000-000000000001',
        'TESTE', '8', 'Turma atual', 999900
    ),
    (
        'b2000000-0000-4000-8000-000000000003',
        'b1000000-0000-4000-8000-000000000002',
        'TESTE', '9', 'Turma outra escola', 555500
    );

insert into public.students (
    id, school_id, class_id, name, is_activated,
    points_student_balance, status, auth_user_id
)
values
    (
        'b3000000-0000-4000-8000-000000000001',
        'b1000000-0000-4000-8000-000000000001',
        'b2000000-0000-4000-8000-000000000002',
        'Aluno RPC ativo', false, 777700, 'ACTIVE',
        'b9000000-0000-4000-8000-000000000001'
    ),
    (
        'b3000000-0000-4000-8000-000000000002',
        'b1000000-0000-4000-8000-000000000001',
        'b2000000-0000-4000-8000-000000000002',
        'Colega RPC', true, 0, 'ACTIVE',
        'b9000000-0000-4000-8000-000000000002'
    ),
    (
        'b3000000-0000-4000-8000-000000000003',
        'b1000000-0000-4000-8000-000000000001',
        'b2000000-0000-4000-8000-000000000002',
        'Aluno RPC inativo', true, 0, 'INACTIVE',
        'b9000000-0000-4000-8000-000000000003'
    ),
    (
        'b3000000-0000-4000-8000-000000000004',
        'b1000000-0000-4000-8000-000000000002',
        'b2000000-0000-4000-8000-000000000003',
        'Aluno RPC outra escola', true, 0, 'ACTIVE',
        'b9000000-0000-4000-8000-000000000004'
    );

insert into public.machines (id, school_id, name, status)
values
    (
        'b4000000-0000-4000-8000-000000000001',
        'b1000000-0000-4000-8000-000000000001',
        'Maquina RPC A', 'ONLINE'
    ),
    (
        'b4000000-0000-4000-8000-000000000002',
        'b1000000-0000-4000-8000-000000000002',
        'Maquina RPC B', 'ONLINE'
    );

insert into public.mission_definitions (
    id, code, title, scope, metric, recurrence, target,
    reward_bincoins, reward_xp
)
values
    (
        'b5000000-0000-4000-8000-000000000001',
        'A_STUDENT_ACTIVE', 'A Student ativa',
        'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 2, 500, 0
    ),
    (
        'b5000000-0000-4000-8000-000000000002',
        'B_CLASS_ACTIVE', 'B Class ativa',
        'CLASS', 'CLASS_XP_EARNED', 'MONTHLY', 3000, 0, 600
    ),
    (
        'b5000000-0000-4000-8000-000000000003',
        'C_STUDENT_ACTIVE', 'C Student ativa',
        'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 10, 100, 0
    ),
    (
        'b5000000-0000-4000-8000-000000000004',
        'D_OTHER_SCHOOL', 'D outra escola',
        'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 100, 0
    ),
    (
        'b5000000-0000-4000-8000-000000000005',
        'E_FUTURE', 'E futura',
        'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 100, 0
    ),
    (
        'b5000000-0000-4000-8000-000000000006',
        'F_ENDED', 'F encerrada',
        'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 100, 0
    );

with bounds as (
    select
        date_trunc(
            'month', pg_catalog.now() at time zone 'America/Sao_Paulo'
        ) at time zone 'America/Sao_Paulo' as active_start
)
insert into public.mission_cycles (
    id, definition_id, school_id, starts_at, ends_at, timezone,
    scope, metric, recurrence, target, reward_bincoins, reward_xp
)
select
    cycle.id,
    cycle.definition_id,
    cycle.school_id,
    cycle.starts_at,
    cycle.ends_at,
    'America/Sao_Paulo',
    cycle.scope,
    cycle.metric,
    'MONTHLY',
    cycle.target,
    cycle.reward_bincoins,
    cycle.reward_xp
from bounds
cross join lateral (
    values
        (
            'b6000000-0000-4000-8000-000000000001'::uuid,
            'b5000000-0000-4000-8000-000000000001'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            bounds.active_start,
            bounds.active_start + interval '1 month',
            'STUDENT'::text, 'VALID_DEPOSIT_COUNT'::text,
            2::bigint, 500::integer, 0::integer
        ),
        (
            'b6000000-0000-4000-8000-000000000002'::uuid,
            'b5000000-0000-4000-8000-000000000002'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            bounds.active_start,
            bounds.active_start + interval '1 month',
            'CLASS'::text, 'CLASS_XP_EARNED'::text,
            3000::bigint, 0::integer, 600::integer
        ),
        (
            'b6000000-0000-4000-8000-000000000003'::uuid,
            'b5000000-0000-4000-8000-000000000003'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            bounds.active_start,
            bounds.active_start + interval '1 month',
            'STUDENT'::text, 'VALID_DEPOSIT_COUNT'::text,
            10::bigint, 100::integer, 0::integer
        ),
        (
            'b6000000-0000-4000-8000-000000000004'::uuid,
            'b5000000-0000-4000-8000-000000000004'::uuid,
            'b1000000-0000-4000-8000-000000000002'::uuid,
            bounds.active_start,
            bounds.active_start + interval '1 month',
            'STUDENT'::text, 'VALID_DEPOSIT_COUNT'::text,
            1::bigint, 100::integer, 0::integer
        ),
        (
            'b6000000-0000-4000-8000-000000000005'::uuid,
            'b5000000-0000-4000-8000-000000000005'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            bounds.active_start + interval '1 month',
            bounds.active_start + interval '2 months',
            'STUDENT'::text, 'VALID_DEPOSIT_COUNT'::text,
            1::bigint, 100::integer, 0::integer
        ),
        (
            'b6000000-0000-4000-8000-000000000006'::uuid,
            'b5000000-0000-4000-8000-000000000006'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            bounds.active_start - interval '1 month',
            bounds.active_start,
            'STUDENT'::text, 'VALID_DEPOSIT_COUNT'::text,
            1::bigint, 100::integer, 0::integer
        )
) as cycle(
    id, definition_id, school_id, starts_at, ends_at,
    scope, metric, target, reward_bincoins, reward_xp
);

with bounds as (
    select
        date_trunc(
            'month', pg_catalog.now() at time zone 'America/Sao_Paulo'
        ) at time zone 'America/Sao_Paulo' as active_start
), category as (
    select id
    from public.waste_categories
    where code = 'UNKNOWN'
)
insert into public.deposits (
    id, event_id, school_id, machine_id, class_id, student_id,
    is_valid, detected_type, points_awarded_student,
    points_awarded_class, created_at, waste_category_id,
    category_source, bonus_rate_applied, bonus_bincoins_awarded
)
select
    deposit.id,
    deposit.event_id,
    deposit.school_id,
    deposit.machine_id,
    deposit.class_id,
    deposit.student_id,
    deposit.is_valid,
    'TEST',
    0,
    deposit.points_awarded_class,
    deposit.created_at,
    case when deposit.is_valid then category.id else null end,
    case when deposit.is_valid then 'UNIDENTIFIED' else null end,
    0,
    0
from bounds
cross join category
cross join lateral (
    values
        -- Progresso STUDENT historico: aluno agora esta na turma atual, mas
        -- estes descartes preservam a turma anterior.
        (
            'b7000000-0000-4000-8000-000000000001'::uuid,
            'b8000000-0000-4000-8000-000000000001'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000001'::uuid,
            'b3000000-0000-4000-8000-000000000001'::uuid,
            true, 9000, bounds.active_start + interval '1 hour'
        ),
        (
            'b7000000-0000-4000-8000-000000000002'::uuid,
            'b8000000-0000-4000-8000-000000000002'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000001'::uuid,
            'b3000000-0000-4000-8000-000000000001'::uuid,
            true, 9000, bounds.active_start + interval '2 hours'
        ),
        (
            'b7000000-0000-4000-8000-000000000003'::uuid,
            'b8000000-0000-4000-8000-000000000003'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000001'::uuid,
            'b3000000-0000-4000-8000-000000000001'::uuid,
            true, 9000, bounds.active_start + interval '3 hours'
        ),
        -- Outro aluno nao entra no progresso STUDENT.
        (
            'b7000000-0000-4000-8000-000000000004'::uuid,
            'b8000000-0000-4000-8000-000000000004'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000002'::uuid,
            'b3000000-0000-4000-8000-000000000002'::uuid,
            true, 0, bounds.active_start + interval '3 hours 30 minutes'
        ),
        -- Invalido e fronteiras temporais nao entram.
        (
            'b7000000-0000-4000-8000-000000000005'::uuid,
            'b8000000-0000-4000-8000-000000000005'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000001'::uuid,
            'b3000000-0000-4000-8000-000000000001'::uuid,
            false, 999999, bounds.active_start + interval '4 hours'
        ),
        (
            'b7000000-0000-4000-8000-000000000006'::uuid,
            'b8000000-0000-4000-8000-000000000006'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000001'::uuid,
            'b3000000-0000-4000-8000-000000000001'::uuid,
            true, 999999, bounds.active_start - interval '1 microsecond'
        ),
        (
            'b7000000-0000-4000-8000-000000000007'::uuid,
            'b8000000-0000-4000-8000-000000000007'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000001'::uuid,
            'b3000000-0000-4000-8000-000000000001'::uuid,
            true, 999999, bounds.active_start + interval '1 month'
        ),
        -- Progresso CLASS usa somente a turma atual. Os dois primeiros
        -- eventos empatam no timestamp; id define qual cruza o target.
        (
            'b7000000-0000-4000-8000-000000000010'::uuid,
            'b8000000-0000-4000-8000-000000000010'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000002'::uuid,
            'b3000000-0000-4000-8000-000000000002'::uuid,
            true, 1500, bounds.active_start + interval '5 hours'
        ),
        (
            'b7000000-0000-4000-8000-000000000011'::uuid,
            'b8000000-0000-4000-8000-000000000011'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000002'::uuid,
            'b3000000-0000-4000-8000-000000000002'::uuid,
            true, 2000, bounds.active_start + interval '5 hours'
        ),
        (
            'b7000000-0000-4000-8000-000000000012'::uuid,
            'b8000000-0000-4000-8000-000000000012'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000002'::uuid,
            'b3000000-0000-4000-8000-000000000002'::uuid,
            true, 500, bounds.active_start + interval '6 hours'
        ),
        (
            'b7000000-0000-4000-8000-000000000013'::uuid,
            'b8000000-0000-4000-8000-000000000013'::uuid,
            'b1000000-0000-4000-8000-000000000001'::uuid,
            'b4000000-0000-4000-8000-000000000001'::uuid,
            'b2000000-0000-4000-8000-000000000002'::uuid,
            'b3000000-0000-4000-8000-000000000002'::uuid,
            false, 500000, bounds.active_start + interval '7 hours'
        ),
        -- Outra escola nunca entra.
        (
            'b7000000-0000-4000-8000-000000000014'::uuid,
            'b8000000-0000-4000-8000-000000000014'::uuid,
            'b1000000-0000-4000-8000-000000000002'::uuid,
            'b4000000-0000-4000-8000-000000000002'::uuid,
            'b2000000-0000-4000-8000-000000000003'::uuid,
            'b3000000-0000-4000-8000-000000000004'::uuid,
            true, 700000, bounds.active_start + interval '5 hours'
        )
) as deposit(
    id, event_id, school_id, machine_id, class_id, student_id,
    is_valid, points_awarded_class, created_at
);

with bounds as (
    select
        date_trunc(
            'month', pg_catalog.now() at time zone 'America/Sao_Paulo'
        ) at time zone 'America/Sao_Paulo' as active_start
)
insert into public.mission_completions (
    id, cycle_id, participant_scope, student_id,
    progress_at_completion, achieved_at, materialized_at
)
select
    'ba000000-0000-4000-8000-000000000001',
    'b6000000-0000-4000-8000-000000000001',
    'STUDENT',
    'b3000000-0000-4000-8000-000000000001',
    2,
    bounds.active_start + interval '2 hours',
    bounds.active_start + interval '8 hours'
from bounds;

create temporary table mission_read_before as
select
    (
        select points_student_balance
        from public.students
        where id = 'b3000000-0000-4000-8000-000000000001'
    ) as student_balance,
    (
        select points_class_balance
        from public.classes
        where id = 'b2000000-0000-4000-8000-000000000002'
    ) as class_balance,
    (select count(*) from public.mission_completions) as completions,
    (select count(*) from public.mission_reward_applications) as applications,
    (select count(*) from public.audit_logs) as audit_logs;

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'b9000000-0000-4000-8000-00000000ffff',
    true
);
set local role authenticated;
select extensions.is(
    (select count(*)::bigint from public.get_active_missions_v1()),
    0::bigint,
    'authenticated sem student vinculado recebe conjunto vazio'
);
reset role;

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'b9000000-0000-4000-8000-000000000003',
    true
);
set local role authenticated;
select extensions.is(
    (select count(*)::bigint from public.get_active_missions_v1()),
    0::bigint,
    'student INACTIVE recebe conjunto vazio'
);
reset role;

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'b9000000-0000-4000-8000-000000000001',
    true
);
set local role authenticated;

select extensions.is(
    (select count(*)::bigint from public.get_active_missions_v1()),
    3::bigint,
    'student ACTIVE com is_activated false recebe os tres ciclos ativos da escola'
);

select extensions.is(
    (
        select array_agg(definition_code)
        from public.get_active_missions_v1()
    ),
    array['A_STUDENT_ACTIVE', 'B_CLASS_ACTIVE', 'C_STUDENT_ACTIVE']::text[],
    'resultado exclui outra escola, futuro e encerrado e preserva ordenacao tecnica'
);

select extensions.ok(
    not exists (
        select 1
        from public.get_active_missions_v1()
        where not (starts_at <= pg_catalog.now() and pg_catalog.now() < ends_at)
    ),
    'somente ciclos ativos sao retornados'
);

select extensions.is(
    (
        select progress
        from public.get_active_missions_v1()
        where cycle_id = 'b6000000-0000-4000-8000-000000000001'
    ),
    3::bigint,
    'STUDENT conta somente descartes validos do proprio aluno dentro do periodo e pode ultrapassar target'
);

select extensions.ok(
    (
        select pg_typeof(progress) = 'bigint'::regtype
        from public.get_active_missions_v1()
        where cycle_id = 'b6000000-0000-4000-8000-000000000001'
    ),
    'progresso STUDENT usa bigint'
);

select extensions.ok(
    (
        select is_achieved
           and achieved_at = (
               date_trunc(
                   'month', pg_catalog.now() at time zone 'America/Sao_Paulo'
               ) at time zone 'America/Sao_Paulo'
           ) + interval '2 hours'
        from public.get_active_missions_v1()
        where cycle_id = 'b6000000-0000-4000-8000-000000000001'
    ),
    'achieved_at STUDENT e o created_at do deposito na posicao target'
);

select extensions.ok(
    (
        select is_completed
           and materialized_at = (
               date_trunc(
                   'month', pg_catalog.now() at time zone 'America/Sao_Paulo'
               ) at time zone 'America/Sao_Paulo'
           ) + interval '8 hours'
        from public.get_active_missions_v1()
        where cycle_id = 'b6000000-0000-4000-8000-000000000001'
    ),
    'completion STUDENT existente aparece com materialized_at persistido'
);

select extensions.ok(
    (
        select progress = 3
           and not is_achieved
           and achieved_at is null
           and not is_completed
           and materialized_at is null
        from public.get_active_missions_v1()
        where cycle_id = 'b6000000-0000-4000-8000-000000000003'
    ),
    'ciclo abaixo do target e sem completion permanece somente leitura e incompleto'
);

select extensions.ok(
    (
        select progress = 4000
           and is_achieved
           and achieved_at = (
               date_trunc(
                   'month', pg_catalog.now() at time zone 'America/Sao_Paulo'
               ) at time zone 'America/Sao_Paulo'
           ) + interval '5 hours'
           and not is_completed
        from public.get_active_missions_v1()
        where cycle_id = 'b6000000-0000-4000-8000-000000000002'
    ),
    'CLASS usa turma atual, soma snapshots em bigint e deriva primeiro cruzamento do target'
);

select extensions.ok(
    (
        select progress <> current_class.points_class_balance::bigint
        from public.get_active_missions_v1() as mission
        join public.classes as current_class
          on current_class.id = 'b2000000-0000-4000-8000-000000000002'
        where mission.cycle_id = 'b6000000-0000-4000-8000-000000000002'
    ),
    'CLASS nao usa points_class_balance'
);

select extensions.is(
    (
        select count(*)::bigint
        from public.deposits
        where id in (
            'b7000000-0000-4000-8000-000000000004',
            'b7000000-0000-4000-8000-000000000011',
            'b7000000-0000-4000-8000-000000000012'
        )
    ),
    0::bigint,
    'RLS nao expoe depositos brutos do colega apesar do agregado CLASS'
);

select extensions.results_eq(
    $$select * from public.get_active_missions_v1()$$,
    $$select * from public.get_active_missions_v1()$$,
    'chamadas repetidas retornam o mesmo resultado ordenado'
);

reset role;

select extensions.is(
    (
        select points_student_balance
        from public.students
        where id = 'b3000000-0000-4000-8000-000000000001'
    ),
    (select student_balance from mission_read_before),
    'RPC nao altera saldo do student'
);

select extensions.is(
    (
        select points_class_balance
        from public.classes
        where id = 'b2000000-0000-4000-8000-000000000002'
    ),
    (select class_balance from mission_read_before),
    'RPC nao altera saldo da class'
);

select extensions.is(
    (select count(*) from public.mission_completions),
    (select completions from mission_read_before),
    'RPC nao cria mission_completions'
);

select extensions.is(
    (select count(*) from public.mission_reward_applications),
    (select applications from mission_read_before),
    'RPC nao cria mission_reward_applications'
);

select extensions.is(
    (select count(*) from public.audit_logs),
    (select audit_logs from mission_read_before),
    'RPC nao cria audit_logs'
);

select extensions.ok(
    exists (
        select 1
        from pg_catalog.pg_policies
        where schemaname = 'public'
          and tablename = 'deposits'
          and policyname = 'deposits_select_own_history_v1'
          and cmd = 'SELECT'
          and roles = array['authenticated']::name[]
    )
    and not has_table_privilege(
        'authenticated', 'public.deposits', 'select'
    )
    and not has_column_privilege(
        'authenticated', 'public.deposits', 'class_id', 'select'
    ),
    'RLS e privilegios diretos de deposits permanecem restritos ao baseline'
);

select * from extensions.finish();
rollback;
