begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(38);

select extensions.is(
    (
        select count(*)::integer
        from pg_class as relation
        join pg_namespace as namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relkind in ('r', 'p')
          and relation.relrowsecurity
    ),
    11,
    'RLS esta habilitado nas onze tabelas de dominio public'
);

select extensions.is(
    (select count(*)::integer from pg_policies where schemaname = 'public'),
    4,
    'somente as quatro policies aprovadas existem'
);

select extensions.ok(
    exists (
        select 1 from pg_policies
        where schemaname = 'public'
          and tablename = 'students'
          and policyname = 'students_select_own_v1'
          and cmd = 'SELECT'
          and roles = array['authenticated']::name[]
    ),
    'students possui policy SELECT explicita para authenticated'
);

select extensions.ok(
    exists (
        select 1 from pg_policies
        where schemaname = 'public'
          and tablename = 'classes'
          and policyname = 'classes_select_own_v1'
          and cmd = 'SELECT'
          and roles = array['authenticated']::name[]
    ),
    'classes possui policy SELECT explicita para authenticated'
);

select extensions.ok(
    exists (
        select 1 from pg_policies
        where schemaname = 'public'
          and tablename = 'schools'
          and policyname = 'schools_select_own_v1'
          and cmd = 'SELECT'
          and roles = array['authenticated']::name[]
    ),
    'schools possui policy SELECT explicita para authenticated'
);

select extensions.ok(
    exists (
        select 1 from pg_policies
        where schemaname = 'public'
          and tablename = 'waste_categories'
          and policyname = 'waste_categories_select_public_v1'
          and cmd = 'SELECT'
          and roles = array['anon', 'authenticated']::name[]
          and qual = 'true'
    ),
    'waste_categories preserva catalogo integralmente publico por policy'
);

select extensions.ok(
    not (
        select attribute.attnotnull
        from pg_attribute as attribute
        where attribute.attrelid = 'public.students'::regclass
          and attribute.attname = 'auth_user_id'
          and not attribute.attisdropped
    ),
    'students.auth_user_id permanece nullable'
);

select extensions.ok(
    exists (
        select 1
        from pg_constraint as constraint_row
        where constraint_row.conrelid = 'public.students'::regclass
          and constraint_row.conname = 'students_auth_user_id_unique'
          and constraint_row.contype = 'u'
    ),
    'students.auth_user_id permanece unico quando preenchido'
);

select extensions.ok(
    exists (
        select 1
        from pg_index as index_row
        join pg_class as index_relation on index_relation.oid = index_row.indexrelid
        where index_row.indrelid = 'public.students'::regclass
          and index_relation.relname = 'students_auth_user_id_unique'
          and index_row.indisunique
    ),
    'constraint de auth_user_id possui indice unico adequado'
);

select extensions.ok(
    not exists (
        select 1
        from (values ('anon'), ('authenticated'), ('service_role')) as exposed(role_name)
        cross join (
            select relation.oid
            from pg_class as relation
            join pg_namespace as namespace on namespace.oid = relation.relnamespace
            where namespace.nspname = 'public'
              and relation.relkind in ('r', 'p')
        ) as domain_table
        cross join (
            values
                ('insert'),
                ('update'),
                ('delete'),
                ('truncate'),
                ('references'),
                ('trigger'),
                ('maintain')
        ) as forbidden(privilege_name)
        where has_table_privilege(
            exposed.role_name,
            domain_table.oid,
            forbidden.privilege_name
        )
    ),
    'papeis expostos nao possuem escrita nem privilegios administrativos em tabelas'
);

select extensions.ok(
    has_table_privilege('anon', 'public.waste_categories', 'select'),
    'anon pode ler o catalogo global'
);

select extensions.ok(
    has_table_privilege('authenticated', 'public.waste_categories', 'select'),
    'authenticated pode ler o catalogo global'
);

select extensions.ok(
    not has_table_privilege('service_role', 'public.waste_categories', 'select'),
    'service_role nao recebe leitura direta desnecessaria do catalogo'
);

select extensions.ok(
    (
        select bool_and(
            has_column_privilege(
                'authenticated',
                'public.students',
                allowed.column_name,
                'select'
            )
        )
        from unnest(array[
            'id',
            'name',
            'school_id',
            'class_id',
            'points_student_balance',
            'status'
        ]) as allowed(column_name)
    ),
    'authenticated recebe somente as colunas funcionais do perfil'
);

select extensions.ok(
    has_column_privilege(
        'authenticated',
        'public.students',
        'auth_user_id',
        'select'
    ),
    'authenticated recebe auth_user_id exigido pelas policies relacionadas'
);

select extensions.ok(
    not has_column_privilege(
        'authenticated',
        'public.students',
        'pin_hash',
        'select'
    ),
    'pin_hash nao e exposto ao cliente autenticado'
);

select extensions.ok(
    not has_column_privilege(
        'authenticated',
        'public.students',
        'is_activated',
        'select'
    ),
    'is_activated nao e exposto sem necessidade comprovada'
);

select extensions.ok(
    not has_column_privilege(
        'authenticated',
        'public.students',
        'created_at',
        'select'
    ) and not has_column_privilege(
        'authenticated',
        'public.students',
        'updated_at',
        'select'
    ),
    'timestamps internos de students nao sao expostos'
);

select extensions.ok(
    (
        select bool_and(
            has_column_privilege(
                'authenticated',
                'public.classes',
                allowed.column_name,
                'select'
            )
        )
        from unnest(array[
            'id',
            'school_id',
            'segment',
            'grade',
            'name',
            'points_class_balance'
        ]) as allowed(column_name)
    ),
    'authenticated recebe as colunas minimas da propria turma'
);

