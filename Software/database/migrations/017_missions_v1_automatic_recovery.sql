-- BinGo V1
-- Migration: 017_missions_v1_automatic_recovery.sql
--
-- Inclui pendencias nunca tentadas na recuperacao e agenda a Edge Function
-- tecnica de recuperacao uma vez por minuto. URL e credencial sao lidas do
-- Supabase Vault; nenhum segredo e persistido nesta migration.

begin;

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

create or replace function public.recover_next_mission_event_v1()
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
      and (
          queue.next_attempt_at is null
          or queue.next_attempt_at <= pg_catalog.clock_timestamp()
      )
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
        perform 1
        from public.record_mission_processing_failure_v1(v_event_id);

        return query
        select v_event_id, 'FAILED'::text, 0, 0;
    end;
end;
$$;

comment on function public.recover_next_mission_event_v1() is
    'Processa em transacao propria uma pendencia vencida ou nunca tentada, com selecao concorrente via SKIP LOCKED.';

revoke all on function public.recover_next_mission_event_v1()
from public, anon, authenticated, service_role;

grant execute on function public.recover_next_mission_event_v1()
to service_role;

select cron.schedule(
    'bingo-missions-v1-recovery-every-minute',
    '* * * * *',
    $cron$
    select net.http_post(
        url := secrets.project_url || '/functions/v1/recover-missions-v1',
        headers := pg_catalog.jsonb_build_object(
            'Content-Type', 'application/json',
            'apikey', secrets.service_role_key,
            'Authorization', 'Bearer ' || secrets.service_role_key
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 55000
    )
    from (
        select
            max(decrypted_secret) filter (
                where name = 'bingo_missions_project_url'
            ) as project_url,
            max(decrypted_secret) filter (
                where name = 'bingo_missions_recovery_service_role_key'
            ) as service_role_key
        from vault.decrypted_secrets
        where name in (
            'bingo_missions_project_url',
            'bingo_missions_recovery_service_role_key'
        )
    ) as secrets
    where secrets.project_url is not null
      and secrets.service_role_key is not null
    $cron$
);

commit;
