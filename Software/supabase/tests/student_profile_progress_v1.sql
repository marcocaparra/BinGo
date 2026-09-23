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
    to_regprocedure('public.get_student_profile_progress_v1()') is not null,
    'RPC de progresso do perfil sem parametros existe'
);

select extensions.ok(
    (
        select function_row.prosecdef
           and function_row.provolatile = 's'
           and function_row.proconfig = array['search_path=""']
           and function_row.pronargs = 0
        from pg_catalog.pg_proc as function_row
        where function_row.oid =
            'public.get_student_profile_progress_v1()'::regprocedure
    ),
    'RPC e STABLE, SECURITY DEFINER, sem parametros e com search_path vazio'
);

select extensions.is(
    pg_get_function_result(
        'public.get_student_profile_progress_v1()'::regprocedure
    ),
    'TABLE(student_id uuid, valid_deposit_count bigint, level_number integer, level_code text, remaining_to_next_level bigint, progress_to_next_level numeric)',
    'contrato da RPC possui exatamente os campos esperados'
);

select extensions.ok(
    not has_function_privilege(
        'anon', 'public.get_student_profile_progress_v1()', 'execute'
    )
    and has_function_privilege(
        'authenticated',
        'public.get_student_profile_progress_v1()',
        'execute'
    )
    and not has_function_privilege(
        'service_role',
        'public.get_student_profile_progress_v1()',
        'execute'
    ),
    'somente authenticated recebe EXECUTE na RPC'
);

select extensions.ok(
    pg_temp.raises_state(
        $$set local role anon; select * from public.get_student_profile_progress_v1()$$,
        '42501'
    ),
    'anon nao executa a RPC'
);

insert into public.schools (id, name)
values ('e1000000-0000-4000-8000-000000000001', 'Escola Trilha');

insert into public.classes (id, school_id, segment, grade, name)
values
    (
        'e2000000-0000-4000-8000-000000000001',
        'e1000000-0000-4000-8000-000000000001',
        'FUNDAMENTAL', '8', 'Turma atual'
    ),
    (
        'e2000000-0000-4000-8000-000000000002',
        'e1000000-0000-4000-8000-000000000001',
        'FUNDAMENTAL', '7', 'Turma anterior'
    );

insert into public.machines (id, school_id, name, status)
values (
    'e4000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000001',
    'Totem Trilha',
    'ONLINE'
);

