begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(13);

select extensions.ok(
    has_column_privilege('service_role', 'public.machines', 'id', 'select'),
    'service_role pode selecionar machines.id'
);

select extensions.ok(
    has_column_privilege('service_role', 'public.machines', 'school_id', 'select'),
    'service_role pode selecionar machines.school_id'
);

select extensions.ok(
    has_column_privilege('service_role', 'public.machines', 'api_key_hash', 'select'),
    'service_role pode selecionar machines.api_key_hash'
);

select extensions.ok(
    not has_table_privilege('service_role', 'public.machines', 'select'),
    'service_role nao recebe SELECT amplo na tabela machines'
);

select extensions.ok(
    not has_column_privilege('service_role', 'public.machines', 'name', 'select'),
    'service_role nao pode selecionar coluna nao concedida'
);

select extensions.ok(
    not has_table_privilege('service_role', 'public.machines', 'insert'),
    'service_role nao pode inserir em machines'
);

select extensions.ok(
    not has_table_privilege('service_role', 'public.machines', 'update'),
    'service_role nao pode atualizar machines'
);

select extensions.ok(
    not has_table_privilege('service_role', 'public.machines', 'delete'),
    'service_role nao pode excluir de machines'
);

select extensions.ok(
    not has_column_privilege('service_role', 'public.machines', 'api_key_hash', 'update'),
    'service_role nao pode atualizar machines.api_key_hash'
);

select extensions.ok(
    not has_column_privilege('anon', 'public.machines', 'api_key_hash', 'select'),
    'anon nao pode selecionar machines.api_key_hash'
);

select extensions.ok(
    not has_column_privilege('authenticated', 'public.machines', 'api_key_hash', 'select'),
    'authenticated nao pode selecionar machines.api_key_hash'
);

select extensions.lives_ok(
    $$set local role service_role;
      select id, school_id, api_key_hash from public.machines limit 1;
      reset role;$$,
    'service_role executa a leitura minima necessaria'
);

select extensions.throws_ok(
    $$set local role service_role;
      select name from public.machines limit 1;$$,
    '42501',
    'permission denied for table machines',
    'service_role nao executa leitura de coluna fora do grant'
);

select * from extensions.finish();
rollback;
