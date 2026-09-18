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

select extensions.ok(
    (
        select data_type = 'integer' and is_nullable = 'NO' and column_default = '0'
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'mission_processing_queue'
          and column_name = 'attempt_count'
    )
    and (
        select data_type = 'text' and is_nullable = 'YES'
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'mission_processing_queue'
          and column_name = 'last_error'
    )
    and (
        select data_type = 'timestamp with time zone' and is_nullable = 'YES'
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'mission_processing_queue'
          and column_name = 'next_attempt_at'
    ),
    'fila possui estado operacional minimo de retry'
);

select extensions.ok(
    to_regclass('public.idx_mission_processing_queue_retry_due') is not null,
    'indice parcial prepara busca futura por retries vencidos'
);

select extensions.ok(
    not has_function_privilege(
        'anon', 'public.record_mission_processing_failure_v1(uuid)', 'execute'
    )
    and not has_function_privilege(
        'authenticated', 'public.record_mission_processing_failure_v1(uuid)', 'execute'
    )
    and has_function_privilege(
        'service_role', 'public.record_mission_processing_failure_v1(uuid)', 'execute'
    )
    and not has_function_privilege(
        'service_role', 'public.process_mission_event_v1_core(uuid)', 'execute'
    ),
    'somente entradas server-side autorizadas ficam executaveis'
);

insert into public.schools (id, name)
values ('d1000000-0000-4000-8000-000000000001', 'Escola retry imediato');
insert into public.school_settings (school_id)
values ('d1000000-0000-4000-8000-000000000001');
insert into public.classes (id, school_id, segment, grade, name)
values ('d2000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001', 'TESTE', '1', 'Turma');
insert into public.machines (id, school_id, name, status)
values ('d3000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001', 'Totem', 'ONLINE');

select * from public.register_deposit_v1(
    'd4000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000001',
    false, null, 'invalido', null, null
);

select extensions.ok(
    (
        select attempt_count = 0
           and last_error is null
           and next_attempt_at is null
           and processed_at is null
        from public.mission_processing_queue
        where event_id = 'd4000000-0000-4000-8000-000000000001'
    ),
    'pendencia nova nasce sem falha operacional'
);

create temporary table first_failure as
select *, pg_catalog.clock_timestamp() as observed_at
from public.record_mission_processing_failure_v1(
    'd4000000-0000-4000-8000-000000000001'
);

select extensions.ok(
    (
        select attempt_count = 1
           and last_error = 'MISSION_PROCESSING_FAILED'
           and was_recorded
           and next_attempt_at between observed_at + interval '55 seconds'
                                   and observed_at + interval '65 seconds'
        from first_failure
    ),
    'primeira falha persiste codigo sanitizado e backoff aproximado de um minuto'
);

select extensions.ok(
    (
        select not result.was_processed
           and not result.was_already_processed
           and result.completions_created = 0
           and result.reward_applications_created = 0
        from public.process_mission_event_v1(
            'd4000000-0000-4000-8000-000000000001'
        ) as result
    )
    and (
        select processed_at is null
        from public.mission_processing_queue
        where event_id = 'd4000000-0000-4000-8000-000000000001'
    ),
    'entrada publica respeita next_attempt_at sem consumir a pendencia'
);

create temporary table second_failure as
select *, pg_catalog.clock_timestamp() as observed_at
from public.record_mission_processing_failure_v1(
    'd4000000-0000-4000-8000-000000000001'
);

select extensions.ok(
    (
        select attempt_count = 2
           and last_error = 'MISSION_PROCESSING_FAILED'
           and next_attempt_at between observed_at + interval '295 seconds'
                                   and observed_at + interval '305 seconds'
        from second_failure
    ),
    'segunda falha incrementa contador e aplica backoff aproximado de cinco minutos'
);

select extensions.ok(
    pg_temp.raises_state(
        $$update public.mission_processing_queue
          set last_error = 'secret SQL stack trace'
          where event_id = 'd4000000-0000-4000-8000-000000000001'$$,
        '23514'
    ),
    'constraint rejeita mensagem de erro bruta ou nao aprovada'
);

update public.mission_processing_queue
set next_attempt_at = pg_catalog.clock_timestamp()
where event_id = 'd4000000-0000-4000-8000-000000000001';

select extensions.ok(
    (
        select result.was_processed
           and not result.was_already_processed
        from public.process_mission_event_v1(
            'd4000000-0000-4000-8000-000000000001'
        ) as result
    ),
    'retry vencido reutiliza o mesmo processador autoritativo'
);

select extensions.ok(
    (
        select processed_at is not null
           and attempt_count = 2
           and last_error = 'MISSION_PROCESSING_FAILED'
        from public.mission_processing_queue
        where event_id = 'd4000000-0000-4000-8000-000000000001'
    ),
    'sucesso encerra pendencia e preserva historico operacional das falhas'
);

select extensions.ok(
    (
        select not was_recorded and attempt_count = 2
        from public.record_mission_processing_failure_v1(
            'd4000000-0000-4000-8000-000000000001'
        )
    ),
    'falha tardia concorrente nao reabre pendencia ja processada'
);

select * from public.register_deposit_v1(
    'd4000000-0000-4000-8000-000000000002',
    'd3000000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000001',
    false, null, 'invalido', null, null
);
select * from public.process_mission_event_v1(
    'd4000000-0000-4000-8000-000000000002'
);

select extensions.ok(
    (
        select processed_at is not null
           and attempt_count = 0
           and last_error is null
           and next_attempt_at is null
        from public.mission_processing_queue
        where event_id = 'd4000000-0000-4000-8000-000000000002'
    ),
    'processamento imediato bem-sucedido encerra pendencia sem criar retry'
);

select * from extensions.finish();
rollback;
