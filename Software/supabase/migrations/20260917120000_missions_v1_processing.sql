-- BinGo V1
-- Migration: 20260917120000_missions_v1_processing.sql
-- Executavelmente equivalente a database/migrations/014_missions_v1_processing.sql.

begin;

create table public.mission_processing_queue (
    event_id uuid primary key
        references public.deposits(event_id) on delete restrict,
    enqueued_at timestamptz not null default now(),
    processed_at timestamptz,
    constraint mission_processing_queue_processed_after_enqueued_check
        check (processed_at is null or processed_at >= enqueued_at)
);

comment on table public.mission_processing_queue is
    'Pendencia duravel minima por event_id para processamento idempotente de Missoes V1.';

create index idx_mission_processing_queue_pending
    on public.mission_processing_queue(enqueued_at, event_id)
    where processed_at is null;

alter table public.mission_processing_queue enable row level security;

revoke all privileges on table public.mission_processing_queue
from public, anon, authenticated, service_role;

create or replace function public.register_deposit_v1(
    p_event_id uuid,
    p_machine_id uuid,
    p_class_id uuid,
    p_is_valid boolean,
    p_student_id uuid default null,
    p_detected_type text default null,
    p_waste_category_code text default null,
    p_category_source text default null
)
returns table (
    deposit_id uuid,
    event_id uuid,
    waste_category_code text,
    category_source text,
    bonus_rate_applied numeric,
    bonus_bincoins_awarded integer,
    points_awarded_student integer,
    points_awarded_class integer,
    created_at timestamptz,
    was_replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_result record;
begin
    for v_result in
        select *
        from public.register_deposit_v1_core(
            p_event_id,
            p_machine_id,
            p_class_id,
            p_is_valid,
            p_student_id,
            p_detected_type,
            p_waste_category_code,
            p_category_source
        )
    loop
        insert into public.mission_processing_queue (event_id)
        values (v_result.event_id)
        on conflict on constraint mission_processing_queue_pkey do nothing;

        return query
        select
            v_result.deposit_id,
            v_result.event_id,
            v_result.waste_category_code,
            deposit.category_source,
            v_result.bonus_rate_applied,
            v_result.bonus_bincoins_awarded,
            v_result.points_awarded_student,
            v_result.points_awarded_class,
            v_result.created_at,
            v_result.was_replayed
        from public.deposits as deposit
        where deposit.id = v_result.deposit_id;
    end loop;
end;
$$;

comment on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text) is
    'Registra descarte e sua pendencia duravel de Missoes na mesma transacao. Uso exclusivo da Edge Function.';

revoke all on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text)
from public, anon, authenticated, service_role;

grant execute on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text)
to service_role;

