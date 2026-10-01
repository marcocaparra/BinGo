-- Admin Totens V1: leitura de fotografia persistida, sem telemetria calculada.
begin;
create function public.get_admin_machines_v1()
returns table (
    machine_id uuid, school_id uuid, school_name text, name text, status text,
    firmware_version text, last_seen timestamptz,
    bin_full boolean, camera_ok boolean, net_ok boolean
)
language plpgsql stable security definer set search_path = '' as $$
declare actor public.admins%rowtype;
begin
    select a.* into actor from public.admins a
    where a.auth_user_id = (select auth.uid());
    if not found or actor.status <> 'ACTIVE'
        or actor.role not in ('ADMIN_A', 'ADMIN_B', 'ADMIN_C')
        or (actor.role in ('ADMIN_B', 'ADMIN_C') and actor.school_id is null) then
        raise exception using errcode = '42501', message = 'ADMIN_MACHINES_ACCESS_DENIED';
    end if;
    return query
        select m.id, m.school_id, s.name, m.name, m.status,
            m.firmware_version, m.last_seen, m.bin_full, m.camera_ok, m.net_ok
        from public.machines m join public.schools s on s.id = m.school_id
        where actor.role = 'ADMIN_A' or m.school_id = actor.school_id
        order by s.name, m.name, m.id;
end;
$$;
comment on function public.get_admin_machines_v1() is
    'Leitura Admin ACTIVE: A global, B/C propria escola. Campos persistidos, sem inferir heartbeat, conectividade ou disponibilidade operacional.';
revoke all on function public.get_admin_machines_v1()
    from public, anon, authenticated, service_role;
grant execute on function public.get_admin_machines_v1() to authenticated;
-- Nenhum grant/policy de tabela ou alteracao na autenticacao tecnica.
commit;
