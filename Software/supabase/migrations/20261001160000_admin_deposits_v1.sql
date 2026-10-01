-- Admin Descartes V1: leitura de eventos e snapshots historicos persistidos.
begin;
create function public.get_admin_deposits_v1()
returns table (
    deposit_id uuid, event_id uuid,
    school_id uuid, school_name text,
    machine_id uuid, machine_name text,
    class_id uuid, class_name text,
    student_id uuid, student_name text,
    is_valid boolean, detected_type text,
    waste_category_code text, category_source text,
    bonus_rate_applied numeric, bonus_bincoins_awarded integer,
    points_awarded_student integer, points_awarded_class integer,
    created_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
declare actor public.admins%rowtype;
begin
    select a.* into actor from public.admins a
    where a.auth_user_id = (select auth.uid());
    if not found or actor.status <> 'ACTIVE'
        or actor.role not in ('ADMIN_A', 'ADMIN_B', 'ADMIN_C')
        or (actor.role in ('ADMIN_B', 'ADMIN_C') and actor.school_id is null) then
        raise exception using errcode = '42501', message = 'ADMIN_DEPOSITS_ACCESS_DENIED';
    end if;
    return query
        select d.id, d.event_id,
            d.school_id, s.name,
            d.machine_id, m.name,
            d.class_id, c.name,
            d.student_id, st.name,
            d.is_valid, d.detected_type,
            wc.code, d.category_source,
            d.bonus_rate_applied, d.bonus_bincoins_awarded,
            d.points_awarded_student, d.points_awarded_class,
            d.created_at
        from public.deposits d
        join public.schools s on s.id = d.school_id
        join public.machines m on m.id = d.machine_id and m.school_id = d.school_id
        join public.classes c on c.id = d.class_id and c.school_id = d.school_id
        left join public.students st on st.id = d.student_id and st.school_id = d.school_id
        left join public.waste_categories wc on wc.id = d.waste_category_id
        where actor.role = 'ADMIN_A' or d.school_id = actor.school_id
        order by d.created_at desc, d.id desc;
end;
$$;
comment on function public.get_admin_deposits_v1() is
    'Leitura Admin ACTIVE: A global, B/C propria escola. Recompensas sao snapshots historicos de deposits, sem recalculo.';
revoke all on function public.get_admin_deposits_v1()
    from public, anon, authenticated, service_role;
grant execute on function public.get_admin_deposits_v1() to authenticated;
-- Nenhum grant/policy direto em deposits e nenhuma alteracao em register_deposit_v1.
commit;