create function public.calculate_mission_progress_v1(
    p_cycle_id uuid,
    p_student_id uuid,
    p_class_id uuid
)
returns table (
    progress bigint,
    achieved_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_cycle public.mission_cycles%rowtype;
begin
    select cycle.*
    into strict v_cycle
    from public.mission_cycles as cycle
    where cycle.id = p_cycle_id;

    if v_cycle.scope = 'STUDENT' then
        return query
        with ranked as (
            select
                deposit.created_at,
                row_number() over (
                    order by deposit.created_at, deposit.id
                ) as position
            from public.deposits as deposit
            where p_student_id is not null
              and deposit.student_id = p_student_id
              and deposit.is_valid
              and deposit.created_at >= v_cycle.starts_at
              and deposit.created_at < v_cycle.ends_at
        )
        select
            count(*)::bigint,
            min(ranked.created_at)
                filter (where ranked.position = v_cycle.target)
        from ranked;
    else
        return query
        with ranked as (
            select
                deposit.created_at,
                sum(deposit.points_awarded_class::bigint) over (
                    order by deposit.created_at, deposit.id
                    rows between unbounded preceding and current row
                ) as accumulated_xp
            from public.deposits as deposit
            where p_class_id is not null
              and deposit.class_id = p_class_id
              and deposit.is_valid
              and deposit.created_at >= v_cycle.starts_at
              and deposit.created_at < v_cycle.ends_at
        )
        select
            coalesce(max(ranked.accumulated_xp), 0::numeric)::bigint,
            min(ranked.created_at)
                filter (where ranked.accumulated_xp >= v_cycle.target)
        from ranked;
    end if;
end;
$$;

comment on function public.calculate_mission_progress_v1(uuid, uuid, uuid) is
    'Auxiliar interno que recalcula progresso e achieved_at a partir de deposits.created_at.';

revoke all on function public.calculate_mission_progress_v1(uuid, uuid, uuid)
from public, anon, authenticated, service_role;

create function public.process_mission_event_v1(p_event_id uuid)
returns table (
    was_processed boolean,
    was_already_processed boolean,
    completions_created integer,
    reward_applications_created integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_deposit public.deposits%rowtype;
    v_queue public.mission_processing_queue%rowtype;
    v_cycle public.mission_cycles%rowtype;
    v_recipient record;
    v_completion_id uuid;
    v_current_class_id uuid;
    v_locked_student_class_id uuid;
    v_candidate_cycle_ids uuid[] := array[]::uuid[];
    v_locked_cycle_ids uuid[] := array[]::uuid[];
    v_progress bigint;
    v_achieved_at timestamptz;
    v_materialized_at timestamptz;
    v_student_delta bigint;
    v_class_delta bigint;
    v_application_count integer := 0;
    v_completion_count integer := 0;
    v_completion_application_count integer;
    v_completion_bincoins_total bigint;
    v_completion_xp_total bigint;
    v_has_student_candidate boolean;
    v_has_class_bincoins boolean;
begin
    select queue.*
    into v_queue
    from public.mission_processing_queue as queue
    where queue.event_id = p_event_id
      and queue.processed_at is null
    for update skip locked;

    if not found then
        select queue.*
        into v_queue
        from public.mission_processing_queue as queue
        where queue.event_id = p_event_id;

        if not found then
            raise exception using
                errcode = 'P0002',
                message = 'Pendencia de Missoes nao encontrada para o event_id.';
        end if;

        return query
        select false, v_queue.processed_at is not null, 0, 0;
        return;
    end if;

    select deposit.*
    into strict v_deposit
    from public.deposits as deposit
    where deposit.event_id = p_event_id;

    if not v_deposit.is_valid then
        update public.mission_processing_queue as queue
        set processed_at = pg_catalog.clock_timestamp()
        where queue.event_id = p_event_id;

        return query select true, false, 0, 0;
        return;
    end if;

    if v_deposit.student_id is not null then
        select student.class_id
        into v_current_class_id
        from public.students as student
        join public.classes as current_class
          on current_class.id = student.class_id
         and current_class.school_id = student.school_id
        where student.id = v_deposit.student_id
          and student.school_id = v_deposit.school_id
          and student.status = 'ACTIVE';
    end if;

    -- Plano preliminar somente leitura. Ele determina quais locks economicos
    -- podem ser necessarios; o plano e recalculado depois dos locks.
    for v_cycle in
        select cycle.*
        from public.mission_cycles as cycle
        where cycle.school_id = v_deposit.school_id
          and cycle.starts_at <= v_deposit.created_at
          and v_deposit.created_at < cycle.ends_at
          and (
                cycle.scope = 'CLASS'
                or (
                    cycle.scope = 'STUDENT'
                    and v_deposit.student_id is not null
                    and v_current_class_id is not null
                )
              )
          and not exists (
              select 1
              from public.mission_completions as completion
              where completion.cycle_id = cycle.id
                and (
                    (cycle.scope = 'STUDENT' and completion.student_id = v_deposit.student_id)
                    or
                    (cycle.scope = 'CLASS' and completion.class_id = v_deposit.class_id)
                )
          )
        order by cycle.id
    loop
        select calculated.progress, calculated.achieved_at
        into v_progress, v_achieved_at
        from public.calculate_mission_progress_v1(
            v_cycle.id,
            v_deposit.student_id,
            v_deposit.class_id
        ) as calculated;

        if v_progress >= v_cycle.target then
            v_candidate_cycle_ids := array_append(
                v_candidate_cycle_ids,
                v_cycle.id
            );
        end if;
    end loop;

    if cardinality(v_candidate_cycle_ids) > 0 then
        select
            coalesce(bool_or(cycle.scope = 'STUDENT'), false),
            coalesce(
                bool_or(
                    cycle.scope = 'CLASS'
                    and cycle.reward_bincoins > 0
                ),
                false
            )
        into v_has_student_candidate, v_has_class_bincoins
        from public.mission_cycles as cycle
        where cycle.id = any(v_candidate_cycle_ids);

        -- Ordem deterministica aprovada: classes, students por UUID, ciclos.
        perform 1
        from public.classes as class_row
        where class_row.id = v_deposit.class_id
           or (
                v_has_student_candidate
                and class_row.id = v_current_class_id
              )
        order by class_row.id
        for update;

        perform 1
        from public.students as student
        where (
                v_has_student_candidate
                and student.id = v_deposit.student_id
              )
           or (
                v_has_class_bincoins
                and student.class_id = v_deposit.class_id
                and student.status = 'ACTIVE'
              )
        order by student.id
        for update;

        if v_has_student_candidate then
            select student.class_id
            into v_locked_student_class_id
            from public.students as student
            join public.classes as current_class
              on current_class.id = student.class_id
             and current_class.school_id = student.school_id
            where student.id = v_deposit.student_id
              and student.school_id = v_deposit.school_id
              and student.status = 'ACTIVE';

            if v_locked_student_class_id is distinct from v_current_class_id then
                raise exception using
                    errcode = '40001',
                    message = 'Vinculo atual do aluno mudou durante o processamento; tente novamente.';
            end if;
        end if;

        perform 1
        from public.mission_cycles as cycle
        where cycle.id = any(v_candidate_cycle_ids)
        order by cycle.id
        for update;

        -- Outro evento pode ter concluido um ciclo enquanto este worker
        -- aguardava. Recalcula o plano sob os locks antes de qualquer escrita.
        v_locked_cycle_ids := v_candidate_cycle_ids;
        v_candidate_cycle_ids := array[]::uuid[];

        for v_cycle in
            select cycle.*
            from public.mission_cycles as cycle
            where cycle.id = any(v_locked_cycle_ids)
              and cycle.school_id = v_deposit.school_id
              and cycle.starts_at <= v_deposit.created_at
              and v_deposit.created_at < cycle.ends_at
              and (
                    cycle.scope = 'CLASS'
                    or (
                        cycle.scope = 'STUDENT'
                        and v_deposit.student_id is not null
                        and v_locked_student_class_id is not null
                    )
                  )
              and not exists (
                  select 1
                  from public.mission_completions as completion
                  where completion.cycle_id = cycle.id
                    and (
                        (cycle.scope = 'STUDENT' and completion.student_id = v_deposit.student_id)
                        or
                        (cycle.scope = 'CLASS' and completion.class_id = v_deposit.class_id)
                    )
              )
            order by cycle.id
        loop
            select calculated.progress, calculated.achieved_at
            into v_progress, v_achieved_at
            from public.calculate_mission_progress_v1(
                v_cycle.id,
                v_deposit.student_id,
                v_deposit.class_id
            ) as calculated;

            if v_progress >= v_cycle.target then
                v_candidate_cycle_ids := array_append(
                    v_candidate_cycle_ids,
                    v_cycle.id
                );
            end if;
        end loop;
    end if;

    -- Preflight economico integral em bigint antes de qualquer completion,
    -- saldo, ledger ou auditoria.
    if cardinality(v_candidate_cycle_ids) > 0 then
        for v_recipient in
            select student.id, student.points_student_balance
            from public.students as student
            where (
                    student.id = v_deposit.student_id
                    and exists (
                        select 1
                        from public.mission_cycles as cycle
                        where cycle.id = any(v_candidate_cycle_ids)
                          and cycle.scope = 'STUDENT'
                          and cycle.reward_bincoins > 0
                    )
                  )
               or (
                    student.class_id = v_deposit.class_id
                    and student.status = 'ACTIVE'
                    and exists (
                        select 1
                        from public.mission_cycles as cycle
                        where cycle.id = any(v_candidate_cycle_ids)
                          and cycle.scope = 'CLASS'
                          and cycle.reward_bincoins > 0
                    )
                  )
            order by student.id
        loop
            select
                coalesce(sum(
                    case
                        when cycle.scope = 'STUDENT'
                             and v_recipient.id = v_deposit.student_id
                            then cycle.reward_bincoins::bigint
                        when cycle.scope = 'CLASS'
                             and exists (
                                 select 1
                                 from public.students as member
                                 where member.id = v_recipient.id
                                   and member.class_id = v_deposit.class_id
                                   and member.status = 'ACTIVE'
                             )
                            then cycle.reward_bincoins::bigint
                        else 0::bigint
                    end
                ), 0::bigint)
            into v_student_delta
            from public.mission_cycles as cycle
            where cycle.id = any(v_candidate_cycle_ids);

            if v_recipient.points_student_balance::bigint + v_student_delta
                > 2147483647::bigint
            then
                raise exception using
                    errcode = '22003',
                    message = 'Recompensa de Missao excede o saldo integer do aluno.';
            end if;
        end loop;

        for v_recipient in
            select class_row.id, class_row.points_class_balance
            from public.classes as class_row
            where class_row.id = v_deposit.class_id
               or class_row.id = v_locked_student_class_id
            order by class_row.id
        loop
            select
                coalesce(sum(
                    case
                        when cycle.scope = 'CLASS'
                             and v_recipient.id = v_deposit.class_id
                            then cycle.reward_xp::bigint
                        when cycle.scope = 'STUDENT'
                             and v_recipient.id = v_locked_student_class_id
                            then cycle.reward_xp::bigint
                        else 0::bigint
                    end
                ), 0::bigint)
            into v_class_delta
            from public.mission_cycles as cycle
            where cycle.id = any(v_candidate_cycle_ids);

            if v_recipient.points_class_balance::bigint + v_class_delta
                > 2147483647::bigint
            then
                raise exception using
                    errcode = '22003',
                    message = 'Recompensa de Missao excede o saldo integer da turma.';
            end if;
        end loop;
    end if;

    for v_cycle in
        select cycle.*
        from public.mission_cycles as cycle
        where cycle.id = any(v_candidate_cycle_ids)
        order by cycle.id
    loop
        select calculated.progress, calculated.achieved_at
        into v_progress, v_achieved_at
        from public.calculate_mission_progress_v1(
            v_cycle.id,
            v_deposit.student_id,
            v_deposit.class_id
        ) as calculated;

        v_materialized_at := pg_catalog.clock_timestamp();
        v_completion_id := null;

        insert into public.mission_completions (
            cycle_id,
            participant_scope,
            student_id,
            class_id,
            progress_at_completion,
            achieved_at,
            materialized_at
        )
        values (
            v_cycle.id,
            v_cycle.scope,
            case when v_cycle.scope = 'STUDENT' then v_deposit.student_id end,
            case when v_cycle.scope = 'CLASS' then v_deposit.class_id end,
            v_progress,
            v_achieved_at,
            v_materialized_at
        )
        on conflict do nothing
        returning id into v_completion_id;

        if v_completion_id is null then
            continue;
        end if;

        v_completion_count := v_completion_count + 1;
        v_completion_application_count := 0;
        v_completion_bincoins_total := 0;
        v_completion_xp_total := 0;

        if v_cycle.scope = 'STUDENT' then
            if v_cycle.reward_bincoins > 0 then
                insert into public.mission_reward_applications (
                    completion_id,
                    reward_type,
                    amount_applied,
                    recipient_student_id,
                    applied_at
                ) values (
                    v_completion_id,
                    'BINCOINS',
                    v_cycle.reward_bincoins,
                    v_deposit.student_id,
                    v_materialized_at
                )
                on conflict do nothing;

                if found then
                    update public.students as student
                    set
                        points_student_balance = (
                            student.points_student_balance::bigint
                            + v_cycle.reward_bincoins::bigint
                        )::integer,
                        updated_at = v_materialized_at
                    where student.id = v_deposit.student_id;

                    v_application_count := v_application_count + 1;
                    v_completion_application_count := v_completion_application_count + 1;
                    v_completion_bincoins_total :=
                        v_completion_bincoins_total + v_cycle.reward_bincoins;
                end if;
            end if;

            if v_cycle.reward_xp > 0 then
                insert into public.mission_reward_applications (
                    completion_id,
                    reward_type,
                    amount_applied,
                    recipient_class_id,
                    applied_at
                ) values (
                    v_completion_id,
                    'XP',
                    v_cycle.reward_xp,
                    v_locked_student_class_id,
                    v_materialized_at
                )
                on conflict do nothing;

                if found then
                    update public.classes as class_row
                    set
                        points_class_balance = (
                            class_row.points_class_balance::bigint
                            + v_cycle.reward_xp::bigint
                        )::integer,
                        updated_at = v_materialized_at
                    where class_row.id = v_locked_student_class_id;

                    v_application_count := v_application_count + 1;
                    v_completion_application_count := v_completion_application_count + 1;
                    v_completion_xp_total :=
                        v_completion_xp_total + v_cycle.reward_xp;
                end if;
            end if;
        else
            if v_cycle.reward_xp > 0 then
                insert into public.mission_reward_applications (
                    completion_id,
                    reward_type,
                    amount_applied,
                    recipient_class_id,
                    applied_at
                ) values (
                    v_completion_id,
                    'XP',
                    v_cycle.reward_xp,
                    v_deposit.class_id,
                    v_materialized_at
                )
                on conflict do nothing;

                if found then
                    update public.classes as class_row
                    set
                        points_class_balance = (
                            class_row.points_class_balance::bigint
                            + v_cycle.reward_xp::bigint
                        )::integer,
                        updated_at = v_materialized_at
                    where class_row.id = v_deposit.class_id;

                    v_application_count := v_application_count + 1;
                    v_completion_application_count := v_completion_application_count + 1;
                    v_completion_xp_total :=
                        v_completion_xp_total + v_cycle.reward_xp;
                end if;
            end if;

            if v_cycle.reward_bincoins > 0 then
                for v_recipient in
                    select student.id
                    from public.students as student
                    where student.class_id = v_deposit.class_id
                      and student.status = 'ACTIVE'
                    order by student.id
                loop
                    insert into public.mission_reward_applications (
                        completion_id,
                        reward_type,
                        amount_applied,
                        recipient_student_id,
                        applied_at
                    ) values (
                        v_completion_id,
                        'BINCOINS',
                        v_cycle.reward_bincoins,
                        v_recipient.id,
                        v_materialized_at
                    )
                    on conflict do nothing;

                    if found then
                        update public.students as student
                        set
                            points_student_balance = (
                                student.points_student_balance::bigint
                                + v_cycle.reward_bincoins::bigint
                            )::integer,
                            updated_at = v_materialized_at
                        where student.id = v_recipient.id;

                        v_application_count := v_application_count + 1;
                        v_completion_application_count := v_completion_application_count + 1;
                        v_completion_bincoins_total :=
                            v_completion_bincoins_total + v_cycle.reward_bincoins;
                    end if;
                end loop;
            end if;
        end if;

        insert into public.audit_logs (
            school_id,
            actor_type,
            actor_id,
            action,
            metadata
        ) values (
            v_deposit.school_id,
            'SYSTEM',
            null,
            'MISSION_COMPLETED_V1',
            pg_catalog.jsonb_build_object(
                'event_id', v_deposit.event_id,
                'completion_id', v_completion_id,
                'cycle_id', v_cycle.id,
                'participant_scope', v_cycle.scope,
                'participant_student_id',
                    case when v_cycle.scope = 'STUDENT' then v_deposit.student_id end,
                'participant_class_id',
                    case when v_cycle.scope = 'CLASS' then v_deposit.class_id end,
                'progress_at_completion', v_progress,
                'target', v_cycle.target,
                'achieved_at', v_achieved_at,
                'materialized_at', v_materialized_at,
                'reward_applications_count', v_completion_application_count,
                'bincoins_applied_total', v_completion_bincoins_total,
                'xp_applied_total', v_completion_xp_total
            )
        );
    end loop;

    update public.mission_processing_queue as queue
    set processed_at = pg_catalog.clock_timestamp()
    where queue.event_id = p_event_id;

    return query
    select true, false, v_completion_count, v_application_count;
end;
$$;

comment on function public.process_mission_event_v1(uuid) is
    'Processa atomicamente uma pendencia de Missoes por event_id, com progresso derivado e recompensas idempotentes.';

revoke all on function public.process_mission_event_v1(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.process_mission_event_v1(uuid)
to service_role;

commit;
