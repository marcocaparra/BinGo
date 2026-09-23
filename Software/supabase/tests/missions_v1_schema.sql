begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

-- Auxiliar temporario: valida SQLSTATE sem acoplar os testes ao texto de erro
-- emitido por uma versao especifica do PostgreSQL.
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

select extensions.is(
    (
        select count(*)::integer
        from pg_catalog.pg_class relation
        join pg_catalog.pg_namespace namespace
          on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relkind = 'r'
          and relation.relname in (
              'mission_definitions',
              'mission_cycles',
              'mission_completions',
              'mission_reward_applications'
          )
    ),
    4,
    'as quatro tabelas estruturais de Missoes V1 existem'
);

select extensions.ok(
    to_regclass('public.mission_progress') is null
    and to_regclass('public.mission_participants') is null
    and to_regclass('public.mission_enrollments') is null
    and to_regclass('public.mission_definition_rewards') is null
    and to_regclass('public.mission_cycle_rewards') is null
    and to_regclass('public.student_missions') is null
    and to_regclass('public.class_missions') is null,
    'nenhuma tabela proibida de progresso, participacao ou recompensa intermediaria existe'
);

select extensions.is(
    (
        select count(*)::integer
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.contype = 'p'
          and constraint_row.conrelid in (
              'public.mission_definitions'::regclass,
              'public.mission_cycles'::regclass,
              'public.mission_completions'::regclass,
              'public.mission_reward_applications'::regclass
          )
    ),
    4,
    'as quatro tabelas possuem chave primaria'
);

select extensions.ok(
    (
        select data_type = 'bigint' and is_nullable = 'NO'
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'mission_definitions'
          and column_name = 'target'
    )
    and (
        select data_type = 'bigint' and is_nullable = 'NO'
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'mission_cycles'
          and column_name = 'target'
    )
    and (
        select data_type = 'bigint' and is_nullable = 'NO'
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'mission_completions'
          and column_name = 'progress_at_completion'
    ),
    'targets e progresso usam bigint e sao obrigatorios'
);

select extensions.ok(
    (
        select bool_and(data_type = 'integer' and is_nullable = 'NO')
        from information_schema.columns
        where table_schema = 'public'
          and table_name in ('mission_definitions', 'mission_cycles')
          and column_name in ('reward_bincoins', 'reward_xp')
    )
    and (
        select data_type = 'integer' and is_nullable = 'NO'
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'mission_reward_applications'
          and column_name = 'amount_applied'
    ),
    'valores economicos usam integer e sao obrigatorios'
);

select extensions.ok(
    (
        select bool_and(data_type = 'timestamp with time zone' and is_nullable = 'NO')
        from information_schema.columns
        where table_schema = 'public'
          and (
              (table_name = 'mission_cycles' and column_name in ('starts_at', 'ends_at', 'created_at'))
              or
              (table_name = 'mission_completions' and column_name in ('achieved_at', 'materialized_at'))
              or
              (table_name = 'mission_reward_applications' and column_name = 'applied_at')
          )
    ),
    'instantes historicos usam timestamptz e sao obrigatorios'
);

select extensions.ok(
    (
        select bool_and(is_nullable = 'YES')
        from information_schema.columns
        where table_schema = 'public'
          and (
              (table_name = 'mission_definitions' and column_name = 'description')
              or
              (table_name = 'mission_completions' and column_name in ('student_id', 'class_id'))
              or
              (table_name = 'mission_reward_applications' and column_name in ('recipient_student_id', 'recipient_class_id'))
          )
    ),
    'somente os campos opcionais previstos aceitam null nos pontos criticos'
);

select extensions.is(
    (
        select count(*)::integer
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.contype = 'f'
          and constraint_row.conrelid in (
              'public.mission_cycles'::regclass,
              'public.mission_completions'::regclass,
              'public.mission_reward_applications'::regclass
          )
    ),
    8,
    'as oito FKs estruturais esperadas existem'
);

select extensions.ok(
    (
        select bool_and(constraint_row.confdeltype = 'r')
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.contype = 'f'
          and constraint_row.conrelid in (
              'public.mission_cycles'::regclass,
              'public.mission_completions'::regclass,
              'public.mission_reward_applications'::regclass
          )
    ),
    'todas as FKs de Missoes usam ON DELETE RESTRICT'
);

