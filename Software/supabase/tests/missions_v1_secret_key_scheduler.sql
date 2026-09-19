begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.is(
    (
        select count(*)::integer
        from cron.job
        where jobname = 'bingo-missions-v1-recovery-every-minute'
    ),
    1,
    'migration 018 preserva exatamente um scheduler de recuperacao'
);

select extensions.is(
    (
        select schedule
        from cron.job
        where jobname = 'bingo-missions-v1-recovery-every-minute'
    ),
    '* * * * *',
    'migration 018 preserva a cadencia de um minuto'
);

select extensions.ok(
    (
        select command ilike '%/functions/v1/recover-missions-v1%'
           and command ilike '%bingo_missions_project_url%'
           and command ilike '%bingo_missions_recovery_secret_key%'
           and command ilike '%''apikey''%'
           and command not ilike '%''Authorization''%'
           and command not ilike '%bingo_missions_recovery_service_role_key%'
           and command not ilike '%process_mission_event_v1%'
           and command not ilike '%mission_completions%'
           and command not ilike '%mission_reward_applications%'
        from cron.job
        where jobname = 'bingo-missions-v1-recovery-every-minute'
    ),
    'scheduler usa somente apikey do novo secret do Vault e apenas aciona o recuperador'
);

select extensions.ok(
    (
        select command !~ 'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+'
           and command not ilike '%sb_secret_%'
           and command not ilike '%service_role=%'
        from cron.job
        where jobname = 'bingo-missions-v1-recovery-every-minute'
    ),
    'migration 018 nao persiste credencial real no comando agendado'
);

select * from extensions.finish();
rollback;
