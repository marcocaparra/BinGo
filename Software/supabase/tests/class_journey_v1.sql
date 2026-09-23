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

select extensions.has_table(
    'public', 'journey_campaigns', 'dominio possui campanhas proprias'
);
select extensions.has_table(
    'public', 'journey_stages', 'dominio possui estagios proprios'
);
select extensions.has_table(
    'public', 'journey_mission_contributions',
    'dominio possui ledger de completions'
);
select extensions.ok(
    (
        select bool_and(class_row.relrowsecurity)
        from pg_catalog.pg_class as class_row
        where class_row.oid in (
            'public.journey_campaigns'::regclass,
            'public.journey_stages'::regclass,
            'public.journey_mission_contributions'::regclass
        )
    ),
    'novas tabelas possuem RLS estrutural'
);
select extensions.ok(
    not has_table_privilege('anon', 'public.journey_campaigns', 'select')
    and not has_table_privilege(
        'authenticated', 'public.journey_campaigns', 'select'
    )
    and not has_table_privilege(
        'service_role', 'public.journey_campaigns', 'select'
    ),
    'tabelas da Jornada nao expoem acesso direto'
);
select extensions.ok(
    (
        select procedure.prosecdef
           and procedure.provolatile = 's'
           and procedure.proconfig = array['search_path=""']
           and procedure.pronargs = 0
        from pg_catalog.pg_proc as procedure
        where procedure.oid = 'public.get_class_journey_v1()'::regprocedure
    ),
    'RPC e STABLE, SECURITY DEFINER, sem parametros e com search_path vazio'
);
select extensions.ok(
    not has_function_privilege(
        'anon', 'public.get_class_journey_v1()', 'execute'
    )
    and has_function_privilege(
        'authenticated', 'public.get_class_journey_v1()', 'execute'
    )
    and not has_function_privilege(
        'service_role', 'public.get_class_journey_v1()', 'execute'
    ),
    'somente authenticated executa a RPC da Jornada'
);
select extensions.ok(
    pg_temp.raises_state(
        $$set local role anon; select * from public.get_class_journey_v1()$$,
        '42501'
    ),
    'anon nao executa a RPC'
);

insert into public.schools (id, name)
values
    ('a1100000-0000-4000-8000-000000000001', 'Escola Jornada'),
    ('a1100000-0000-4000-8000-000000000002', 'Escola Isolada'),
    ('a1100000-0000-4000-8000-000000000003', 'Escola Backfill');

insert into public.school_settings (school_id)
values
    ('a1100000-0000-4000-8000-000000000001'),
    ('a1100000-0000-4000-8000-000000000003');

insert into public.classes (id, school_id, segment, grade, name)
select
    ('a1200000-0000-4000-8000-' || lpad(number::text, 12, '0'))::uuid,
    'a1100000-0000-4000-8000-000000000001',
    'TESTE',
    number::text,
    'Turma ' || number::text
from generate_series(0, 15) as fixture(number);

insert into public.classes (id, school_id, segment, grade, name)
values
    (
        'a1200000-0000-4000-8000-000000000099',
        'a1100000-0000-4000-8000-000000000002',
        'TESTE', 'X', 'Outra escola'
    ),
    (
        'a1200000-0000-4000-8000-000000000100',
        'a1100000-0000-4000-8000-000000000003',
        'TESTE', 'B', 'Backfill'
    );

insert into public.machines (id, school_id, name, status)
values
    (
        'a1400000-0000-4000-8000-000000000001',
        'a1100000-0000-4000-8000-000000000001',
        'Totem Jornada', 'ONLINE'
    ),
    (
        'a1400000-0000-4000-8000-000000000003',
        'a1100000-0000-4000-8000-000000000003',
        'Totem Backfill', 'ONLINE'
    );

insert into public.students (
    id, school_id, class_id, name, status, auth_user_id
)
select
    ('a1300000-0000-4000-8000-' || lpad(number::text, 12, '0'))::uuid,
    'a1100000-0000-4000-8000-000000000001',
    ('a1200000-0000-4000-8000-' || lpad(number::text, 12, '0'))::uuid,
    'Aluno ' || number::text,
    'ACTIVE',
    ('a1900000-0000-4000-8000-' || lpad(number::text, 12, '0'))::uuid