select extensions.ok(
    has_column_privilege('authenticated', 'public.schools', 'id', 'select')
    and has_column_privilege('authenticated', 'public.schools', 'name', 'select'),
    'authenticated recebe id e nome da propria escola'
);

select extensions.ok(
    not exists (
        select 1
        from pg_class as relation
        join pg_namespace as namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relkind in ('r', 'p')
          and relation.relname <> 'waste_categories'
          and has_table_privilege('anon', relation.oid, 'select')
    ),
    'anon nao possui leitura de tabelas privadas'
);

select extensions.ok(
    has_column_privilege('service_role', 'public.machines', 'id', 'select'),
    'service_role pode ler machines.id'
);

select extensions.ok(
    has_column_privilege('service_role', 'public.machines', 'school_id', 'select'),
    'service_role pode ler machines.school_id'
);

select extensions.ok(
    has_column_privilege('service_role', 'public.machines', 'api_key_hash', 'select'),
    'service_role pode ler machines.api_key_hash'
);

select extensions.ok(
    not has_column_privilege('service_role', 'public.machines', 'name', 'select'),
    'service_role nao le coluna adicional de machines'
);

select extensions.ok(
    not has_table_privilege('service_role', 'public.machines', 'select'),
    'service_role nao recebe SELECT amplo em machines'
);

select extensions.ok(
    not has_column_privilege('anon', 'public.machines', 'api_key_hash', 'select'),
    'anon nao le api_key_hash'
);

select extensions.ok(
    not has_column_privilege('authenticated', 'public.machines', 'api_key_hash', 'select'),
    'authenticated nao le api_key_hash'
);

select extensions.ok(
    not has_function_privilege(
        'anon',
        'public.register_deposit_v1(uuid,uuid,uuid,boolean,uuid,text,text,text)',
        'execute'
    ),
    'anon nao executa register_deposit_v1'
);

select extensions.ok(
    not has_function_privilege(
        'authenticated',
        'public.register_deposit_v1(uuid,uuid,uuid,boolean,uuid,text,text,text)',
        'execute'
    ),
    'authenticated nao executa register_deposit_v1'
);

select extensions.ok(
    has_function_privilege(
        'service_role',
        'public.register_deposit_v1(uuid,uuid,uuid,boolean,uuid,text,text,text)',
        'execute'
    ),
    'service_role continua executando register_deposit_v1'
);

select extensions.ok(
    not has_function_privilege(
        'service_role',
        'public.register_deposit_v1_core(uuid,uuid,uuid,boolean,uuid,text,text,text)',
        'execute'
    ),
    'service_role nao executa diretamente o core interno'
);

select extensions.ok(
    (
        select bool_and(function_row.prosecdef)
        from pg_proc as function_row
        join pg_namespace as namespace on namespace.oid = function_row.pronamespace
        where namespace.nspname = 'public'
          and function_row.proname in ('register_deposit_v1', 'register_deposit_v1_core')
    ),
    'RPC publica e core permanecem SECURITY DEFINER'
);

select extensions.ok(
    (
        select bool_and(function_row.proconfig = array['search_path=""'])
        from pg_proc as function_row
        join pg_namespace as namespace on namespace.oid = function_row.pronamespace
        where namespace.nspname = 'public'
          and function_row.proname in ('register_deposit_v1', 'register_deposit_v1_core')
    ),
    'RPC publica e core preservam search_path vazio'
);

select extensions.ok(
    not exists (
        select 1
        from pg_default_acl as defaults
        cross join lateral aclexplode(defaults.defaclacl) as exploded
        where defaults.defaclrole = 'postgres'::regrole
          and defaults.defaclnamespace = 'public'::regnamespace
          and defaults.defaclobjtype = 'r'
          and exploded.grantee in (
              'anon'::regrole,
              'authenticated'::regrole,
              'service_role'::regrole
          )
    ),
    'novas tabelas de postgres nao herdam grants para papeis expostos'
);

select extensions.ok(
    not exists (
        select 1
        from pg_default_acl as defaults
        cross join lateral aclexplode(defaults.defaclacl) as exploded
        where defaults.defaclrole = 'postgres'::regrole
          and defaults.defaclnamespace = 'public'::regnamespace
          and defaults.defaclobjtype = 'S'
          and exploded.grantee in (
              'anon'::regrole,
              'authenticated'::regrole,
              'service_role'::regrole
          )
    ),
    'novas sequences de postgres nao herdam grants para papeis expostos'
);

select extensions.ok(
    not exists (
        select 1
        from pg_default_acl as defaults
        cross join lateral aclexplode(defaults.defaclacl) as exploded
        where defaults.defaclrole = 'postgres'::regrole
          and defaults.defaclnamespace = 'public'::regnamespace
          and defaults.defaclobjtype = 'f'
          and exploded.grantee in (
              'anon'::regrole,
              'authenticated'::regrole,
              'service_role'::regrole
          )
    ),
    'novas funcoes de postgres nao herdam EXECUTE para papeis expostos'
);

select extensions.ok(
    not exists (
        select 1
        from pg_class as relation
        join pg_namespace as namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relkind in ('r', 'p')
          and relation.relname <> 'machines'
          and has_table_privilege('service_role', relation.oid, 'select')
    ),
    'service_role nao recebe SELECT direto em outras tabelas de dominio'
);

select * from extensions.finish();
rollback;