select extensions.ok(
    exists (
        select 1
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid = 'public.mission_completions'::regclass
          and constraint_row.conname = 'mission_completions_cycle_scope_fk'
          and constraint_row.contype = 'f'
          and constraint_row.confrelid = 'public.mission_cycles'::regclass
    ),
    'completion referencia relacionalmente ciclo e scope por FK composta'
);

select extensions.ok(
    not exists (
        select 1
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid = 'public.mission_definitions'::regclass
          and constraint_row.contype = 'f'
    ),
    'definicao global nao possui FK para escola ou outro catalogo'
);

select extensions.ok(
    not exists (
        select required.constraint_name
        from unnest(array[
            'mission_definitions_scope_check',
            'mission_definitions_metric_check',
            'mission_definitions_scope_metric_check',
            'mission_definitions_target_check',
            'mission_definitions_reward_bincoins_check',
            'mission_definitions_reward_xp_check',
            'mission_definitions_reward_required_check',
            'mission_cycles_period_order_check',
            'mission_cycles_timezone_check',
            'mission_cycles_scope_check',
            'mission_cycles_metric_check',
            'mission_cycles_scope_metric_check',
            'mission_cycles_target_check',
            'mission_cycles_reward_bincoins_check',
            'mission_cycles_reward_xp_check',
            'mission_cycles_reward_required_check',
            'mission_cycles_monthly_period_check',
            'mission_completions_participant_check',
            'mission_completions_progress_check',
            'mission_completions_materialized_after_achieved_check',
            'mission_reward_applications_type_check',
            'mission_reward_applications_amount_check',
            'mission_reward_applications_recipient_check'
        ]) as required(constraint_name)
        where not exists (
            select 1
            from pg_catalog.pg_constraint constraint_row
            where constraint_row.conname = required.constraint_name
              and constraint_row.contype = 'c'
        )
    ),
    'todos os CHECKs estruturais obrigatorios existem'
);

insert into public.schools (id, name)
values
    ('a1000000-0000-4000-8000-000000000001', 'Escola Missoes A'),
    ('a1000000-0000-4000-8000-000000000002', 'Escola Missoes B');

insert into public.classes (id, school_id, segment, grade, name)
values
    (
        'a2000000-0000-4000-8000-000000000001',
        'a1000000-0000-4000-8000-000000000001',
        'TESTE', '7', 'Turma A'
    ),
    (
        'a2000000-0000-4000-8000-000000000002',
        'a1000000-0000-4000-8000-000000000002',
        'TESTE', '7', 'Turma B'
    );

insert into public.students (
    id, school_id, class_id, name, status, is_activated
)
values
    (
        'a3000000-0000-4000-8000-000000000001',
        'a1000000-0000-4000-8000-000000000001',
        'a2000000-0000-4000-8000-000000000001',
        'Aluno ativo nao ativado', 'ACTIVE', false
    ),
    (
        'a3000000-0000-4000-8000-000000000002',
        'a1000000-0000-4000-8000-000000000001',
        'a2000000-0000-4000-8000-000000000001',
        'Aluno inativo ativado', 'INACTIVE', true
    );

select extensions.lives_ok(
    $$
    insert into public.mission_definitions (
        id, code, title, scope, metric, recurrence, target,
        reward_bincoins, reward_xp
    ) values (
        'a4000000-0000-4000-8000-000000000001',
        'SUSTAINABLE_CONSISTENCY', 'Consistencia Sustentavel',
        'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 3, 500, 0
    )
    $$,
    'definicao STUDENT valida pode existir sem ciclo'
);

insert into public.mission_definitions (
    id, code, title, scope, metric, recurrence, target,
    reward_bincoins, reward_xp
) values (
    'a4000000-0000-4000-8000-000000000002',
    'TOGETHER_FOR_THE_SQUARE', 'Juntos pela Praca',
    'CLASS', 'CLASS_XP_EARNED', 'MONTHLY', 10000, 1000, 2000
);

insert into public.mission_definitions (
    id, code, title, scope, metric, recurrence, target,
    reward_bincoins, reward_xp
) values (
    'a4000000-0000-4000-8000-000000000003',
    'NO_CYCLE_YET', 'Definicao sem ciclo',
    'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 100, 0
);