from generate_series(0, 15) as fixture(number);

insert into public.students (
    id, school_id, class_id, name, status, auth_user_id
)
values (
    'a1300000-0000-4000-8000-000000000100',
    'a1100000-0000-4000-8000-000000000003',
    'a1200000-0000-4000-8000-000000000100',
    'Aluno Backfill', 'ACTIVE',
    'a1900000-0000-4000-8000-000000000100'
);

insert into public.journey_campaigns (
    id, school_id, starts_at, ends_at, timezone,
    discard_units, student_mission_units, class_mission_units
)
values (
    'a1600000-0000-4000-8000-000000000001',
    'a1100000-0000-4000-8000-000000000001',
    '2026-07-01 00:00:00 America/Sao_Paulo',
    '2027-01-01 00:00:00 America/Sao_Paulo',
    'America/Sao_Paulo', 1, 3, 5
);

insert into public.journey_stages (
    campaign_id, stage_code, stage_order, target_units
)
values
    ('a1600000-0000-4000-8000-000000000001', 'CENTRAL_SQUARE', 1, 20),
    ('a1600000-0000-4000-8000-000000000001', 'SPRING_PARK', 2, 25),
    ('a1600000-0000-4000-8000-000000000001', 'CREATIVE_SCHOOL', 3, 30);

create function pg_temp.insert_class_deposits(
    p_class_number integer,
    p_count integer
)
returns void
language sql
as $$
    insert into public.deposits (
        event_id, school_id, machine_id, class_id, student_id, is_valid,
        detected_type, points_awarded_student, points_awarded_class,
        waste_category_id, category_source, bonus_rate_applied,
        bonus_bincoins_awarded, created_at
    )
    select
        md5('journey:' || p_class_number::text || ':' || item.number::text)::uuid,
        'a1100000-0000-4000-8000-000000000001'::uuid,
        'a1400000-0000-4000-8000-000000000001'::uuid,
        ('a1200000-0000-4000-8000-' || lpad(p_class_number::text, 12, '0'))::uuid,
        null,
        true,
        'fixture', 0, 0,
        (
            select category.id
            from public.waste_categories as category
            where category.code = 'UNKNOWN'
        ),
        'UNIDENTIFIED', 0, 0,
        '2026-09-10 12:00:00+00'::timestamptz
            + item.number * interval '1 second'
    from generate_series(1, p_count) as item(number);
$$;

select pg_temp.insert_class_deposits(1, 19);
select pg_temp.insert_class_deposits(2, 20);
select pg_temp.insert_class_deposits(3, 21);
select pg_temp.insert_class_deposits(4, 44);
select pg_temp.insert_class_deposits(5, 45);
select pg_temp.insert_class_deposits(6, 74);
select pg_temp.insert_class_deposits(7, 75);
select pg_temp.insert_class_deposits(8, 80);

-- Invalido, fora do semestre e de outra turma nao contam para a turma zero.
insert into public.deposits (
    event_id, school_id, machine_id, class_id, student_id, is_valid,
    detected_type, points_awarded_student, points_awarded_class,
    waste_category_id, category_source,
    bonus_rate_applied, bonus_bincoins_awarded, created_at
)
values
    (
        'a1700000-0000-4000-8000-000000000001',
        'a1100000-0000-4000-8000-000000000001',
        'a1400000-0000-4000-8000-000000000001',
        'a1200000-0000-4000-8000-000000000000', null, false,
        'invalido', 0, 0, null, null, 0, 0,
        '2026-09-10 12:00:00+00'
    ),
    (
        'a1700000-0000-4000-8000-000000000002',
        'a1100000-0000-4000-8000-000000000001',
        'a1400000-0000-4000-8000-000000000001',
        'a1200000-0000-4000-8000-000000000000', null, true,
        'fora', 0, 0,
        (
            select category.id
            from public.waste_categories as category
            where category.code = 'UNKNOWN'
        ),
        'UNIDENTIFIED', 0, 0, '2026-07-01 02:59:59+00'
    );

