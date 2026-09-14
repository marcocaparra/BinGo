-- BinGo V1
-- Migration: 011_points_unit_redenomination.sql
--
-- Este arquivo deve permanecer funcionalmente equivalente a
-- database/migrations/011_points_unit_redenomination.sql.
--
-- Redenomina BinCoins e XP por fator 100 sem alterar poder economico.
-- A migration preserva os tipos integer, snapshots historicos, timestamps e
-- metadata de auditoria preexistente.

begin;

select pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('bingo.points_unit_redenomination.v1', 0)
);

-- A ordem dos locks cria uma barreira antes das tabelas alteradas e tambem
-- impede resgates concorrentes durante a conversao de saldo e custo.
lock table public.schools in share mode;
lock table
    public.classes,
    public.school_settings,
    public.students,
    public.deposits,
    public.rewards,
    public.redemptions,
    public.audit_logs
in access exclusive mode;

do $$
declare
    v_bincoins_default_expression text;
    v_class_xp_default_expression text;
    v_weekly_goal_default_expression text;
    v_bincoins_default bigint;
    v_class_xp_default bigint;
    v_weekly_goal_default bigint;
    v_overflow_field text;
    v_overflow_value bigint;
begin
    select pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid)
    into v_bincoins_default_expression
    from pg_catalog.pg_attrdef as default_value
    join pg_catalog.pg_attribute as attribute
      on attribute.attrelid = default_value.adrelid
     and attribute.attnum = default_value.adnum
    where default_value.adrelid = 'public.school_settings'::pg_catalog.regclass
      and attribute.attname = 'deposit_bincoins_base';

    select pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid)
    into v_class_xp_default_expression
    from pg_catalog.pg_attrdef as default_value
    join pg_catalog.pg_attribute as attribute
      on attribute.attrelid = default_value.adrelid
     and attribute.attnum = default_value.adnum
    where default_value.adrelid = 'public.school_settings'::pg_catalog.regclass
      and attribute.attname = 'deposit_class_xp_base';

    select pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid)
    into v_weekly_goal_default_expression
    from pg_catalog.pg_attrdef as default_value
    join pg_catalog.pg_attribute as attribute
      on attribute.attrelid = default_value.adrelid
     and attribute.attnum = default_value.adnum
    where default_value.adrelid = 'public.school_settings'::pg_catalog.regclass
      and attribute.attname = 'class_weekly_xp_goal';

    if v_bincoins_default_expression is null
       or v_class_xp_default_expression is null
       or v_weekly_goal_default_expression is null then
        raise exception using
            errcode = 'P0001',
            message = 'Redenominacao abortada: defaults estruturais de pontuacao ausentes.';
    end if;

    begin
        execute pg_catalog.format(
            'select (%s)::bigint',
            v_bincoins_default_expression
        ) into v_bincoins_default;
        execute pg_catalog.format(
            'select (%s)::bigint',
            v_class_xp_default_expression
        ) into v_class_xp_default;
        execute pg_catalog.format(
            'select (%s)::bigint',
            v_weekly_goal_default_expression
        ) into v_weekly_goal_default;
    exception when others then
        raise exception using
            errcode = 'P0001',
            message = 'Redenominacao abortada: defaults estruturais de pontuacao inesperados.';
    end;

    if (v_bincoins_default, v_class_xp_default, v_weekly_goal_default)
        is not distinct from (800::bigint, 1900::bigint, 10000::bigint) then
        raise exception using
            errcode = 'P0001',
            message = 'Redenominacao abortada: a unidade nova ja esta configurada.';
    elsif (v_bincoins_default, v_class_xp_default, v_weekly_goal_default)
        is distinct from (8::bigint, 19::bigint, 100::bigint) then
        raise exception using
            errcode = 'P0001',
            message = pg_catalog.format(
                'Redenominacao abortada: defaults em estado inesperado (%s/%s/%s).',
                v_bincoins_default,
                v_class_xp_default,
                v_weekly_goal_default
            );
    end if;

    if exists (
        select 1
        from public.audit_logs
        where action = 'POINTS_UNIT_REDENOMINATED_V1'
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Redenominacao abortada: evento de auditoria V1 ja existente.';
    end if;

    select affected.field_name, affected.maximum_value
    into v_overflow_field, v_overflow_value
    from (
        select 'school_settings.deposit_bincoins_base'::text as field_name,
               pg_catalog.max(deposit_bincoins_base)::bigint as maximum_value
        from public.school_settings
        union all
        select 'school_settings.deposit_class_xp_base',
               pg_catalog.max(deposit_class_xp_base)::bigint
        from public.school_settings
        union all
        select 'school_settings.class_weekly_xp_goal',
               pg_catalog.max(class_weekly_xp_goal)::bigint
        from public.school_settings
        union all
        select 'students.points_student_balance',
               pg_catalog.max(points_student_balance)::bigint
        from public.students
        union all
        select 'classes.points_class_balance',
               pg_catalog.max(points_class_balance)::bigint
        from public.classes
        union all
        select 'deposits.points_awarded_student',
               pg_catalog.max(points_awarded_student)::bigint
        from public.deposits
        union all
        select 'deposits.points_awarded_class',
               pg_catalog.max(points_awarded_class)::bigint
        from public.deposits
        union all
        select 'deposits.bonus_bincoins_awarded',
               pg_catalog.max(bonus_bincoins_awarded)::bigint
        from public.deposits
        union all
        select 'rewards.cost_points',
               pg_catalog.max(cost_points)::bigint
        from public.rewards
    ) as affected
    where affected.maximum_value > 21474836
    order by affected.field_name
    limit 1;

    if v_overflow_field is not null then
        raise exception using
            errcode = '22003',
            message = pg_catalog.format(
                'Redenominacao abortada: %s possui valor %s que excede o limite seguro 21474836.',
                v_overflow_field,
                v_overflow_value
            );
    end if;
end;
$$;

create temporary table points_unit_redenomination_before
on commit drop
as
with affected_schools as (
    select school_id from public.school_settings
    union
    select school_id from public.students
    union
    select school_id from public.classes
    union
    select school_id from public.deposits
    union
    select school_id from public.rewards
)
select
    affected.school_id,
    (select count(*)::bigint from public.school_settings where school_id = affected.school_id) as school_settings_count,
    (select count(*)::bigint from public.students where school_id = affected.school_id) as students_count,
    (select count(*)::bigint from public.classes where school_id = affected.school_id) as classes_count,
    (select count(*)::bigint from public.deposits where school_id = affected.school_id) as deposits_count,
    (select count(*)::bigint from public.rewards where school_id = affected.school_id) as rewards_count,
    (select count(*)::bigint from public.redemptions where school_id = affected.school_id) as redemptions_count,
    (select count(*)::bigint from public.audit_logs where school_id = affected.school_id) as audit_logs_count,
    (select coalesce(sum(deposit_bincoins_base), 0)::bigint from public.school_settings where school_id = affected.school_id) as deposit_bincoins_base_sum,
    (select coalesce(sum(deposit_class_xp_base), 0)::bigint from public.school_settings where school_id = affected.school_id) as deposit_class_xp_base_sum,
    (select coalesce(sum(class_weekly_xp_goal), 0)::bigint from public.school_settings where school_id = affected.school_id) as class_weekly_xp_goal_sum,
    (select coalesce(sum(points_student_balance), 0)::bigint from public.students where school_id = affected.school_id) as points_student_balance_sum,
    (select coalesce(sum(points_class_balance), 0)::bigint from public.classes where school_id = affected.school_id) as points_class_balance_sum,
    (select coalesce(sum(points_awarded_student), 0)::bigint from public.deposits where school_id = affected.school_id) as points_awarded_student_sum,
    (select coalesce(sum(points_awarded_class), 0)::bigint from public.deposits where school_id = affected.school_id) as points_awarded_class_sum,
    (select coalesce(sum(bonus_bincoins_awarded), 0)::bigint from public.deposits where school_id = affected.school_id) as bonus_bincoins_awarded_sum,
    (select coalesce(sum(cost_points), 0)::bigint from public.rewards where school_id = affected.school_id) as rewards_cost_points_sum
from affected_schools as affected;

update public.school_settings
set
    deposit_bincoins_base = (deposit_bincoins_base::bigint * 100)::integer,
    deposit_class_xp_base = (deposit_class_xp_base::bigint * 100)::integer,
    class_weekly_xp_goal = (class_weekly_xp_goal::bigint * 100)::integer;

update public.students
set points_student_balance = (points_student_balance::bigint * 100)::integer;

update public.classes
set points_class_balance = (points_class_balance::bigint * 100)::integer;

update public.deposits
set
    points_awarded_student = (points_awarded_student::bigint * 100)::integer,
    points_awarded_class = (points_awarded_class::bigint * 100)::integer,
    bonus_bincoins_awarded = (bonus_bincoins_awarded::bigint * 100)::integer;

update public.rewards
set cost_points = (cost_points::bigint * 100)::integer;

alter table public.school_settings
    alter column deposit_bincoins_base set default 800,
    alter column deposit_class_xp_base set default 1900,
    alter column class_weekly_xp_goal set default 10000;

do $$
begin
    if exists (
        select 1
        from points_unit_redenomination_before as before_state
        where (select count(*) from public.school_settings where school_id = before_state.school_id) <> before_state.school_settings_count
           or (select count(*) from public.students where school_id = before_state.school_id) <> before_state.students_count
           or (select count(*) from public.classes where school_id = before_state.school_id) <> before_state.classes_count
           or (select count(*) from public.deposits where school_id = before_state.school_id) <> before_state.deposits_count
           or (select count(*) from public.rewards where school_id = before_state.school_id) <> before_state.rewards_count
           or (select count(*) from public.redemptions where school_id = before_state.school_id) <> before_state.redemptions_count
           or (select coalesce(sum(deposit_bincoins_base), 0)::bigint from public.school_settings where school_id = before_state.school_id) <> before_state.deposit_bincoins_base_sum * 100
           or (select coalesce(sum(deposit_class_xp_base), 0)::bigint from public.school_settings where school_id = before_state.school_id) <> before_state.deposit_class_xp_base_sum * 100
           or (select coalesce(sum(class_weekly_xp_goal), 0)::bigint from public.school_settings where school_id = before_state.school_id) <> before_state.class_weekly_xp_goal_sum * 100
           or (select coalesce(sum(points_student_balance), 0)::bigint from public.students where school_id = before_state.school_id) <> before_state.points_student_balance_sum * 100
           or (select coalesce(sum(points_class_balance), 0)::bigint from public.classes where school_id = before_state.school_id) <> before_state.points_class_balance_sum * 100
           or (select coalesce(sum(points_awarded_student), 0)::bigint from public.deposits where school_id = before_state.school_id) <> before_state.points_awarded_student_sum * 100
           or (select coalesce(sum(points_awarded_class), 0)::bigint from public.deposits where school_id = before_state.school_id) <> before_state.points_awarded_class_sum * 100
           or (select coalesce(sum(bonus_bincoins_awarded), 0)::bigint from public.deposits where school_id = before_state.school_id) <> before_state.bonus_bincoins_awarded_sum * 100
           or (select coalesce(sum(cost_points), 0)::bigint from public.rewards where school_id = before_state.school_id) <> before_state.rewards_cost_points_sum * 100
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Redenominacao abortada: validacao pos-conversao falhou.';
    end if;
end;
$$;

insert into public.audit_logs (
    school_id,
    actor_type,
    actor_id,
    action,
    metadata
)
select
    before_state.school_id,
    'SYSTEM',
    null,
    'POINTS_UNIT_REDENOMINATED_V1',
    pg_catalog.jsonb_build_object(
        'factor', 100,
        'migration_id', 'POINTS_UNIT_REDENOMINATION_V1',
        'database_migration', '011_points_unit_redenomination.sql',
        'supabase_migration', '20260913120000_points_unit_redenomination.sql',
        'previous_unit', 'LEGACY_POINT_UNIT',
        'new_unit', 'POINT_UNIT_X100',
        'historical_audit_logs_metadata', 'PRESERVED_IN_PREVIOUS_UNIT',
        'counts_before', pg_catalog.jsonb_build_object(
            'school_settings', before_state.school_settings_count,
            'students', before_state.students_count,
            'classes', before_state.classes_count,
            'deposits', before_state.deposits_count,
            'rewards', before_state.rewards_count,
            'redemptions', before_state.redemptions_count,
            'audit_logs', before_state.audit_logs_count
        ),
        'aggregates_before', pg_catalog.jsonb_build_object(
            'deposit_bincoins_base', before_state.deposit_bincoins_base_sum,
            'deposit_class_xp_base', before_state.deposit_class_xp_base_sum,
            'class_weekly_xp_goal', before_state.class_weekly_xp_goal_sum,
            'points_student_balance', before_state.points_student_balance_sum,
            'points_class_balance', before_state.points_class_balance_sum,
            'points_awarded_student', before_state.points_awarded_student_sum,
            'points_awarded_class', before_state.points_awarded_class_sum,
            'bonus_bincoins_awarded', before_state.bonus_bincoins_awarded_sum,
            'rewards_cost_points', before_state.rewards_cost_points_sum
        ),
        'aggregates_after', pg_catalog.jsonb_build_object(
            'deposit_bincoins_base', before_state.deposit_bincoins_base_sum * 100,
            'deposit_class_xp_base', before_state.deposit_class_xp_base_sum * 100,
            'class_weekly_xp_goal', before_state.class_weekly_xp_goal_sum * 100,
            'points_student_balance', before_state.points_student_balance_sum * 100,
            'points_class_balance', before_state.points_class_balance_sum * 100,
            'points_awarded_student', before_state.points_awarded_student_sum * 100,
            'points_awarded_class', before_state.points_awarded_class_sum * 100,
            'bonus_bincoins_awarded', before_state.bonus_bincoins_awarded_sum * 100,
            'rewards_cost_points', before_state.rewards_cost_points_sum * 100
        )
    )
from points_unit_redenomination_before as before_state;

do $$
begin
    if exists (
        select 1
        from points_unit_redenomination_before as before_state
        where (
            select count(*)
            from public.audit_logs as audit
            where audit.school_id = before_state.school_id
              and audit.action = 'POINTS_UNIT_REDENOMINATED_V1'
              and audit.actor_type = 'SYSTEM'
              and audit.actor_id is null
        ) <> 1
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Redenominacao abortada: auditoria SYSTEM por escola nao foi preservada.';
    end if;
end;
$$;

commit;