select extensions.is(
    (
        select count(*)::integer
        from public.mission_cycles
        where definition_id = 'a4000000-0000-4000-8000-000000000003'
    ),
    0,
    'definicao nao exige ciclo nem copia por participante'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_definitions
          (code, title, scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values ('BAD_SCOPE', 'x', 'SCHOOL', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 1, 0)$$,
        '23514'
    ),
    'scope de definicao fora de STUDENT/CLASS e rejeitado'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_definitions
          (code, title, scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values ('BAD_METRIC', 'x', 'STUDENT', 'ENVIRONMENTAL_IMPACT', 'MONTHLY', 1, 1, 0)$$,
        '23514'
    ),
    'metrica fora do primeiro slice e rejeitada'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_definitions
          (code, title, scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values ('BAD_PAIR', 'x', 'STUDENT', 'CLASS_XP_EARNED', 'MONTHLY', 1, 1, 0)$$,
        '23514'
    ),
    'combinacao scope/metric nao aprovada e rejeitada'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_definitions
          (code, title, scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values ('BAD_RECURRENCE', 'x', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'WEEKLY', 1, 1, 0)$$,
        '23514'
    ),
    'recorrencia nao documentada para o primeiro slice e rejeitada'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_definitions
          (code, title, scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values ('BAD_TARGET', 'x', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 0, 1, 0)$$,
        '23514'
    ),
    'target deve ser positivo'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_definitions
          (code, title, scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values ('BAD_BINCOINS', 'x', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, -1, 0)$$,
        '23514'
    ),
    'reward_bincoins negativa e rejeitada'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_definitions
          (code, title, scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values ('BAD_XP', 'x', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 0, -1)$$,
        '23514'
    ),
    'reward_xp negativa e rejeitada'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_definitions
          (code, title, scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values ('NO_REWARD', 'x', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 0, 0)$$,
        '23514'
    ),
    'definicao sem qualquer recompensa e rejeitada'
);

insert into public.mission_cycles (
    id, definition_id, school_id, starts_at, ends_at, timezone,
    scope, metric, recurrence, target, reward_bincoins, reward_xp
) values
    (
        'a5000000-0000-4000-8000-000000000001',
        'a4000000-0000-4000-8000-000000000001',
        'a1000000-0000-4000-8000-000000000001',
        '2026-09-01 00:00:00-03', '2026-10-01 00:00:00-03',
        'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT',
        'MONTHLY', 3, 500, 0
    ),
    (
        'a5000000-0000-4000-8000-000000000002',
        'a4000000-0000-4000-8000-000000000001',
        'a1000000-0000-4000-8000-000000000002',
        '2026-09-01 00:00:00-03', '2026-10-01 00:00:00-03',
        'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT',
        'MONTHLY', 3, 500, 0
    ),
    (
        'a5000000-0000-4000-8000-000000000003',
        'a4000000-0000-4000-8000-000000000002',
        'a1000000-0000-4000-8000-000000000001',
        '2026-09-01 00:00:00-03', '2026-10-01 00:00:00-03',
        'America/Sao_Paulo', 'CLASS', 'CLASS_XP_EARNED',
        'MONTHLY', 10000, 1000, 2000
    );