create temporary table expected_journey (
    class_number integer primary key,
    total_units bigint not null,
    stage_code text not null,
    progress_units bigint not null,
    state text not null,
    progress_ratio numeric not null
);

insert into expected_journey values
    (0, 0, 'CENTRAL_SQUARE', 0, 'ACTIVE', 0),
    (1, 19, 'CENTRAL_SQUARE', 19, 'ACTIVE', 0.95),
    (2, 20, 'SPRING_PARK', 0, 'ACTIVE', 0),
    (3, 21, 'SPRING_PARK', 1, 'ACTIVE', 0.04),
    (4, 44, 'SPRING_PARK', 24, 'ACTIVE', 0.96),
    (5, 45, 'CREATIVE_SCHOOL', 0, 'ACTIVE', 0),
    (6, 74, 'CREATIVE_SCHOOL', 29, 'ACTIVE', 29::numeric / 30),
    (7, 75, 'CREATIVE_SCHOOL', 30, 'COMPLETED', 1),
    (8, 80, 'CREATIVE_SCHOOL', 30, 'COMPLETED', 1);

create function pg_temp.assert_journey(p_class_number integer)
returns text
language plpgsql
as $$
declare
    expected expected_journey%rowtype;
begin
    select * into strict expected
    from expected_journey
    where class_number = p_class_number;

    perform pg_catalog.set_config(
        'request.jwt.claim.sub',
        ('a1900000-0000-4000-8000-'
            || lpad(p_class_number::text, 12, '0'))::uuid::text,
        true
    );

    return extensions.results_eq(
        format(
            $query$
                select
                    total_units,
                    stage_code,
                    progress_units,
                    state,
                    progress_ratio,
                    valid_deposit_count
                from public.get_class_journey_v1()
                where state = %L
                   or (stage_code = 'CREATIVE_SCHOOL' and %L = 'COMPLETED')
                order by stage_order desc
                limit 1
            $query$,
            expected.state,
            expected.state
        ),
        format(
            'values (%s::bigint, %L::text, %s::bigint, %L::text, %L::numeric, %s::bigint)',
            expected.total_units,
            expected.stage_code,
            expected.progress_units,
            expected.state,
            expected.progress_ratio,
            expected.total_units
        ),
        format('total %s respeita carry-over e estado V1', expected.total_units)
    );
end;
$$;

select pg_temp.assert_journey(0);
select pg_temp.assert_journey(1);
select pg_temp.assert_journey(2);
select pg_temp.assert_journey(3);
select pg_temp.assert_journey(4);
select pg_temp.assert_journey(5);
select pg_temp.assert_journey(6);
select pg_temp.assert_journey(7);
select pg_temp.assert_journey(8);

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'a1900000-0000-4000-8000-000000000008',
    true
);
select extensions.is(
    (select count(*)::bigint from public.get_class_journey_v1()),
    3::bigint,
    'excedente acima de 75 nao cria quarto estagio'
);

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'a1900000-0000-4000-8000-00000000ffff',
    true
);
set local role authenticated;
select extensions.is(
    (select count(*)::bigint from public.get_class_journey_v1()),
    0::bigint,
    'conta sem aluno vinculado recebe zero linhas'
);
reset role;

-- Missoes de transferencia: target 2 com XP economico.
insert into public.mission_definitions (
    id, code, title, scope, metric, recurrence, target,
    reward_bincoins, reward_xp
)
values
    (
        'a1500000-0000-4000-8000-000000000001',
        'JOURNEY_TRANSFER', 'Transferencia', 'STUDENT',
        'VALID_DEPOSIT_COUNT', 'MONTHLY', 2, 0, 7
    ),
    (
        'a1500000-0000-4000-8000-000000000002',
        'JOURNEY_MIXED', 'Mudanca antes da meta', 'STUDENT',
        'VALID_DEPOSIT_COUNT', 'MONTHLY', 2, 1, 0
    ),
    (
        'a1500000-0000-4000-8000-000000000003',
        'JOURNEY_CLASS', 'Coletiva', 'CLASS',
        'CLASS_XP_EARNED', 'MONTHLY', 1, 0, 1
    ),
    (
        'a1500000-0000-4000-8000-000000000100',
        'JOURNEY_BACKFILL', 'Backfill', 'STUDENT',
        'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 1, 0
    );

