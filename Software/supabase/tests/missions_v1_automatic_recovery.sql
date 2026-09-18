begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.ok(
    pg_catalog.pg_get_functiondef(
        'public.recover_next_mission_event_v1()'::regprocedure
    ) ilike '%queue.next_attempt_at is null%'
    and pg_catalog.pg_get_functiondef(
        'public.recover_next_mission_event_v1()'::regprocedure
    ) ilike '%queue.next_attempt_at <= pg_catalog.clock_timestamp()%'
    and pg_catalog.pg_get_functiondef(
        'public.recover_next_mission_event_v1()'::regprocedure
    ) ilike '%order by queue.next_attempt_at, queue.enqueued_at, queue.event_id%'
    and pg_catalog.pg_get_functiondef(
        'public.recover_next_mission_event_v1()'::regprocedure
    ) ilike '%for update skip locked%'
    and pg_catalog.pg_get_functiondef(
        'public.recover_next_mission_event_v1()'::regprocedure
    ) ilike '%public.process_mission_event_v1(v_event_id)%',
    'recuperador inclui pendencias nunca tentadas e preserva ordem e nucleo economico'
);

select extensions.is(
    (
        select count(*)::integer
        from cron.job
        where jobname = 'bingo-missions-v1-recovery-every-minute'
    ),
    1,
    'existe exatamente um scheduler de recuperacao de Missoes V1'
);

select extensions.is(
    (
        select schedule
        from cron.job
        where jobname = 'bingo-missions-v1-recovery-every-minute'
    ),
    '* * * * *',
    'scheduler executa uma vez por minuto'
);

select extensions.ok(
    (
        select command ilike '%/functions/v1/recover-missions-v1%'
           and command ilike '%from vault.decrypted_secrets%'
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
    'scheduler somente aciona o recuperador tecnico e obtem configuracao do Vault'
);

select extensions.ok(
    (
        select command !~ 'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+'
           and command not ilike '%sb_secret_%'
           and command not ilike '%service_role=%'
        from cron.job
        where jobname = 'bingo-missions-v1-recovery-every-minute'
    ),
    'nenhuma credencial real esta persistida no comando agendado'
);

select extensions.ok(
    has_function_privilege(
        'service_role', 'public.recover_next_mission_event_v1()', 'execute'
    )
    and not has_function_privilege(
        'anon', 'public.recover_next_mission_event_v1()', 'execute'
    )
    and not has_function_privilege(
        'authenticated', 'public.recover_next_mission_event_v1()', 'execute'
    ),
    'recuperador permanece restrito ao service_role'
);

select * from extensions.finish();
rollback;
