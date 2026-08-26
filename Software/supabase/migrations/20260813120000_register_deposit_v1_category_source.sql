-- BinGo V1
-- Migration: 006_register_deposit_v1_category_source.sql
--
-- Este arquivo deve permanecer funcionalmente equivalente a
-- database/migrations/006_register_deposit_v1_category_source.sql.

alter function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text)
    rename to register_deposit_v1_core;

comment on function public.register_deposit_v1_core(uuid, uuid, uuid, boolean, uuid, text, text, text) is
    'Implementacao interna preservada da RPC atomica de descarte V1.';

revoke all on function public.register_deposit_v1_core(uuid, uuid, uuid, boolean, uuid, text, text, text)
    from public, anon, authenticated, service_role;

create function public.register_deposit_v1(
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
        return query
        select
            v_result.deposit_id,
            v_result.event_id,
            v_result.waste_category_code,
            d.category_source,
            v_result.bonus_rate_applied,
            v_result.bonus_bincoins_awarded,
            v_result.points_awarded_student,
            v_result.points_awarded_class,
            v_result.created_at,
            v_result.was_replayed
        from public.deposits as d
        where d.id = v_result.deposit_id;
    end loop;
end;
$$;

comment on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text) is
    'Registra descarte, recompensa, saldos e auditoria atomicamente e retorna a fotografia persistida. Uso exclusivo da Edge Function.';

revoke all on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text)
    from public;
revoke all on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text)
    from anon, authenticated;
grant execute on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text)
    to service_role;