insert into public.mission_cycles (
    id, definition_id, school_id, starts_at, ends_at, timezone,
    scope, metric, recurrence, target, reward_bincoins, reward_xp
)
values
    (
        'a1510000-0000-4000-8000-000000000001',
        'a1500000-0000-4000-8000-000000000001',
        'a1100000-0000-4000-8000-000000000001',
        '2026-09-01 00:00:00 America/Sao_Paulo',
        '2026-10-01 00:00:00 America/Sao_Paulo',
        'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY',
        2, 0, 7
    ),
    (
        'a1510000-0000-4000-8000-000000000002',
        'a1500000-0000-4000-8000-000000000002',
        'a1100000-0000-4000-8000-000000000001',
        '2026-08-01 00:00:00 America/Sao_Paulo',
        '2026-09-01 00:00:00 America/Sao_Paulo',
        'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY',
        2, 1, 0
    ),
    (
        'a1510000-0000-4000-8000-000000000003',
        'a1500000-0000-4000-8000-000000000003',
        'a1100000-0000-4000-8000-000000000001',
        '2026-08-01 00:00:00 America/Sao_Paulo',
        '2026-09-01 00:00:00 America/Sao_Paulo',
        'America/Sao_Paulo', 'CLASS', 'CLASS_XP_EARNED', 'MONTHLY',
        1, 0, 1
    ),
    (
        'a1510000-0000-4000-8000-000000000100',
        'a1500000-0000-4000-8000-000000000100',
        'a1100000-0000-4000-8000-000000000003',
        '2026-09-01 00:00:00 America/Sao_Paulo',
        '2026-10-01 00:00:00 America/Sao_Paulo',
        'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY',
        1, 1, 0
    );

-- Aluno 10 atinge target na turma A, muda para B antes do processamento.
update public.students
set class_id = 'a1200000-0000-4000-8000-000000000010'
where id = 'a1300000-0000-4000-8000-000000000010';

