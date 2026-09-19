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
    to_regprocedure('public.get_class_ranking_v1()') is not null,
    'RPC get_class_ranking_v1 sem parametros existe'
);

select extensions.ok(
    (
        select function_row.prosecdef
           and function_row.provolatile = 's'
           and function_row.proconfig = array['search_path=""']
           and function_row.pronargs = 0
        from pg_catalog.pg_proc as function_row
        where function_row.oid = 'public.get_class_ranking_v1()'::regprocedure
    ),
    'RPC e STABLE, SECURITY DEFINER, sem parametros e possui search_path vazio'
);

select extensions.ok(
    not has_function_privilege(
        'anon', 'public.get_class_ranking_v1()', 'execute'
    )
    and has_function_privilege(
        'authenticated', 'public.get_class_ranking_v1()', 'execute'
    )
    and not has_function_privilege(
        'service_role', 'public.get_class_ranking_v1()', 'execute'
    ),
    'somente authenticated recebe EXECUTE na RPC'
);

select extensions.ok(
    pg_temp.raises_state(
        $$set local role anon; select * from public.get_class_ranking_v1()$$,
        '42501'
    ),
    'anon nao executa a leitura privada'
);

select extensions.ok(
    pg_get_function_result('public.get_class_ranking_v1()'::regprocedure)
        = 'TABLE(class_id uuid, class_name text, points_class_balance integer)',
    'contrato retorna somente id, nome e saldo atual da turma'
);

insert into public.schools (id, name)
values
    ('d1000000-0000-4000-8000-000000000001', 'Escola Ranking A'),
    ('d1000000-0000-4000-8000-000000000002', 'Escola Ranking B');

insert into public.classes (
    id, school_id, segment, grade, name, points_class_balance
)
values
    (
        'd2000000-0000-4000-8000-000000000001',
        'd1000000-0000-4000-8000-000000000001',
        'FUNDAMENTAL', '7', '7º A', 9000
    ),
    (
        'd2000000-0000-4000-8000-000000000002',
        'd1000000-0000-4000-8000-000000000001',
        'FUNDAMENTAL', '8', '8º B', 5000
    ),
    (
        'd2000000-0000-4000-8000-000000000003',
        'd1000000-0000-4000-8000-000000000001',
        'FUNDAMENTAL', '6', '6º C', 9000
    ),
    (
        'd2000000-0000-4000-8000-000000000004',
        'd1000000-0000-4000-8000-000000000001',
        'FUNDAMENTAL', '9', '9º D', 0
    ),
    (
        'd2000000-0000-4000-8000-000000000005',
        'd1000000-0000-4000-8000-000000000002',
        'FUNDAMENTAL', '9', 'Outra escola', 999999
    );

insert into public.students (
    id, school_id, class_id, name, is_activated,
    points_student_balance, status, auth_user_id
)
values
    (
        'd3000000-0000-4000-8000-000000000001',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000002',
        'Aluno Ranking', true, 0, 'ACTIVE',
        'd9000000-0000-4000-8000-000000000001'
    ),
    (
        'd3000000-0000-4000-8000-000000000002',
        'd1000000-0000-4000-8000-000000000002',
        'd2000000-0000-4000-8000-000000000005',
        'Aluno outra escola', true, 0, 'ACTIVE',
        'd9000000-0000-4000-8000-000000000002'
    ),
    (
        'd3000000-0000-4000-8000-000000000003',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000005',
        'Aluno com vinculo inconsistente', true, 0, 'ACTIVE',
        'd9000000-0000-4000-8000-000000000003'
    );

create temporary table class_ranking_before as
select
    (select count(*) from public.classes) as class_count,
    (select sum(points_class_balance) from public.classes) as class_balance,
    (select count(*) from public.students) as student_count;

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'd9000000-0000-4000-8000-00000000ffff',
    true
);
set local role authenticated;
select extensions.is(
    (select count(*)::bigint from public.get_class_ranking_v1()),
    0::bigint,
    'authenticated sem student vinculado recebe conjunto vazio'
);
reset role;

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'd9000000-0000-4000-8000-000000000003',
    true
);
set local role authenticated;
select extensions.is(
    (select count(*)::bigint from public.get_class_ranking_v1()),
    0::bigint,
    'vinculo inconsistente entre student, class e school nao recebe ranking'
);
reset role;

select pg_catalog.set_config(
    'request.jwt.claim.sub',
    'd9000000-0000-4000-8000-000000000001',
    true
);
set local role authenticated;

select extensions.results_eq(
    $$
        select class_id, class_name, points_class_balance
        from public.get_class_ranking_v1()
    $$,
    $$
        values
            ('d2000000-0000-4000-8000-000000000001'::uuid, '7º A'::text, 9000),
            ('d2000000-0000-4000-8000-000000000003'::uuid, '6º C'::text, 9000),
            ('d2000000-0000-4000-8000-000000000002'::uuid, '8º B'::text, 5000),
            ('d2000000-0000-4000-8000-000000000004'::uuid, '9º D'::text, 0)
    $$,
    'retorna somente a escola do aluno, ordena saldo desc e desempata por UUID'
);

select extensions.ok(
    not exists (
        select 1
        from public.get_class_ranking_v1()
        where class_name = 'Outra escola'
    ),
    'turma de outra escola nunca aparece'
);

select extensions.is(
    (
        select points_class_balance
        from public.get_class_ranking_v1()
        where class_id = 'd2000000-0000-4000-8000-000000000004'
    ),
    0,
    'saldo zero e retornado como zero'
);

reset role;

select extensions.is(
    (select count(*) from public.classes),
    (select class_count from class_ranking_before),
    'RPC nao cria nem remove turmas'
);

select extensions.is(
    (select sum(points_class_balance) from public.classes),
    (select class_balance from class_ranking_before),
    'RPC nao altera saldos das turmas'
);

select extensions.is(
    (select count(*) from public.students),
    (select student_count from class_ranking_before),
    'RPC nao altera students'
);

select extensions.ok(
    not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'classes'
          and policyname <> 'classes_select_own_v1'
    ),
    'Ranking nao amplia as policies globais de classes'
);

select * from extensions.finish();
rollback;