insert into public.students (
    id, school_id, class_id, name, status, auth_user_id
)
values
    ('e3000000-0000-4000-8000-000000000000', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 0', 'ACTIVE', 'e9000000-0000-4000-8000-000000000000'),
    ('e3000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 1', 'ACTIVE', 'e9000000-0000-4000-8000-000000000001'),
    ('e3000000-0000-4000-8000-000000000004', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 4', 'ACTIVE', 'e9000000-0000-4000-8000-000000000004'),
    ('e3000000-0000-4000-8000-000000000005', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 5', 'ACTIVE', 'e9000000-0000-4000-8000-000000000005'),
    ('e3000000-0000-4000-8000-000000000009', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 9', 'ACTIVE', 'e9000000-0000-4000-8000-000000000009'),
    ('e3000000-0000-4000-8000-000000000010', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 10', 'ACTIVE', 'e9000000-0000-4000-8000-000000000010'),
    ('e3000000-0000-4000-8000-000000000019', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 19', 'ACTIVE', 'e9000000-0000-4000-8000-000000000019'),
    ('e3000000-0000-4000-8000-000000000020', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 20', 'ACTIVE', 'e9000000-0000-4000-8000-000000000020'),
    ('e3000000-0000-4000-8000-000000000049', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 49', 'ACTIVE', 'e9000000-0000-4000-8000-000000000049'),
    ('e3000000-0000-4000-8000-000000000050', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 50', 'ACTIVE', 'e9000000-0000-4000-8000-000000000050'),
    ('e3000000-0000-4000-8000-000000000073', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno 73', 'ACTIVE', 'e9000000-0000-4000-8000-000000000073'),
    ('e3000000-0000-4000-8000-000000000099', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'Aluno mudou de turma', 'ACTIVE', 'e9000000-0000-4000-8000-000000000099');

create function pg_temp.insert_valid_deposits(
    p_student_id uuid,
    p_class_id uuid,
    p_count integer
)
returns void
language sql
as $$
    insert into public.deposits (
        event_id,
        school_id,
        machine_id,
        class_id,
        student_id,
        is_valid,
        detected_type,
        points_awarded_student,
        points_awarded_class,
        waste_category_id,
        category_source,
        bonus_rate_applied,
        bonus_bincoins_awarded
    )
    select
        md5(p_student_id::text || ':' || item.number::text)::uuid,
        'e1000000-0000-4000-8000-000000000001'::uuid,
        'e4000000-0000-4000-8000-000000000001'::uuid,
        p_class_id,
        p_student_id,
        true,
        'fixture',
        0,
        0,
        (
            select category.id
            from public.waste_categories as category
            where category.code = 'UNKNOWN'
        ),
        'UNIDENTIFIED',
        0,
        0
    from generate_series(1, p_count) as item(number);
$$;

select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 1);
select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000004', 'e2000000-0000-4000-8000-000000000001', 4);
select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000005', 'e2000000-0000-4000-8000-000000000001', 5);
select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000009', 'e2000000-0000-4000-8000-000000000001', 9);
select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000010', 'e2000000-0000-4000-8000-000000000001', 10);
select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000019', 'e2000000-0000-4000-8000-000000000001', 19);
select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000020', 'e2000000-0000-4000-8000-000000000001', 20);
select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000049', 'e2000000-0000-4000-8000-000000000001', 49);
select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000050', 'e2000000-0000-4000-8000-000000000001', 50);
select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000073', 'e2000000-0000-4000-8000-000000000001', 73);
select pg_temp.insert_valid_deposits('e3000000-0000-4000-8000-000000000099', 'e2000000-0000-4000-8000-000000000002', 1);

-- Um descarte invalido ligado ao aluno zero nao conta.
insert into public.deposits (
    event_id, school_id, machine_id, class_id, student_id, is_valid,
    detected_type, points_awarded_student, points_awarded_class,
    bonus_rate_applied, bonus_bincoins_awarded
)
values (
    'e5000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000001',
    'e4000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    'e3000000-0000-4000-8000-000000000000',
    false, 'invalido', 0, 0, 0, 0
);

-- Um descarte valido anonimo na mesma turma nao conta para aluno algum.
insert into public.deposits (
    event_id, school_id, machine_id, class_id, student_id, is_valid,
    detected_type, points_awarded_student, points_awarded_class,
    waste_category_id, category_source, bonus_rate_applied,
    bonus_bincoins_awarded
)
select
    'e5000000-0000-4000-8000-000000000002',
    'e1000000-0000-4000-8000-000000000001',
    'e4000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    null,
    true,
    'anonimo',
    0,
    0,
    category.id,
    'UNIDENTIFIED',
    0,
    0
from public.waste_categories as category
where category.code = 'UNKNOWN';

create temporary table expected_profile_progress (
    auth_user_id uuid primary key,
    student_id uuid not null,
    valid_deposit_count bigint not null,
    level_number integer not null,
    level_code text not null,
    remaining_to_next_level bigint not null,
    progress_to_next_level numeric not null
);

insert into expected_profile_progress values
    ('e9000000-0000-4000-8000-000000000000', 'e3000000-0000-4000-8000-000000000000', 0, 0, 'NONE', 1, 0),
    ('e9000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000001', 1, 1, 'APPRENTICE', 4, 0.2),
    ('e9000000-0000-4000-8000-000000000004', 'e3000000-0000-4000-8000-000000000004', 4, 1, 'APPRENTICE', 1, 0.8),
    ('e9000000-0000-4000-8000-000000000005', 'e3000000-0000-4000-8000-000000000005', 5, 2, 'EXPLORER', 5, 0.5),
    ('e9000000-0000-4000-8000-000000000009', 'e3000000-0000-4000-8000-000000000009', 9, 2, 'EXPLORER', 1, 0.9),
    ('e9000000-0000-4000-8000-000000000010', 'e3000000-0000-4000-8000-000000000010', 10, 3, 'RESTORER', 10, 0.5),
    ('e9000000-0000-4000-8000-000000000019', 'e3000000-0000-4000-8000-000000000019', 19, 3, 'RESTORER', 1, 0.95),
    ('e9000000-0000-4000-8000-000000000020', 'e3000000-0000-4000-8000-000000000020', 20, 4, 'GUARDIAN', 30, 0.4),
    ('e9000000-0000-4000-8000-000000000049', 'e3000000-0000-4000-8000-000000000049', 49, 4, 'GUARDIAN', 1, 0.98),
    ('e9000000-0000-4000-8000-000000000050', 'e3000000-0000-4000-8000-000000000050', 50, 5, 'HERO', 0, 1),
    ('e9000000-0000-4000-8000-000000000073', 'e3000000-0000-4000-8000-000000000073', 73, 5, 'HERO', 0, 1),
    ('e9000000-0000-4000-8000-000000000099', 'e3000000-0000-4000-8000-000000000099', 1, 1, 'APPRENTICE', 4, 0.2);

create function pg_temp.assert_profile_progress(p_auth_user_id uuid)
returns text
language plpgsql
as $$
declare
    expected expected_profile_progress%rowtype;
begin
    select *
    into strict expected
    from expected_profile_progress
    where auth_user_id = p_auth_user_id;

    perform pg_catalog.set_config(
        'request.jwt.claim.sub', expected.auth_user_id::text, true
    );

    return extensions.results_eq(
        'select student_id, valid_deposit_count, level_number, level_code, remaining_to_next_level, progress_to_next_level from public.get_student_profile_progress_v1()',
        format(
            'values (%L::uuid, %s::bigint, %s::integer, %L::text, %s::bigint, %L::numeric)',
            expected.student_id,
            expected.valid_deposit_count,
            expected.level_number,
            expected.level_code,
            expected.remaining_to_next_level,
            expected.progress_to_next_level
        ),
        format(
            '%s descartes retorna nivel, restante e progresso corretos',
            expected.valid_deposit_count
        )
    );
end;
$$;

select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000000');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000001');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000004');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000005');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000009');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000010');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000019');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000020');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000049');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000050');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000073');
select pg_temp.assert_profile_progress('e9000000-0000-4000-8000-000000000099');

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'e9000000-0000-4000-8000-00000000ffff',
    true
);
set local role authenticated;
select extensions.is(
    (select count(*)::bigint from public.get_student_profile_progress_v1()),
    0::bigint,
    'Auth sem student vinculado recebe zero registros'
);
reset role;

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'e9000000-0000-4000-8000-000000000001',
    true
);
set local role authenticated;
select extensions.results_eq(
    $$
        select student_id, valid_deposit_count
        from public.get_student_profile_progress_v1()
    $$,
    $$
        values (
            'e3000000-0000-4000-8000-000000000001'::uuid,
            1::bigint
        )
    $$,
    'authenticated recebe somente o progresso do proprio contexto'
);
reset role;

select extensions.ok(
    not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'deposits'
          and policyname <> 'deposits_select_own_history_v1'
    ),
    'Trilha nao amplia a RLS geral de deposits'
);

select extensions.ok(
    exists (
        select 1
        from pg_indexes
        where schemaname = 'public'
          and tablename = 'deposits'
          and indexname = 'idx_deposits_student_created_at'
    ),
    'indice existente por student_id permanece disponivel sem novo indice'
);

select * from extensions.finish();
rollback;