select * from public.register_deposit_v1(
    'a1700000-0000-4000-8000-000000000010',
    'a1400000-0000-4000-8000-000000000001',
    'a1200000-0000-4000-8000-000000000010', true,
    'a1300000-0000-4000-8000-000000000010',
    'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
select * from public.register_deposit_v1(
    'a1700000-0000-4000-8000-000000000011',
    'a1400000-0000-4000-8000-000000000001',
    'a1200000-0000-4000-8000-000000000010', true,
    'a1300000-0000-4000-8000-000000000010',
    'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
update public.deposits
set created_at = case event_id
    when 'a1700000-0000-4000-8000-000000000010'::uuid
        then '2026-09-20 12:00:00+00'::timestamptz
    when 'a1700000-0000-4000-8000-000000000011'::uuid
        then '2026-09-20 12:00:01+00'::timestamptz
end
where event_id in (
    'a1700000-0000-4000-8000-000000000010',
    'a1700000-0000-4000-8000-000000000011'
);
update public.students
set class_id = 'a1200000-0000-4000-8000-000000000011'
where id = 'a1300000-0000-4000-8000-000000000010';
select * from public.process_mission_event_v1(
    'a1700000-0000-4000-8000-000000000011'
);

select extensions.ok(
    exists (
        select 1
        from public.journey_mission_contributions as contribution
        join public.mission_completions as completion
          on completion.id = contribution.mission_completion_id
        where completion.cycle_id = 'a1510000-0000-4000-8000-000000000001'
          and contribution.class_id = 'a1200000-0000-4000-8000-000000000010'
          and contribution.units_applied = 3
          and contribution.achievement_deposit_id = (
              select deposit.id
              from public.deposits as deposit
              where deposit.event_id = 'a1700000-0000-4000-8000-000000000011'
          )
    ),
    'Jornada STUDENT permanece na turma do deposito que atingiu o target'
);
select extensions.ok(
    exists (
        select 1
        from public.mission_reward_applications as application
        join public.mission_completions as completion
          on completion.id = application.completion_id
        where completion.cycle_id = 'a1510000-0000-4000-8000-000000000001'
          and application.reward_type = 'XP'
          and application.recipient_class_id = 'a1200000-0000-4000-8000-000000000011'
    ),
    'economia STUDENT continua enviando XP para turma atual na materializacao'
);
select extensions.is(
    (
        select count(*)::integer
        from public.journey_mission_contributions as contribution
        join public.mission_completions as completion
          on completion.id = contribution.mission_completion_id
        where completion.cycle_id = 'a1510000-0000-4000-8000-000000000001'
    ),
    1,
    'uma completion gera uma unica contribuicao'
);
select extensions.ok(
    pg_temp.raises_state(
        $$update public.journey_mission_contributions
          set units_applied = units_applied + 1
          where mission_completion_id = (
              select completion.id
              from public.mission_completions as completion
              where completion.cycle_id =
                  'a1510000-0000-4000-8000-000000000001'
              limit 1
          )$$,
        '55000'
    ),
    'ledger da Jornada rejeita mutacao de contribuicao materializada'
);

select * from public.register_deposit_v1(
    'a1700000-0000-4000-8000-000000000011',
    'a1400000-0000-4000-8000-000000000001',
    'a1200000-0000-4000-8000-000000000010', true,
    'a1300000-0000-4000-8000-000000000010',
    'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
select * from public.process_mission_event_v1(
    'a1700000-0000-4000-8000-000000000011'
);
select extensions.is(
    (
        select count(*)::integer
        from public.journey_mission_contributions as contribution
        join public.mission_completions as completion
          on completion.id = contribution.mission_completion_id
        where completion.cycle_id = 'a1510000-0000-4000-8000-000000000001'
    ),
    1,
    'retry do descarte e processamento nao duplica Jornada'
);

select extensions.is(
    (
        select
            (
                select count(*)::integer
                from public.deposits as deposit
                where deposit.class_id =
                    'a1200000-0000-4000-8000-000000000010'
                  and deposit.is_valid
            )
            +
            (
                select coalesce(sum(contribution.units_applied), 0)::integer
                from public.journey_mission_contributions as contribution
                where contribution.campaign_id =
                    'a1600000-0000-4000-8000-000000000001'
                  and contribution.class_id =
                    'a1200000-0000-4000-8000-000000000010'
                  and contribution.completion_scope = 'STUDENT'
            )
    ),
    5,
    'descarte mais completion STUDENT acumulam efeitos 1 mais 3'
);

-- O target 2 ocorre em B; mudanca posterior para C nao move o ledger.
insert into public.deposits (
    event_id, school_id, machine_id, class_id, student_id, is_valid,
    detected_type, points_awarded_student, points_awarded_class,
    waste_category_id, category_source, bonus_rate_applied,
    bonus_bincoins_awarded, created_at
)
select
    source.event_id,
    'a1100000-0000-4000-8000-000000000001',
    'a1400000-0000-4000-8000-000000000001',
    source.class_id,
    'a1300000-0000-4000-8000-000000000012',
    true, 'fixture', 0, 0, category.id, 'UNIDENTIFIED', 0, 0,
    source.created_at
from public.waste_categories as category
cross join (
    values
        (
            'a1700000-0000-4000-8000-000000000020'::uuid,
            'a1200000-0000-4000-8000-000000000012'::uuid,
            '2026-08-10 12:00:00+00'::timestamptz
        ),
        (
            'a1700000-0000-4000-8000-000000000021'::uuid,
            'a1200000-0000-4000-8000-000000000013'::uuid,
            '2026-08-11 12:00:00+00'::timestamptz
        )
) as source(event_id, class_id, created_at)
where category.code = 'UNKNOWN';

insert into public.mission_completions (
    id, cycle_id, participant_scope, student_id,
    progress_at_completion, achieved_at, materialized_at
)
values (
    'a1520000-0000-4000-8000-000000000002',
    'a1510000-0000-4000-8000-000000000002',
    'STUDENT', 'a1300000-0000-4000-8000-000000000012',
    2, '2026-08-11 12:00:00+00', '2026-09-02 12:00:00+00'
);
update public.students
set class_id = 'a1200000-0000-4000-8000-000000000014'
where id = 'a1300000-0000-4000-8000-000000000012';

select extensions.ok(
    exists (
        select 1
        from public.journey_mission_contributions
        where mission_completion_id = 'a1520000-0000-4000-8000-000000000002'
          and class_id = 'a1200000-0000-4000-8000-000000000013'
          and units_applied = 3
    ),
    'target realizado em B atribui +3 a B e mudanca posterior nao move ledger'
);

insert into public.mission_completions (
    id, cycle_id, participant_scope, class_id,
    progress_at_completion, achieved_at, materialized_at
)
values (
    'a1520000-0000-4000-8000-000000000003',
    'a1510000-0000-4000-8000-000000000003',
    'CLASS', 'a1200000-0000-4000-8000-000000000015',
    1, '2026-08-12 12:00:00+00', '2026-08-12 12:01:00+00'
);
select extensions.ok(
    exists (
        select 1
        from public.journey_mission_contributions
        where mission_completion_id = 'a1520000-0000-4000-8000-000000000003'
          and class_id = 'a1200000-0000-4000-8000-000000000015'
          and completion_scope = 'CLASS'
          and units_applied = 5
          and achievement_deposit_id is null
    ),
    'completion CLASS aplica +5 para a propria class_id'
);

-- Backfill: completion preexistente sem campanha, depois campanha provisionada.
insert into public.deposits (
    event_id, school_id, machine_id, class_id, student_id, is_valid,
    detected_type, points_awarded_student, points_awarded_class,
    waste_category_id, category_source, bonus_rate_applied,
    bonus_bincoins_awarded, created_at
)
select
    'a1700000-0000-4000-8000-000000000100',
    'a1100000-0000-4000-8000-000000000003',
    'a1400000-0000-4000-8000-000000000003',
    'a1200000-0000-4000-8000-000000000100',
    'a1300000-0000-4000-8000-000000000100',
    true, 'fixture', 0, 0, category.id, 'UNIDENTIFIED', 0, 0,
    '2026-09-18 21:51:56.301564+00'
from public.waste_categories as category
where category.code = 'UNKNOWN';

insert into public.mission_completions (
    id, cycle_id, participant_scope, student_id,
    progress_at_completion, achieved_at, materialized_at
)
values (
    'a1520000-0000-4000-8000-000000000100',
    'a1510000-0000-4000-8000-000000000100',
    'STUDENT', 'a1300000-0000-4000-8000-000000000100',
    1,
    '2026-09-18 21:51:56.301564+00',
    '2026-09-18 21:52:00.619989+00'
);

insert into public.journey_campaigns (
    id, school_id, starts_at, ends_at, timezone,
    discard_units, student_mission_units, class_mission_units
)
values (
    'a1600000-0000-4000-8000-000000000100',
    'a1100000-0000-4000-8000-000000000003',
    '2026-07-01 00:00:00 America/Sao_Paulo',
    '2027-01-01 00:00:00 America/Sao_Paulo',
    'America/Sao_Paulo', 1, 3, 5
);

select extensions.is(
    public.backfill_journey_campaign_v1(
        'a1600000-0000-4000-8000-000000000100'
    ),
    1,
    'backfill local reconstrui e insere a completion historica'
);
select extensions.is(
    public.backfill_journey_campaign_v1(
        'a1600000-0000-4000-8000-000000000100'
    ),
    0,
    'backfill local e idempotente'
);
select extensions.ok(
    exists (
        select 1
        from public.journey_mission_contributions as contribution
        join public.deposits as deposit
          on deposit.id = contribution.achievement_deposit_id
        where contribution.mission_completion_id =
            'a1520000-0000-4000-8000-000000000100'
          and contribution.class_id =
            'a1200000-0000-4000-8000-000000000100'
          and deposit.event_id =
            'a1700000-0000-4000-8000-000000000100'
          and deposit.created_at = contribution.contributed_at
    ),
    'backfill fotografa deposit id, event id, class id e achieved_at exatos'
);

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'a1900000-0000-4000-8000-000000000000',
    true
);
set local role authenticated;
select extensions.ok(
    not exists (
        select 1
        from public.get_class_journey_v1()
        where total_units <> 0
    ),
    'outra turma e outra escola nao sao expostas ao contexto autenticado'
);
reset role;

select * from extensions.finish();
rollback;