select extensions.is(
    (
        select count(*)::integer
        from public.mission_cycles
        where definition_id = 'a4000000-0000-4000-8000-000000000001'
          and starts_at = '2026-09-01 00:00:00-03'
    ),
    2,
    'escolas diferentes possuem ciclos independentes da mesma definicao e periodo'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_cycles
          (definition_id, school_id, starts_at, ends_at, timezone,
           scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values (
            'a4000000-0000-4000-8000-000000000001',
            'a1000000-0000-4000-8000-000000000001',
            '2026-09-01 00:00:00-03', '2026-10-01 00:00:00-03',
            'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT',
            'MONTHLY', 3, 500, 0
          )$$,
        '23505'
    ),
    'mesma escola nao aceita ciclo duplicado da mesma definicao e periodo'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_cycles
          (definition_id, school_id, starts_at, ends_at, timezone,
           scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values (
            'a4000000-0000-4000-8000-000000000001',
            'a1000000-0000-4000-8000-000000000001',
            '2026-11-01 00:00:00-03', '2026-11-01 00:00:00-03',
            'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT',
            'MONTHLY', 3, 500, 0
          )$$,
        '23514'
    ),
    'ciclo exige starts_at anterior a ends_at'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_cycles
          (definition_id, school_id, starts_at, ends_at, timezone,
           scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values (
            'a4000000-0000-4000-8000-000000000001',
            'a1000000-0000-4000-8000-000000000001',
            '2026-11-01 00:00:00+00', '2026-12-01 00:00:00+00',
            'UTC', 'STUDENT', 'VALID_DEPOSIT_COUNT',
            'MONTHLY', 3, 500, 0
          )$$,
        '23514'
    ),
    'ciclo rejeita timezone diferente de America/Sao_Paulo'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_cycles
          (definition_id, school_id, starts_at, ends_at, timezone,
           scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values (
            'a4000000-0000-4000-8000-000000000001',
            'a1000000-0000-4000-8000-000000000001',
            '2026-11-02 00:00:00-03', '2026-12-02 00:00:00-03',
            'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT',
            'MONTHLY', 3, 500, 0
          )$$,
        '23514'
    ),
    'ciclo mensal exige fronteiras canonicas no timezone oficial'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_cycles
          (definition_id, school_id, starts_at, ends_at, timezone,
           scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values (
            'a4000000-0000-4000-8000-000000000001',
            'a1000000-0000-4000-8000-000000000001',
            '2026-11-01 00:00:00-03', '2026-12-01 00:00:00-03',
            'America/Sao_Paulo', 'STUDENT', 'CLASS_XP_EARNED',
            'MONTHLY', 3, 500, 0
          )$$,
        '23514'
    ),
    'snapshot do ciclo rejeita combinacao scope/metric invalida'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_cycles
          (definition_id, school_id, starts_at, ends_at, timezone,
           scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values (
            'a4000000-0000-4000-8000-000000000001',
            'a1000000-0000-4000-8000-000000000001',
            '2026-11-01 00:00:00-03', '2026-12-01 00:00:00-03',
            'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT',
            'MONTHLY', 0, 500, 0
          )$$,
        '23514'
    ),
    'snapshot do ciclo exige target positivo'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_cycles
          (definition_id, school_id, starts_at, ends_at, timezone,
           scope, metric, recurrence, target, reward_bincoins, reward_xp)
          values (
            'a4000000-0000-4000-8000-000000000001',
            'a1000000-0000-4000-8000-000000000001',
            '2026-11-01 00:00:00-03', '2026-12-01 00:00:00-03',
            'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT',
            'MONTHLY', 3, 0, 0
          )$$,
        '23514'
    ),
    'snapshot do ciclo exige ao menos uma recompensa positiva'
);

update public.mission_definitions
set target = 99, reward_bincoins = 999
where id = 'a4000000-0000-4000-8000-000000000001';

select extensions.ok(
    (
        select target = 3 and reward_bincoins = 500 and reward_xp = 0
        from public.mission_cycles
        where id = 'a5000000-0000-4000-8000-000000000001'
    ),
    'alterar definicao nao modifica o snapshot do ciclo existente'
);

select extensions.is(
    (select count(*)::integer from public.mission_completions),
    0,
    'ciclos nao precriam completion por aluno ou turma'
);

insert into public.mission_completions (
    id, cycle_id, participant_scope, student_id,
    progress_at_completion, achieved_at, materialized_at
) values (
    'a6000000-0000-4000-8000-000000000001',
    'a5000000-0000-4000-8000-000000000001',
    'STUDENT', 'a3000000-0000-4000-8000-000000000001',
    3, '2026-09-30 23:59:00-03', '2026-10-01 08:00:00-03'
);

