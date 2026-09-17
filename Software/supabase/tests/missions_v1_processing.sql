begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

create function pg_temp.raises_state(command text, expected_state text)
returns boolean language plpgsql as $$
begin
    execute command;
    return false;
exception when others then
    return sqlstate = expected_state;
end;
$$;

select extensions.has_table('public', 'mission_processing_queue', 'fila duravel existe');
select extensions.has_function('public', 'process_mission_event_v1', array['uuid'], 'processador por event_id existe');
select extensions.ok(
    (select relrowsecurity from pg_catalog.pg_class where oid = 'public.mission_processing_queue'::regclass),
    'fila possui RLS'
);
select extensions.ok(
    not has_table_privilege('anon', 'public.mission_processing_queue', 'select')
    and not has_table_privilege('authenticated', 'public.mission_processing_queue', 'select')
    and not has_table_privilege('service_role', 'public.mission_processing_queue', 'select'),
    'fila nao possui acesso direto pelos papeis de API'
);
select extensions.ok(
    not has_function_privilege('anon', 'public.process_mission_event_v1(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.process_mission_event_v1(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.process_mission_event_v1(uuid)', 'execute'),
    'somente service_role executa o processador'
);

insert into public.schools (id, name)
values ('c1000000-0000-4000-8000-000000000001', 'Escola processamento');
insert into public.school_settings (school_id)
values ('c1000000-0000-4000-8000-000000000001');
insert into public.classes (id, school_id, segment, grade, name)
values
    ('c2000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'TESTE', '1', 'Principal'),
    ('c2000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000001', 'TESTE', '2', 'Anonima'),
    ('c2000000-0000-4000-8000-000000000003', 'c1000000-0000-4000-8000-000000000001', 'TESTE', '3', 'Retry'),
    ('c2000000-0000-4000-8000-000000000004', 'c1000000-0000-4000-8000-000000000001', 'TESTE', '4', 'Overflow');
insert into public.students (
    id, school_id, class_id, name, status, is_activated, points_student_balance
)
values
    ('c3000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000001', 'Principal', 'ACTIVE', false, 0),
    ('c3000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000001', 'Colega ativo', 'ACTIVE', false, 0),
    ('c3000000-0000-4000-8000-000000000003', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000001', 'Colega inativo', 'INACTIVE', true, 0),
    ('c3000000-0000-4000-8000-000000000004', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000002', 'Membro anonima', 'ACTIVE', false, 0),
    ('c3000000-0000-4000-8000-000000000005', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000003', 'Historico', 'ACTIVE', false, 0),
    ('c3000000-0000-4000-8000-000000000006', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000004', 'Overflow', 'ACTIVE', false, 2147483637);
insert into public.machines (id, school_id, name, status)
values ('c4000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'Totem', 'ONLINE');

insert into public.mission_definitions (
    id, code, title, scope, metric, recurrence, target, reward_bincoins, reward_xp
)
values
    ('c5000000-0000-4000-8000-000000000001', 'PROC_STUDENT_BOTH', 'Student ambas', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 100, 200),
    ('c5000000-0000-4000-8000-000000000002', 'PROC_STUDENT_XP', 'Student XP', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 0, 300),
    ('c5000000-0000-4000-8000-000000000003', 'PROC_CLASS_BOTH', 'Class ambas', 'CLASS', 'CLASS_XP_EARNED', 'MONTHLY', 1900, 50, 400),
    ('c5000000-0000-4000-8000-000000000004', 'PROC_CLASS_ANON', 'Class anonima', 'CLASS', 'CLASS_XP_EARNED', 'MONTHLY', 1900, 70, 0),
    ('c5000000-0000-4000-8000-000000000005', 'PROC_STUDENT_HISTORY', 'Student historica', 'STUDENT', 'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 90, 0),
    ('c5000000-0000-4000-8000-000000000006', 'PROC_CLASS_RETRY', 'Class retry', 'CLASS', 'CLASS_XP_EARNED', 'MONTHLY', 1900, 0, 100),
    ('c5000000-0000-4000-8000-000000000007', 'PROC_CLASS_OVERFLOW', 'Class overflow', 'CLASS', 'CLASS_XP_EARNED', 'MONTHLY', 1900, 20, 0);

with bounds as (
    select date_trunc('month', pg_catalog.now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo' as active_start
)
insert into public.mission_cycles (
    id, definition_id, school_id, starts_at, ends_at, timezone,
    scope, metric, recurrence, target, reward_bincoins, reward_xp
)
select cycle.id, cycle.definition_id, 'c1000000-0000-4000-8000-000000000001',
       cycle.starts_at, cycle.ends_at, 'America/Sao_Paulo', cycle.scope,
       cycle.metric, 'MONTHLY', cycle.target, cycle.reward_bincoins, cycle.reward_xp
from bounds
cross join lateral (
    values
        ('c6000000-0000-4000-8000-000000000001'::uuid, 'c5000000-0000-4000-8000-000000000001'::uuid, bounds.active_start, bounds.active_start + interval '1 month', 'STUDENT'::text, 'VALID_DEPOSIT_COUNT'::text, 1::bigint, 100, 200),
        ('c6000000-0000-4000-8000-000000000002'::uuid, 'c5000000-0000-4000-8000-000000000002'::uuid, bounds.active_start, bounds.active_start + interval '1 month', 'STUDENT'::text, 'VALID_DEPOSIT_COUNT'::text, 1::bigint, 0, 300),
        ('c6000000-0000-4000-8000-000000000003'::uuid, 'c5000000-0000-4000-8000-000000000003'::uuid, bounds.active_start, bounds.active_start + interval '1 month', 'CLASS'::text, 'CLASS_XP_EARNED'::text, 1900::bigint, 50, 400),
        ('c6000000-0000-4000-8000-000000000005'::uuid, 'c5000000-0000-4000-8000-000000000005'::uuid, bounds.active_start - interval '1 month', bounds.active_start, 'STUDENT'::text, 'VALID_DEPOSIT_COUNT'::text, 1::bigint, 90, 0)
) as cycle(id, definition_id, starts_at, ends_at, scope, metric, target, reward_bincoins, reward_xp);

-- Se a escrita da outbox falhar, o proprio descarte e seus efeitos normais
-- tambem voltam: nao existe deposito persistido sem pendencia duravel.
create function pg_temp.fail_queue_insert() returns trigger language plpgsql as $$
begin
    if new.event_id = 'c7000000-0000-4000-8000-000000000000' then
        raise exception using errcode = 'P0001', message = 'falha de outbox injetada';
    end if;
    return new;
end;
$$;
create trigger test_fail_queue_insert before insert on public.mission_processing_queue
for each row execute function pg_temp.fail_queue_insert();
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.register_deposit_v1(
            'c7000000-0000-4000-8000-000000000000',
            'c4000000-0000-4000-8000-000000000001',
            'c2000000-0000-4000-8000-000000000001', true,
            'c3000000-0000-4000-8000-000000000001',
            'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
        )$$,
        'P0001'
    ), 'falha ao criar pendencia aborta a transacao de registro'
);
select extensions.ok(
    not exists (select 1 from public.deposits where event_id = 'c7000000-0000-4000-8000-000000000000')
    and not exists (select 1 from public.mission_processing_queue where event_id = 'c7000000-0000-4000-8000-000000000000')
    and (select points_student_balance = 0 from public.students where id = 'c3000000-0000-4000-8000-000000000001')
    and (select points_class_balance = 0 from public.classes where id = 'c2000000-0000-4000-8000-000000000001')
    and not exists (select 1 from public.audit_logs where metadata ->> 'event_id' = 'c7000000-0000-4000-8000-000000000000'),
    'falha de outbox nao deixa deposito, saldo, audit ou pendencia parcial'
);
drop trigger test_fail_queue_insert on public.mission_processing_queue;

select * from public.register_deposit_v1(
    'c7000000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000001', true,
    'c3000000-0000-4000-8000-000000000001', 'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
select extensions.is(
    (select count(*)::integer from public.mission_processing_queue where event_id = 'c7000000-0000-4000-8000-000000000001' and processed_at is null),
    1, 'descarte persistido cria pendencia atomica'
);
select * from public.register_deposit_v1(
    'c7000000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000001', true,
    'c3000000-0000-4000-8000-000000000001', 'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
select extensions.is(
    (select count(*)::integer from public.mission_processing_queue where event_id = 'c7000000-0000-4000-8000-000000000001'),
    1, 'replay nao duplica pendencia'
);

select extensions.ok(
    (select result.was_processed and not result.was_already_processed
       and result.completions_created = 3 and result.reward_applications_created = 6
     from public.process_mission_event_v1('c7000000-0000-4000-8000-000000000001') as result),
    'evento identificado conclui duas STUDENT e uma CLASS atomicamente'
);
select extensions.ok(
    (select points_student_balance = 950 from public.students where id = 'c3000000-0000-4000-8000-000000000001')
    and (select points_student_balance = 50 from public.students where id = 'c3000000-0000-4000-8000-000000000002')
    and (select points_student_balance = 0 from public.students where id = 'c3000000-0000-4000-8000-000000000003'),
    'BinCoins usam aluno STUDENT e membros ACTIVE atuais da CLASS'
);
select extensions.is(
    (select points_class_balance from public.classes where id = 'c2000000-0000-4000-8000-000000000001'),
    2800, 'XP STUDENT e CLASS usa a turma destinataria correta'
);
select extensions.is(
    (select count(*)::integer from public.mission_reward_applications),
    6, 'ledger contem somente os seis efeitos positivos efetivamente aplicados'
);
select extensions.ok(
    not exists (select 1 from public.mission_reward_applications where amount_applied <= 0),
    'reward zero nao cria ledger de valor zero'
);
select extensions.is(
    (select count(*)::integer from public.audit_logs where action = 'MISSION_COMPLETED_V1'
      and actor_type = 'SYSTEM' and actor_id is null
      and metadata ->> 'event_id' = 'c7000000-0000-4000-8000-000000000001'),
    3, 'auditoria agregada cria uma linha SYSTEM por completion'
);
select extensions.ok(
    not exists (
        select 1 from public.audit_logs where action = 'MISSION_COMPLETED_V1'
        and not (metadata ? 'completion_id' and metadata ? 'cycle_id'
          and metadata ? 'participant_scope' and metadata ? 'progress_at_completion'
          and metadata ? 'target' and metadata ? 'achieved_at'
          and metadata ? 'materialized_at' and metadata ? 'reward_applications_count'
          and metadata ? 'bincoins_applied_total' and metadata ? 'xp_applied_total')
    ), 'audit possui metadata suficiente para reconciliacao'
);

create temporary table first_result as
select (select count(*) from public.mission_completions) completions,
       (select count(*) from public.mission_reward_applications) applications,
       (select count(*) from public.audit_logs where action = 'MISSION_COMPLETED_V1') audits,
       (select points_student_balance from public.students where id = 'c3000000-0000-4000-8000-000000000001') student_balance,
       (select points_class_balance from public.classes where id = 'c2000000-0000-4000-8000-000000000001') class_balance;
select extensions.ok(
    (select not result.was_processed and result.was_already_processed
       and result.completions_created = 0 and result.reward_applications_created = 0
     from public.process_mission_event_v1('c7000000-0000-4000-8000-000000000001') result),
    'retry de pendencia processada e idempotente'
);
select extensions.ok(
    (select count(*) from public.mission_completions) = (select completions from first_result)
    and (select count(*) from public.mission_reward_applications) = (select applications from first_result)
    and (select count(*) from public.audit_logs where action = 'MISSION_COMPLETED_V1') = (select audits from first_result)
    and (select points_student_balance from public.students where id = 'c3000000-0000-4000-8000-000000000001') = (select student_balance from first_result)
    and (select points_class_balance from public.classes where id = 'c2000000-0000-4000-8000-000000000001') = (select class_balance from first_result),
    'retry nao duplica completion, ledger, audit ou saldo'
);

-- A recompensa XP de STUDENT resolve a turma atual na materializacao, nao a
-- class_id historica do deposito.
insert into public.students (id, school_id, class_id, name, status, is_activated)
values ('c3000000-0000-4000-8000-000000000007', 'c1000000-0000-4000-8000-000000000001',
        'c2000000-0000-4000-8000-000000000001', 'Transferido', 'ACTIVE', false);
select * from public.register_deposit_v1(
    'c7000000-0000-4000-8000-000000000008', 'c4000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000001', true,
    'c3000000-0000-4000-8000-000000000007', 'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
update public.students set class_id = 'c2000000-0000-4000-8000-000000000002'
where id = 'c3000000-0000-4000-8000-000000000007';
select * from public.process_mission_event_v1('c7000000-0000-4000-8000-000000000008');
select extensions.ok(
    exists (
        select 1
        from public.mission_reward_applications application
        join public.mission_completions completion on completion.id = application.completion_id
        where completion.cycle_id = 'c6000000-0000-4000-8000-000000000001'
          and completion.student_id = 'c3000000-0000-4000-8000-000000000007'
          and application.reward_type = 'XP'
          and application.recipient_class_id = 'c2000000-0000-4000-8000-000000000002'
    )
    and not exists (
        select 1
        from public.mission_reward_applications application
        join public.mission_completions completion on completion.id = application.completion_id
        where completion.student_id = 'c3000000-0000-4000-8000-000000000007'
          and application.reward_type = 'XP'
          and application.recipient_class_id = 'c2000000-0000-4000-8000-000000000001'
    ), 'XP STUDENT usa a turma atual e ledger congela o destinatario'
);

-- Um novo evento faz o progresso ultrapassar o target, sem nova recompensa.
select * from public.register_deposit_v1(
    'c7000000-0000-4000-8000-000000000002', 'c4000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000001', true,
    'c3000000-0000-4000-8000-000000000001', 'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
create temporary table before_above_target as
select (select count(*) from public.mission_completions) completions,
       (select count(*) from public.mission_reward_applications) applications,
       (select points_student_balance from public.students where id = 'c3000000-0000-4000-8000-000000000001') student_balance,
       (select points_class_balance from public.classes where id = 'c2000000-0000-4000-8000-000000000001') class_balance;
select * from public.process_mission_event_v1('c7000000-0000-4000-8000-000000000002');
select extensions.ok(
    (select count(*) from public.mission_completions) = (select completions from before_above_target)
    and (select count(*) from public.mission_reward_applications) = (select applications from before_above_target)
    and (select points_student_balance from public.students where id = 'c3000000-0000-4000-8000-000000000001') = (select student_balance from before_above_target)
    and (select points_class_balance from public.classes where id = 'c2000000-0000-4000-8000-000000000001') = (select class_balance from before_above_target),
    'progresso acima da meta nao concede segunda recompensa'
);

-- Invalido deixa pendencia, mas o processador a encerra sem efeito economico.
select * from public.register_deposit_v1(
    'c7000000-0000-4000-8000-000000000003', 'c4000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000001', false,
    'c3000000-0000-4000-8000-000000000001', 'invalido', null, null
);
create temporary table before_invalid as
select (select count(*) from public.mission_completions) completions,
       (select count(*) from public.mission_reward_applications) applications,
       (select count(*) from public.audit_logs where action = 'MISSION_COMPLETED_V1') audits;
select * from public.process_mission_event_v1('c7000000-0000-4000-8000-000000000003');
select extensions.ok(
    (select processed_at is not null from public.mission_processing_queue where event_id = 'c7000000-0000-4000-8000-000000000003')
    and (select count(*) from public.mission_completions) = (select completions from before_invalid)
    and (select count(*) from public.mission_reward_applications) = (select applications from before_invalid)
    and (select count(*) from public.audit_logs where action = 'MISSION_COMPLETED_V1') = (select audits from before_invalid),
    'descarte invalido nao produz efeito e so entao encerra pendencia'
);

-- Anonimo pode completar apenas a missao CLASS de sua turma historica.
with bounds as (
    select date_trunc('month', pg_catalog.now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo' active_start
)
insert into public.mission_cycles (
    id, definition_id, school_id, starts_at, ends_at, timezone,
    scope, metric, recurrence, target, reward_bincoins, reward_xp
)
select 'c6000000-0000-4000-8000-000000000004', 'c5000000-0000-4000-8000-000000000004',
       'c1000000-0000-4000-8000-000000000001', bounds.active_start,
       bounds.active_start + interval '1 month', 'America/Sao_Paulo',
       'CLASS', 'CLASS_XP_EARNED', 'MONTHLY', 1900, 70, 0
from bounds;

select * from public.register_deposit_v1(
    'c7000000-0000-4000-8000-000000000004', 'c4000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000002', true,
    null, 'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
select * from public.process_mission_event_v1('c7000000-0000-4000-8000-000000000004');
select extensions.ok(
    exists (select 1 from public.mission_completions
            where cycle_id = 'c6000000-0000-4000-8000-000000000004'
              and participant_scope = 'CLASS'
              and class_id = 'c2000000-0000-4000-8000-000000000002')
    and not exists (select 1 from public.mission_completions
                    where participant_scope = 'STUDENT' and student_id is null)
    and (select points_student_balance = 120 from public.students where id = 'c3000000-0000-4000-8000-000000000004'),
    'valido anonimo afeta somente CLASS e premia membro ACTIVE atual'
);

-- O timestamp persistido do deposito, e nao o instante do worker, seleciona o ciclo.
select * from public.register_deposit_v1(
    'c7000000-0000-4000-8000-000000000005', 'c4000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000003', true,
    'c3000000-0000-4000-8000-000000000005', 'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
with bounds as (
    select date_trunc('month', pg_catalog.now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo' active_start
)
update public.deposits set created_at = bounds.active_start - interval '1 day'
from bounds where event_id = 'c7000000-0000-4000-8000-000000000005';
select * from public.process_mission_event_v1('c7000000-0000-4000-8000-000000000005');
select extensions.ok(
    exists (select 1 from public.mission_completions
            where cycle_id = 'c6000000-0000-4000-8000-000000000005'
              and student_id = 'c3000000-0000-4000-8000-000000000005')
    and not exists (select 1 from public.mission_completions
                    where cycle_id in ('c6000000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000002')
                      and student_id = 'c3000000-0000-4000-8000-000000000005'),
    'deposit.created_at seleciona ciclo encerrado e permite materializacao tardia'
);

-- Falha injetada no audit ocorre depois de completion/ledger/saldo; a chamada
-- inteira deve voltar e deixar a pendencia disponivel para retry.
with bounds as (
    select date_trunc('month', pg_catalog.now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo' active_start
)
insert into public.mission_cycles (
    id, definition_id, school_id, starts_at, ends_at, timezone,
    scope, metric, recurrence, target, reward_bincoins, reward_xp
)
select 'c6000000-0000-4000-8000-000000000006', 'c5000000-0000-4000-8000-000000000006',
       'c1000000-0000-4000-8000-000000000001', bounds.active_start,
       bounds.active_start + interval '1 month', 'America/Sao_Paulo',
       'CLASS', 'CLASS_XP_EARNED', 'MONTHLY', 1900, 0, 100
from bounds;

select * from public.register_deposit_v1(
    'c7000000-0000-4000-8000-000000000006', 'c4000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000003', true,
    null, 'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
create function pg_temp.fail_mission_audit() returns trigger language plpgsql as $$
begin
    if new.action = 'MISSION_COMPLETED_V1'
       and new.metadata ->> 'event_id' = 'c7000000-0000-4000-8000-000000000006' then
        raise exception using errcode = 'P0001', message = 'falha de auditoria injetada';
    end if;
    return new;
end;
$$;
create trigger test_fail_mission_audit before insert on public.audit_logs
for each row execute function pg_temp.fail_mission_audit();
create temporary table before_failure as
select (select count(*) from public.mission_completions) completions,
       (select count(*) from public.mission_reward_applications) applications,
       (select points_class_balance from public.classes where id = 'c2000000-0000-4000-8000-000000000003') class_balance;
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.process_mission_event_v1('c7000000-0000-4000-8000-000000000006')$$,
        'P0001'
    ), 'falha posterior as escritas propaga erro economico'
);
select extensions.ok(
    (select count(*) from public.mission_completions) = (select completions from before_failure)
    and (select count(*) from public.mission_reward_applications) = (select applications from before_failure)
    and (select points_class_balance from public.classes where id = 'c2000000-0000-4000-8000-000000000003') = (select class_balance from before_failure)
    and (select processed_at is null from public.mission_processing_queue where event_id = 'c7000000-0000-4000-8000-000000000006'),
    'falha faz rollback integral e nao marca pendencia'
);
drop trigger test_fail_mission_audit on public.audit_logs;
create temporary table retry_result as
select * from public.process_mission_event_v1('c7000000-0000-4000-8000-000000000006');
select extensions.ok(
    (select result.was_processed and result.completions_created = 3
     from retry_result result)
    and (select processed_at is not null from public.mission_processing_queue where event_id = 'c7000000-0000-4000-8000-000000000006'),
    'retry posterior conclui e marca pendencia somente no sucesso'
);

-- Um destinatario sem espaco integer impede todo o evento antes das escritas.
with bounds as (
    select date_trunc('month', pg_catalog.now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo' active_start
)
insert into public.mission_cycles (
    id, definition_id, school_id, starts_at, ends_at, timezone,
    scope, metric, recurrence, target, reward_bincoins, reward_xp
)
select 'c6000000-0000-4000-8000-000000000007', 'c5000000-0000-4000-8000-000000000007',
       'c1000000-0000-4000-8000-000000000001', bounds.active_start,
       bounds.active_start + interval '1 month', 'America/Sao_Paulo',
       'CLASS', 'CLASS_XP_EARNED', 'MONTHLY', 1900, 20, 0
from bounds;

select * from public.register_deposit_v1(
    'c7000000-0000-4000-8000-000000000007', 'c4000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000004', true,
    null, 'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
);
create temporary table before_overflow as
select (select count(*) from public.mission_completions) completions,
       (select count(*) from public.mission_reward_applications) applications,
       (select points_student_balance from public.students where id = 'c3000000-0000-4000-8000-000000000006') student_balance;
select extensions.ok(
    pg_temp.raises_state(
        $$select * from public.process_mission_event_v1('c7000000-0000-4000-8000-000000000007')$$,
        '22003'
    ), 'overflow de um destinatario aborta o event_id'
);
select extensions.ok(
    (select count(*) from public.mission_completions) = (select completions from before_overflow)
    and (select count(*) from public.mission_reward_applications) = (select applications from before_overflow)
    and (select points_student_balance from public.students where id = 'c3000000-0000-4000-8000-000000000006') = (select student_balance from before_overflow)
    and (select processed_at is null from public.mission_processing_queue where event_id = 'c7000000-0000-4000-8000-000000000007'),
    'overflow nao deixa efeito parcial e preserva pendencia'
);

select * from extensions.finish();
rollback;
