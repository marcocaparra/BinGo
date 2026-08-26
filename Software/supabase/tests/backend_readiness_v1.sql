begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(11);

select extensions.ok(
    to_regprocedure('public.check_backend_readiness_v1()') is not null,
    'check_backend_readiness_v1 existe sem argumentos'
);

select extensions.ok(
    (
        select p.prorettype = 'boolean'::regtype
        from pg_catalog.pg_proc p
        where p.oid = 'public.check_backend_readiness_v1()'::regprocedure
    ),
    'check_backend_readiness_v1 retorna boolean'
);

select extensions.ok(
    (
        select p.provolatile = 's'
        from pg_catalog.pg_proc p
        where p.oid = 'public.check_backend_readiness_v1()'::regprocedure
    ),
    'check_backend_readiness_v1 e STABLE'
);

select extensions.ok(
    (
        select not p.prosecdef
        from pg_catalog.pg_proc p
        where p.oid = 'public.check_backend_readiness_v1()'::regprocedure
    ),
    'check_backend_readiness_v1 usa SECURITY INVOKER'
);

select extensions.is(
    (
        select p.proconfig
        from pg_catalog.pg_proc p
        where p.oid = 'public.check_backend_readiness_v1()'::regprocedure
    ),
    array['search_path=""']::text[],
    'check_backend_readiness_v1 possui search_path vazio'
);

select extensions.ok(
    not exists (
        select 1
        from pg_catalog.pg_proc p
        cross join lateral pg_catalog.aclexplode(
            coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
        ) acl
        where p.oid = 'public.check_backend_readiness_v1()'::regprocedure
          and acl.grantee = 0
          and acl.privilege_type = 'EXECUTE'
    ),
    'PUBLIC nao pode executar check_backend_readiness_v1'
);

select extensions.ok(
    not has_function_privilege(
        'anon',
        'public.check_backend_readiness_v1()',
        'execute'
    ),
    'anon nao pode executar check_backend_readiness_v1'
);

select extensions.ok(
    not has_function_privilege(
        'authenticated',
        'public.check_backend_readiness_v1()',
        'execute'
    ),
    'authenticated nao pode executar check_backend_readiness_v1'
);

select extensions.ok(
    has_function_privilege(
        'service_role',
        'public.check_backend_readiness_v1()',
        'execute'
    ),
    'service_role pode executar check_backend_readiness_v1'
);

select extensions.is(
    public.check_backend_readiness_v1(),
    true,
    'PostgreSQL primario e gravavel e reportado como pronto'
);

set local default_transaction_read_only = on;

select extensions.is(
    public.check_backend_readiness_v1(),
    false,
    'servidor configurado como somente leitura e reportado como indisponivel'
);

select * from extensions.finish();
rollback;