insert into public.mission_completions (
    id, cycle_id, participant_scope, class_id,
    progress_at_completion, achieved_at, materialized_at
) values (
    'a6000000-0000-4000-8000-000000000002',
    'a5000000-0000-4000-8000-000000000003',
    'CLASS', 'a2000000-0000-4000-8000-000000000001',
    11400, '2026-09-28 12:00:00-03', '2026-09-28 12:01:00-03'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_completions
          (cycle_id, participant_scope, student_id, class_id,
           progress_at_completion, achieved_at, materialized_at)
          values (
            'a5000000-0000-4000-8000-000000000001', 'STUDENT',
            'a3000000-0000-4000-8000-000000000002',
            'a2000000-0000-4000-8000-000000000001',
            3, '2026-09-20 00:00:00-03', '2026-09-20 01:00:00-03'
          )$$,
        '23514'
    ),
    'completion nunca aceita dois participantes'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_completions
          (cycle_id, participant_scope, class_id,
           progress_at_completion, achieved_at, materialized_at)
          values (
            'a5000000-0000-4000-8000-000000000001', 'STUDENT',
            'a2000000-0000-4000-8000-000000000001',
            3, '2026-09-20 00:00:00-03', '2026-09-20 01:00:00-03'
          )$$,
        '23514'
    ),
    'STUDENT completion nao aceita turma como participante'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_completions
          (cycle_id, participant_scope, student_id,
           progress_at_completion, achieved_at, materialized_at)
          values (
            'a5000000-0000-4000-8000-000000000003', 'CLASS',
            'a3000000-0000-4000-8000-000000000001',
            10000, '2026-09-20 00:00:00-03', '2026-09-20 01:00:00-03'
          )$$,
        '23514'
    ),
    'CLASS completion nao aceita aluno como participante'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_completions
          (cycle_id, participant_scope, class_id,
           progress_at_completion, achieved_at, materialized_at)
          values (
            'a5000000-0000-4000-8000-000000000001', 'CLASS',
            'a2000000-0000-4000-8000-000000000001',
            3, '2026-09-20 00:00:00-03', '2026-09-20 01:00:00-03'
          )$$,
        '23503'
    ),
    'FK composta impede scope diferente do scope do ciclo'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_completions
          (cycle_id, participant_scope, student_id,
           progress_at_completion, achieved_at, materialized_at)
          values (
            'a5000000-0000-4000-8000-000000000001', 'STUDENT',
            'a3000000-0000-4000-8000-000000000002',
            0, '2026-09-20 00:00:00-03', '2026-09-20 01:00:00-03'
          )$$,
        '23514'
    ),
    'completion exige progresso positivo'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_completions
          (cycle_id, participant_scope, student_id,
           progress_at_completion, achieved_at, materialized_at)
          values (
            'a5000000-0000-4000-8000-000000000001', 'STUDENT',
            'a3000000-0000-4000-8000-000000000002',
            3, '2026-09-20 01:00:00-03', '2026-09-20 00:00:00-03'
          )$$,
        '23514'
    ),
    'materialized_at nao pode anteceder achieved_at'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_completions
          (cycle_id, participant_scope, student_id,
           progress_at_completion, achieved_at, materialized_at)
          values (
            'a5000000-0000-4000-8000-000000000001', 'STUDENT',
            'a3000000-0000-4000-8000-000000000001',
            4, '2026-09-29 00:00:00-03', '2026-09-29 01:00:00-03'
          )$$,
        '23505'
    ),
    'aluno possui no maximo uma completion por ciclo'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_completions
          (cycle_id, participant_scope, class_id,
           progress_at_completion, achieved_at, materialized_at)
          values (
            'a5000000-0000-4000-8000-000000000003', 'CLASS',
            'a2000000-0000-4000-8000-000000000001',
            12000, '2026-09-29 00:00:00-03', '2026-09-29 01:00:00-03'
          )$$,
        '23505'
    ),
    'turma possui no maximo uma completion por ciclo'
);

insert into public.mission_reward_applications (
    id, completion_id, reward_type, amount_applied, recipient_student_id
) values (
    'a7000000-0000-4000-8000-000000000001',
    'a6000000-0000-4000-8000-000000000001',
    'BINCOINS', 500, 'a3000000-0000-4000-8000-000000000001'
);

insert into public.mission_reward_applications (
    id, completion_id, reward_type, amount_applied, recipient_class_id
) values (
    'a7000000-0000-4000-8000-000000000002',
    'a6000000-0000-4000-8000-000000000001',
    'XP', 1000, 'a2000000-0000-4000-8000-000000000001'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_reward_applications
          (completion_id, reward_type, amount_applied, recipient_class_id)
          values (
            'a6000000-0000-4000-8000-000000000002',
            'BINCOINS', 1000, 'a2000000-0000-4000-8000-000000000001'
          )$$,
        '23514'
    ),
    'BINCOINS exige destinatario student'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_reward_applications
          (completion_id, reward_type, amount_applied, recipient_student_id)
          values (
            'a6000000-0000-4000-8000-000000000002',
            'XP', 2000, 'a3000000-0000-4000-8000-000000000001'
          )$$,
        '23514'
    ),
    'XP exige destinatario class'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_reward_applications
          (completion_id, reward_type, amount_applied,
           recipient_student_id, recipient_class_id)
          values (
            'a6000000-0000-4000-8000-000000000002', 'BINCOINS', 1000,
            'a3000000-0000-4000-8000-000000000001',
            'a2000000-0000-4000-8000-000000000001'
          )$$,
        '23514'
    ),
    'reward application nunca aceita dois destinatarios'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_reward_applications
          (completion_id, reward_type, amount_applied, recipient_student_id)
          values (
            'a6000000-0000-4000-8000-000000000002',
            'BINCOINS', 0, 'a3000000-0000-4000-8000-000000000001'
          )$$,
        '23514'
    ),
    'reward application exige amount_applied positivo'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_reward_applications
          (completion_id, reward_type, amount_applied, recipient_student_id)
          values (
            'a6000000-0000-4000-8000-000000000001',
            'BINCOINS', 500, 'a3000000-0000-4000-8000-000000000001'
          )$$,
        '23505'
    ),
    'mesma completion nao duplica BinCoins para o mesmo aluno'
);

