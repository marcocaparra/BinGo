begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

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
    'somente service_role pode executar o recuperador tecnico'
);

insert into public.schools (id, name)
values ('e1000000-0000-4000-8000-000000000001', 'Escola recuperacao manual');
insert into public.school_settings (school_id)
values ('e1000000-0000-4000-8000-000000000001');
insert into public.classes (id, school_id, segment, grade, name)
values (
    'e2000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000001',
    'TESTE', '1', 'Turma'
);
insert into public.students (id, school_id, class_id, name, status)
values (
    'e3000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    'Aluno', 'ACTIVE'
);
insert into public.machines (id, school_id, name, status)
values (
    'e4000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000001',
    'Totem', 'ONLINE'
);
insert into public.mission_definitions (
    id, code, title, scope, metric, recurrence, target,
    reward_bincoins, reward_xp
) values (
    'e5000000-0000-4000-8000-000000000001',
    'MANUAL_RECOVERY_STUDENT', 'Recuperacao manual', 'STUDENT',
    'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 100, 0
);
with bounds as (
    select
        date_trunc('month', pg_catalog.now() at time zone 'America/Sao_Paulo')
            at time zone 'America/Sao_Paulo' as starts_at
)
insert into public.mission_cycles (
    id, definition_id, school_id, starts_at, ends_at, timezone,
    scope, metric, recurrence, target, reward_bincoins, reward_xp
)
select
    'e6000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000001',
    bounds.starts_at, bounds.starts_at + interval '1 month',
    'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY',
    1, 100, 0
from bounds;

