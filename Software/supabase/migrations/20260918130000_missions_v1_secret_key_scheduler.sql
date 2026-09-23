-- BinGo V1
-- Migration: 20260918130000_missions_v1_secret_key_scheduler.sql
--
-- Migra a chamada agendada da Edge Function para a Secret API Key dedicada.
-- O estado active existente do job e preservado; a migration nao o reativa.

begin;

do $$
declare
    v_job_id bigint;
begin
    select jobid
    into strict v_job_id
    from cron.job
    where jobname = 'bingo-missions-v1-recovery-every-minute';

    perform cron.alter_job(
        job_id := v_job_id,
        schedule := '* * * * *',
        command := $cron$
        select net.http_post(
            url := secrets.project_url || '/functions/v1/recover-missions-v1',
            headers := pg_catalog.jsonb_build_object(
                'Content-Type', 'application/json',
                'apikey', secrets.secret_key
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
                    where name = 'bingo_missions_recovery_secret_key'
                ) as secret_key
            from vault.decrypted_secrets
            where name in (
                'bingo_missions_project_url',
                'bingo_missions_recovery_secret_key'
            )
        ) as secrets
        where secrets.project_url is not null
          and secrets.secret_key is not null
        $cron$
    );
end;
$$;

commit;