select extensions.ok(
    pg_temp.raises_state(
        $$insert into public.mission_reward_applications
          (completion_id, reward_type, amount_applied, recipient_class_id)
          values (
            'a6000000-0000-4000-8000-000000000001',
            'XP', 1000, 'a2000000-0000-4000-8000-000000000001'
          )$$,
        '23505'
    ),
    'mesma completion nao duplica XP para a mesma turma'
);

select extensions.is(
    (
        select count(*)::integer
        from pg_catalog.pg_class relation
        join pg_catalog.pg_namespace namespace
          on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relname in (
              'mission_definitions',
              'mission_cycles',
              'mission_completions',
              'mission_reward_applications'
          )
          and relation.relrowsecurity
    ),
    4,
    'RLS esta habilitada nas quatro tabelas de Missoes'
);

select extensions.is(
    (
        select count(*)::integer
        from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename in (
              'mission_definitions',
              'mission_cycles',
              'mission_completions',
              'mission_reward_applications'
          )
    ),
    0,
    'nenhuma policy direta e aberta antes das RPCs autorizadas'
);

select extensions.ok(
    not exists (
        select 1
        from unnest(array['anon', 'authenticated', 'service_role'])
            as exposed(role_name)
        cross join unnest(array[
            'mission_definitions',
            'mission_cycles',
            'mission_completions',
            'mission_reward_applications'
        ]) as mission_table(table_name)
        cross join unnest(array['select', 'insert', 'update', 'delete'])
            as checked_privilege(privilege_name)
        where has_table_privilege(
            role_name,
            format('public.%I', table_name),
            privilege_name
        )
    ),
    'anon, authenticated e service_role nao recebem acesso direto as tabelas'
);

select extensions.ok(
    not exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name in (
              'mission_definitions',
              'mission_cycles',
              'mission_completions',
              'mission_reward_applications'
          )
          and column_name in ('is_activated', 'status', 'participant_id')
    ),
    'elegibilidade ACTIVE e is_activated nao viram coluna ou participacao persistida'
);

select extensions.ok(
    exists (
        select 1
        from pg_catalog.pg_class index_relation
        join pg_catalog.pg_namespace namespace
          on namespace.oid = index_relation.relnamespace
        join pg_catalog.pg_index index_row
          on index_row.indexrelid = index_relation.oid
        where namespace.nspname = 'public'
          and index_relation.relname = 'idx_deposits_class_created_at_valid'
          and index_row.indrelid = 'public.deposits'::regclass
          and not index_row.indisunique
          and pg_get_indexdef(index_row.indexrelid)
              ~ '\(class_id, created_at, id\) INCLUDE \(points_awarded_class\)'
          and pg_get_expr(index_row.indpred, index_row.indrelid) = 'is_valid'
    ),
    'indice parcial CLASS cobre periodo, desempate, XP e somente depositos validos'
);

select extensions.ok(
    to_regclass('public.idx_deposits_student_created_at') is not null,
    'indice existente de student_id e created_at foi preservado sem duplicacao'
);

select extensions.ok(
    (
        select count(*) = 6
        from pg_catalog.pg_proc function_row
        join pg_catalog.pg_namespace namespace
          on namespace.oid = function_row.pronamespace
        where namespace.nspname = 'public'
          and function_row.proname = any (array[
              'calculate_mission_progress_v1',
              'get_active_missions_v1',
              'process_mission_event_v1',
              'process_mission_event_v1_core',
              'record_mission_processing_failure_v1',
              'recover_next_mission_event_v1'
          ])
    ),
    'runtime adiciona leitura, nucleo economico e entradas server-side de processamento, retry e recuperacao'
);

select extensions.ok(
    (
        select status = 'ACTIVE' and not is_activated
        from public.students
        where id = 'a3000000-0000-4000-8000-000000000001'
    )
    and (
        select status = 'INACTIVE' and is_activated
        from public.students
        where id = 'a3000000-0000-4000-8000-000000000002'
    ),
    'fixture preserva que status ACTIVE, e nao is_activated, orienta a RPC de leitura'
);

select * from extensions.finish();
rollback;