-- Uma pendencia vencida elegivel, uma futura e uma ja processada.
select * from public.register_deposit_v1(
    'e7000000-0000-4000-8000-000000000001',
    'e4000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    true, 'e3000000-0000-4000-8000-000000000001',
    'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
select * from public.record_mission_processing_failure_v1(
    'e7000000-0000-4000-8000-000000000001'
);
update public.mission_processing_queue
set enqueued_at = pg_catalog.clock_timestamp() - interval '3 minutes',
    next_attempt_at = pg_catalog.clock_timestamp() - interval '3 minutes'
where event_id = 'e7000000-0000-4000-8000-000000000001';

select * from public.register_deposit_v1(
    'e7000000-0000-4000-8000-000000000002',
    'e4000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    false, null, 'invalido', null, null
);
select * from public.record_mission_processing_failure_v1(
    'e7000000-0000-4000-8000-000000000002'
);

select * from public.register_deposit_v1(
    'e7000000-0000-4000-8000-000000000003',
    'e4000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    false, null, 'invalido', null, null
);
select * from public.process_mission_event_v1(
    'e7000000-0000-4000-8000-000000000003'
);

create temporary table recovered_due as
select * from public.recover_next_mission_event_v1();

select extensions.ok(
    (select event_id = 'e7000000-0000-4000-8000-000000000001'
         and outcome = 'PROCESSED'
         and completions_created = 1
         and reward_applications_created = 1
     from recovered_due),
    'pendencia vencida e selecionada e processada'
);

select extensions.ok(
    (select processed_at is not null
     from public.mission_processing_queue
     where event_id = 'e7000000-0000-4000-8000-000000000003')
    and (select processed_at is null and next_attempt_at > pg_catalog.clock_timestamp()
         from public.mission_processing_queue
         where event_id = 'e7000000-0000-4000-8000-000000000002'),
    'pendencia processada e pendencia futura nao sao selecionadas'
);

create temporary table economic_snapshot as
select
    (select count(*) from public.mission_completions
     where cycle_id = 'e6000000-0000-4000-8000-000000000001') as completions,
    (select count(*) from public.mission_reward_applications as application
     join public.mission_completions as completion
       on completion.id = application.completion_id
     where completion.cycle_id = 'e6000000-0000-4000-8000-000000000001') as applications,
    (select count(*) from public.audit_logs
     where action = 'MISSION_COMPLETED_V1'
       and metadata ->> 'event_id' = 'e7000000-0000-4000-8000-000000000001') as audits,
    (select points_student_balance from public.students
     where id = 'e3000000-0000-4000-8000-000000000001') as student_balance;

select extensions.ok(
    not exists (select 1 from public.recover_next_mission_event_v1())
    and (select count(*) from public.mission_completions
         where cycle_id = 'e6000000-0000-4000-8000-000000000001') =
        (select completions from economic_snapshot)
    and (select count(*) from public.mission_reward_applications as application
         join public.mission_completions as completion
           on completion.id = application.completion_id
         where completion.cycle_id = 'e6000000-0000-4000-8000-000000000001') =
        (select applications from economic_snapshot)
    and (select count(*) from public.audit_logs
         where action = 'MISSION_COMPLETED_V1'
           and metadata ->> 'event_id' = 'e7000000-0000-4000-8000-000000000001') =
        (select audits from economic_snapshot)
    and (select points_student_balance from public.students
         where id = 'e3000000-0000-4000-8000-000000000001') =
        (select student_balance from economic_snapshot),
    'execucao repetida nao duplica completion, recompensa, auditoria ou saldo'
);

-- Uma pendencia nunca tentada representa o crash antes da tentativa imediata
-- e precisa ser recuperavel sem depender de registro previo de falha.
select * from public.register_deposit_v1(
    'e7000000-0000-4000-8000-000000000004',
    'e4000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    false, null, 'invalido', null, null
);
create temporary table recovered_never_attempted as
select * from public.recover_next_mission_event_v1();
select extensions.ok(
    (select event_id = 'e7000000-0000-4000-8000-000000000004'
         and outcome = 'PROCESSED'
     from recovered_never_attempted)
    and (select processed_at is not null and next_attempt_at is null
         from public.mission_processing_queue
         where event_id = 'e7000000-0000-4000-8000-000000000004'),
    'pendencia nunca tentada e recuperada imediatamente apos crash simulado'
);

-- Duas pendencias vencidas sao consumidas em transacoes independentes.
select * from public.register_deposit_v1(
    'e7000000-0000-4000-8000-000000000005',
    'e4000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    false, null, 'invalido', null, null
);
select * from public.register_deposit_v1(
    'e7000000-0000-4000-8000-000000000006',
    'e4000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    false, null, 'invalido', null, null
);
select * from public.record_mission_processing_failure_v1('e7000000-0000-4000-8000-000000000005');
select * from public.record_mission_processing_failure_v1('e7000000-0000-4000-8000-000000000006');
update public.mission_processing_queue
set enqueued_at = pg_catalog.clock_timestamp() - interval '2 minutes',
    next_attempt_at = pg_catalog.clock_timestamp() - interval '2 minutes'
where event_id in (
    'e7000000-0000-4000-8000-000000000005',
    'e7000000-0000-4000-8000-000000000006'
);
create temporary table multiple_results as
select 1 as call_number, recovered.* from public.recover_next_mission_event_v1() as recovered
union all
select 2, recovered.* from public.recover_next_mission_event_v1() as recovered;
select extensions.ok(
    (select count(*) = 2 and bool_and(outcome = 'PROCESSED') from multiple_results)
    and (select count(*) = 2 from public.mission_processing_queue
         where event_id in (
             'e7000000-0000-4000-8000-000000000005',
             'e7000000-0000-4000-8000-000000000006'
         ) and processed_at is not null),
    'multiplas pendencias vencidas sao processadas uma por chamada'
);

-- Uma falha economica e capturada, recebe backoff e nao bloqueia o proximo.
select * from public.register_deposit_v1(
    'e7000000-0000-4000-8000-000000000007',
    'e4000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    false, null, 'invalido', null, null
);
select * from public.register_deposit_v1(
    'e7000000-0000-4000-8000-000000000008',
    'e4000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001',
    false, null, 'invalido', null, null
);
select * from public.record_mission_processing_failure_v1('e7000000-0000-4000-8000-000000000007');
select * from public.record_mission_processing_failure_v1('e7000000-0000-4000-8000-000000000008');
update public.mission_processing_queue
set enqueued_at = case event_id
    when 'e7000000-0000-4000-8000-000000000007'::uuid
        then pg_catalog.clock_timestamp() - interval '3 minutes'
    else pg_catalog.clock_timestamp() - interval '2 minutes'
end,
    next_attempt_at = case event_id
    when 'e7000000-0000-4000-8000-000000000007'::uuid
        then pg_catalog.clock_timestamp() - interval '3 minutes'
    else pg_catalog.clock_timestamp() - interval '2 minutes'
end
where event_id in (
    'e7000000-0000-4000-8000-000000000007',
    'e7000000-0000-4000-8000-000000000008'
);
create function pg_temp.fail_first_recovery() returns trigger language plpgsql as $$
begin
    if new.event_id = 'e7000000-0000-4000-8000-000000000007'::uuid then
        raise exception using errcode = 'P0001', message = 'erro interno sensivel';
    end if;
    return new;
end;
$$;
create trigger test_fail_first_recovery
before update of processed_at on public.mission_processing_queue
for each row execute function pg_temp.fail_first_recovery();

create temporary table failed_result as
select * from public.recover_next_mission_event_v1();
create temporary table following_result as
select * from public.recover_next_mission_event_v1();

select extensions.ok(
    (select event_id = 'e7000000-0000-4000-8000-000000000007'
         and outcome = 'FAILED' from failed_result)
    and (select processed_at is null
             and attempt_count = 2
             and last_error = 'MISSION_PROCESSING_FAILED'
             and next_attempt_at > pg_catalog.clock_timestamp()
         from public.mission_processing_queue
         where event_id = 'e7000000-0000-4000-8000-000000000007'),
    'falha usa retry sanitizado e agenda novo backoff'
);
select extensions.ok(
    (select event_id = 'e7000000-0000-4000-8000-000000000008'
         and outcome = 'PROCESSED' from following_result)
    and (select processed_at is not null
         from public.mission_processing_queue
         where event_id = 'e7000000-0000-4000-8000-000000000008'),
    'falha de um event_id nao bloqueia o seguinte'
);

select extensions.ok(
    pg_get_functiondef(
        'public.recover_next_mission_event_v1()'::regprocedure
    ) ilike '%for update skip locked%'
    and pg_get_functiondef(
        'public.recover_next_mission_event_v1()'::regprocedure
    ) ilike '%public.process_mission_event_v1(v_event_id)%'
    and pg_get_functiondef(
        'public.recover_next_mission_event_v1()'::regprocedure
    ) ilike '%public.record_mission_processing_failure_v1(v_event_id)%',
    'recuperador usa SKIP LOCKED e reutiliza processamento e retry existentes'
);

select * from extensions.finish();
rollback;
