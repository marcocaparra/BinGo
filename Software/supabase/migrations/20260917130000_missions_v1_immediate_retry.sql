-- BinGo V1
-- Migration: 20260917130000_missions_v1_immediate_retry.sql
-- Executavelmente equivalente a database/migrations/015_missions_v1_immediate_retry.sql.

begin;

alter table public.mission_processing_queue
    add column attempt_count integer not null default 0,
    add column last_error text,
    add column next_attempt_at timestamptz,
    add constraint mission_processing_queue_attempt_count_check
        check (attempt_count >= 0),
    add constraint mission_processing_queue_last_error_check
        check (
            last_error is null
            or last_error = 'MISSION_PROCESSING_FAILED'
        ),
    add constraint mission_processing_queue_retry_state_check
        check (
            (
                attempt_count = 0
                and last_error is null
                and next_attempt_at is null
            )
            or
            (
                attempt_count > 0
                and last_error is not null
                and next_attempt_at is not null
            )
        ),
    add constraint mission_processing_queue_next_attempt_check
        check (
            next_attempt_at is null
            or next_attempt_at >= enqueued_at
        );

comment on column public.mission_processing_queue.attempt_count is
    'Quantidade de tentativas de processamento que falharam e foram registradas separadamente.';
comment on column public.mission_processing_queue.last_error is
    'Codigo operacional sanitizado; nunca contem mensagem bruta de excecao.';
comment on column public.mission_processing_queue.next_attempt_at is
    'Primeiro instante em que o recuperador futuro pode tentar novamente.';

create index idx_mission_processing_queue_retry_due
    on public.mission_processing_queue(next_attempt_at, enqueued_at, event_id)
    where processed_at is null;

alter function public.process_mission_event_v1(uuid)
    rename to process_mission_event_v1_core;

comment on function public.process_mission_event_v1_core(uuid) is
    'Nucleo economico interno, atomico e idempotente do processamento de Missoes V1.';

revoke all on function public.process_mission_event_v1_core(uuid)
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
    v_processed_at timestamptz;
    v_next_attempt_at timestamptz;
begin
    select queue.processed_at, queue.next_attempt_at
    into v_processed_at, v_next_attempt_at
    from public.mission_processing_queue as queue
    where queue.event_id = p_event_id;

    if found
       and v_processed_at is null
       and v_next_attempt_at is not null
       and v_next_attempt_at > pg_catalog.clock_timestamp()
    then
        return query select false, false, 0, 0;
        return;
    end if;

    return query
    select
        result.was_processed,
        result.was_already_processed,
        result.completions_created,
        result.reward_applications_created
    from public.process_mission_event_v1_core(p_event_id) as result;
end;
$$;

comment on function public.process_mission_event_v1(uuid) is
    'Entrada server-side que respeita backoff e delega ao nucleo economico idempotente.';

revoke all on function public.process_mission_event_v1(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.process_mission_event_v1(uuid)
to service_role;

create function public.record_mission_processing_failure_v1(p_event_id uuid)
returns table (
    attempt_count integer,
    last_error text,
    next_attempt_at timestamptz,
    was_recorded boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_queue public.mission_processing_queue%rowtype;
    v_attempt_count integer;
    v_now timestamptz := pg_catalog.clock_timestamp();
    v_next_attempt_at timestamptz;
begin
    select queue.*
    into v_queue
    from public.mission_processing_queue as queue
    where queue.event_id = p_event_id
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Pendencia de Missoes nao encontrada para o event_id.';
    end if;

    if v_queue.processed_at is not null then
        return query
        select
            v_queue.attempt_count,
            v_queue.last_error,
            v_queue.next_attempt_at,
            false;
        return;
    end if;

    v_attempt_count := least(
        v_queue.attempt_count::bigint + 1::bigint,
        2147483647::bigint
    )::integer;

    v_next_attempt_at := v_now + case
        when v_attempt_count = 1 then interval '1 minute'
        when v_attempt_count = 2 then interval '5 minutes'
        when v_attempt_count = 3 then interval '15 minutes'
        else interval '1 hour'
    end;

    update public.mission_processing_queue as queue
    set
        attempt_count = v_attempt_count,
        last_error = 'MISSION_PROCESSING_FAILED',
        next_attempt_at = v_next_attempt_at
    where queue.event_id = p_event_id;

    return query
    select
        v_attempt_count,
        'MISSION_PROCESSING_FAILED'::text,
        v_next_attempt_at,
        true;
end;
$$;

comment on function public.record_mission_processing_failure_v1(uuid) is
    'Registra em transacao separada uma falha sanitizada e agenda o backoff da pendencia.';

revoke all on function public.record_mission_processing_failure_v1(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.record_mission_processing_failure_v1(uuid)
to service_role;

commit;
