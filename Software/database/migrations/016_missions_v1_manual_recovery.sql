-- BinGo V1
-- Migration: 016_missions_v1_manual_recovery.sql
--
-- Disponibiliza uma operacao tecnica que seleciona e processa exatamente
-- uma pendencia vencida por transacao, permitindo orquestracao manual em lote.

begin;

create function public.recover_next_mission_event_v1()
returns table (
    event_id uuid,
    outcome text,
    completions_created integer,
    reward_applications_created integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_event_id uuid;
    v_result record;
begin
    select queue.event_id
    into v_event_id
    from public.mission_processing_queue as queue
    where queue.processed_at is null
      and queue.next_attempt_at <= pg_catalog.clock_timestamp()
    order by queue.next_attempt_at, queue.enqueued_at, queue.event_id
    for update skip locked
    limit 1;

    if not found then
        return;
    end if;

    begin
        select *
        into strict v_result
        from public.process_mission_event_v1(v_event_id);

        return query
        select
            v_event_id,
            'PROCESSED'::text,
            v_result.completions_created,
            v_result.reward_applications_created;
    exception when others then
        -- A excecao reverte somente o sub-bloco economico. O lock externo
        -- permanece e o estado operacional sanitizado e gravado pelo mesmo
        -- mecanismo usado pela tentativa imediata.
        perform 1
        from public.record_mission_processing_failure_v1(v_event_id);

        return query
        select v_event_id, 'FAILED'::text, 0, 0;
    end;
end;
$$;

comment on function public.recover_next_mission_event_v1() is
    'Processa em transacao propria uma pendencia vencida, com selecao concorrente via SKIP LOCKED.';

revoke all on function public.recover_next_mission_event_v1()
from public, anon, authenticated, service_role;

grant execute on function public.recover_next_mission_event_v1()
to service_role;

commit;
