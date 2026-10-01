-- Totem: narrow server-only reads. Machine authentication remains in the Edge.
-- No table grants, schema changes or browser policies are introduced.
create or replace function public.get_totem_context_v1(p_machine_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
    select jsonb_build_object(
        'school', jsonb_build_object('id', s.id, 'name', s.name),
        'machine', jsonb_build_object('id', m.id, 'name', m.name),
        'classes', coalesce((select jsonb_agg(jsonb_build_object(
            'id', c.id, 'name', c.name, 'segment', c.segment, 'grade', c.grade,
            'points_class_balance', c.points_class_balance) order by c.name, c.id)
            from public.classes c where c.school_id = m.school_id), '[]'::jsonb),
        'students', coalesce((select jsonb_agg(jsonb_build_object(
            'id', st.id, 'name', st.name, 'class_id', c.id, 'class_name', c.name,
            'status', st.status, 'points_student_balance', st.points_student_balance)
            order by st.name, st.id)
            from public.students st join public.classes c on c.id = st.class_id
                and c.school_id = st.school_id
            where st.school_id = m.school_id and st.status = 'ACTIVE'), '[]'::jsonb))
    from public.machines m join public.schools s on s.id = m.school_id
    where m.id = p_machine_id;
$$;

-- Only the PIN Edge needs this hash. No client role can execute this RPC or
-- SELECT pin_hash. is_activated is deliberately not a login condition.
create or replace function public.get_totem_student_pin_record_v1(
    p_machine_id uuid, p_class_id uuid, p_student_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
    select jsonb_build_object('pin_hash', st.pin_hash, 'student',
        jsonb_build_object('id', st.id, 'name', st.name,
            'class_id', c.id, 'class_name', c.name))
    from public.machines m join public.students st on st.school_id = m.school_id
    join public.classes c on c.id = st.class_id and c.school_id = m.school_id
    where m.id = p_machine_id and st.id = p_student_id
        and c.id = p_class_id and st.status = 'ACTIVE';
$$;

create or replace function public.get_totem_student_summary_v1(
    p_machine_id uuid, p_student_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
    select jsonb_build_object('student', jsonb_build_object(
        'id', st.id, 'name', st.name, 'class_id', c.id, 'class_name', c.name,
        'status', st.status, 'points_student_balance', st.points_student_balance),
        'stats', (select jsonb_build_object(
            'valid_deposits_count', count(*) filter (where d.is_valid),
            'invalid_deposits_count', count(*) filter (where not d.is_valid),
            'total_bins_generated', coalesce(sum(d.points_awarded_student)
                filter (where d.is_valid), 0))
            from public.deposits d where d.student_id = st.id and d.school_id = m.school_id),
        'recent_deposits', coalesce((select jsonb_agg(to_jsonb(recent)
            order by recent.created_at desc, recent.id desc) from (
            select d.id, d.event_id, d.is_valid, d.detected_type,
                wc.code as waste_category_code, d.category_source, d.bonus_rate_applied,
                d.bonus_bincoins_awarded, d.points_awarded_student,
                d.points_awarded_class, d.created_at
            from public.deposits d left join public.waste_categories wc on wc.id = d.waste_category_id
            where d.student_id = st.id and d.school_id = m.school_id
            order by d.created_at desc, d.id desc limit 5) recent), '[]'::jsonb))
    from public.machines m join public.students st on st.school_id = m.school_id
    join public.classes c on c.id = st.class_id and c.school_id = m.school_id
    where m.id = p_machine_id and st.id = p_student_id;
$$;

-- Preserve the legacy ranking's inclusion of INACTIVE students. UUID is the
-- final tie-breaker, after balance DESC and name ASC.
create or replace function public.get_totem_rankings_v1(p_machine_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
    select jsonb_build_object(
        'students', coalesce((select jsonb_agg(jsonb_build_object(
            'id', st.id, 'name', st.name, 'class_name', c.name,
            'points_student_balance', st.points_student_balance)
            order by st.points_student_balance desc, st.name, st.id)
            from public.students st join public.classes c on c.id = st.class_id
                and c.school_id = st.school_id
            where st.school_id = m.school_id), '[]'::jsonb),
        'classes', coalesce((select jsonb_agg(jsonb_build_object(
            'id', c.id, 'name', c.name, 'points_class_balance', c.points_class_balance)
            order by c.points_class_balance desc, c.name, c.id)
            from public.classes c where c.school_id = m.school_id), '[]'::jsonb))
    from public.machines m where m.id = p_machine_id;
$$;

revoke all on function public.get_totem_context_v1(uuid),
    public.get_totem_student_pin_record_v1(uuid, uuid, uuid),
    public.get_totem_student_summary_v1(uuid, uuid),
    public.get_totem_rankings_v1(uuid) from public, anon, authenticated;
grant execute on function public.get_totem_context_v1(uuid),
    public.get_totem_student_pin_record_v1(uuid, uuid, uuid),
    public.get_totem_student_summary_v1(uuid, uuid),
    public.get_totem_rankings_v1(uuid) to service_role;
