-- BinGo V1
-- Migration: 013_get_active_missions_v1.sql
--
-- Primeira leitura autenticada de Missoes V1. A RPC deriva o participante
-- de auth.uid(), agrega progresso de deposits e nao produz efeitos.

create function public.get_active_missions_v1()
returns table (
    cycle_id uuid,
    definition_id uuid,
    definition_code text,
    definition_title text,
    scope text,
    metric text,
    starts_at timestamptz,
    ends_at timestamptz,
    target bigint,
    reward_bincoins integer,
    reward_xp integer,
    progress bigint,
    is_achieved boolean,
    achieved_at timestamptz,
    is_completed boolean,
    materialized_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    with current_student as materialized (
        select
            student.id,
            student.school_id,
            student.class_id
        from public.students as student
        join public.classes as current_class
          on current_class.id = student.class_id
         and current_class.school_id = student.school_id
        where student.auth_user_id = auth.uid()
          and student.status = 'ACTIVE'
    ),
    active_cycles as materialized (
        select
            cycle.id,
            cycle.definition_id,
            definition.code,
            definition.title,
            cycle.scope,
            cycle.metric,
            cycle.starts_at,
            cycle.ends_at,
            cycle.target,
            cycle.reward_bincoins,
            cycle.reward_xp
        from current_student as student
        join public.mission_cycles as cycle
          on cycle.school_id = student.school_id
        join public.mission_definitions as definition
          on definition.id = cycle.definition_id
        where cycle.starts_at <= pg_catalog.now()
          and pg_catalog.now() < cycle.ends_at
    )
    select
        cycle.id as cycle_id,
        cycle.definition_id,
        cycle.code as definition_code,
        cycle.title as definition_title,
        cycle.scope,
        cycle.metric,
        cycle.starts_at,
        cycle.ends_at,
        cycle.target,
        cycle.reward_bincoins,
        cycle.reward_xp,
        case
            when cycle.scope = 'STUDENT' then student_progress.progress
            else class_progress.progress
        end as progress,
        case
            when cycle.scope = 'STUDENT'
                then student_progress.progress >= cycle.target
            else class_progress.progress >= cycle.target
        end as is_achieved,
        coalesce(
            completion.achieved_at,
            case
                when cycle.scope = 'STUDENT'
                    then student_progress.achieved_at
                else class_progress.achieved_at
            end
        ) as achieved_at,
        completion.id is not null as is_completed,
        completion.materialized_at
    from active_cycles as cycle
    cross join current_student as student
    left join lateral (
        select
            count(*)::bigint as progress,
            min(ranked_deposit.created_at)
                filter (where ranked_deposit.position = cycle.target)
                as achieved_at
        from (
            select
                deposit.created_at,
                row_number() over (
                    order by deposit.created_at, deposit.id
                ) as position
            from public.deposits as deposit
            where cycle.scope = 'STUDENT'
              and cycle.metric = 'VALID_DEPOSIT_COUNT'
              and deposit.student_id = student.id
              and deposit.is_valid
              and deposit.created_at >= cycle.starts_at
              and deposit.created_at < cycle.ends_at
        ) as ranked_deposit
    ) as student_progress on true
    left join lateral (
        select
            coalesce(
                sum(ranked_deposit.points_awarded_class),
                0::numeric
            )::bigint as progress,
            min(ranked_deposit.created_at)
                filter (
                    where ranked_deposit.accumulated_xp >= cycle.target
                ) as achieved_at
        from (
            select
                deposit.created_at,
                deposit.points_awarded_class::bigint
                    as points_awarded_class,
                sum(deposit.points_awarded_class::bigint) over (
                    order by deposit.created_at, deposit.id
                    rows between unbounded preceding and current row
                ) as accumulated_xp
            from public.deposits as deposit
            where cycle.scope = 'CLASS'
              and cycle.metric = 'CLASS_XP_EARNED'
              and deposit.class_id = student.class_id
              and deposit.is_valid
              and deposit.created_at >= cycle.starts_at
              and deposit.created_at < cycle.ends_at
        ) as ranked_deposit
    ) as class_progress on true
    left join public.mission_completions as completion
      on completion.cycle_id = cycle.id
     and (
            (
                cycle.scope = 'STUDENT'
                and completion.student_id = student.id
            )
            or
            (
                cycle.scope = 'CLASS'
                and completion.class_id = student.class_id
            )
         )
    order by cycle.starts_at, cycle.code, cycle.id;
$$;

comment on function public.get_active_missions_v1() is
    'Lista ciclos ativos da escola do aluno ACTIVE autenticado e calcula progresso derivado, sem efeitos colaterais.';

revoke all on function public.get_active_missions_v1()
from public, anon, authenticated, service_role;

grant execute on function public.get_active_missions_v1()
to authenticated;
