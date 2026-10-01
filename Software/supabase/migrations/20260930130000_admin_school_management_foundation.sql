begin;

alter table public.students
    add column registration text,
    add column email text,
    add constraint students_registration_normalized_check check (
        registration is null or (
            registration !~ '^[[:space:]]*$' and
            registration = regexp_replace(registration, '^[[:space:]]+|[[:space:]]+$', '', 'g')
        )
    ),
    add constraint students_email_nonblank_check check (email is null or email !~ '^[[:space:]]*$');
create unique index students_school_registration_unique
    on public.students (school_id, registration) where registration is not null;
comment on column public.students.registration is 'RA/matricula administrativa, unica por escola; NULL preserva alunos historicos. Case-sensitive, sem whitespace nas extremidades.';
comment on column public.students.email is 'Email administrativo/institucional; independente de Supabase Auth e sem vinculacao automatica.';

-- Fronteira interna: nunca conceder EXECUTE ao cliente. Toda operacao valida
-- ACTIVE no banco, mesmo que a sessao Angular tenha sido resolvida anteriormente.
create function public.require_school_admin_v1(p_write boolean)
returns table (admin_id uuid, school_id uuid, role text)
language plpgsql stable security definer set search_path = '' as $$
declare v_admin public.admins%rowtype;
begin
    if auth.uid() is null then
        raise exception using errcode = '42501', message = 'ADMIN_SCHOOL_ACCESS_DENIED';
    end if;
    select a.* into v_admin from public.admins a where a.auth_user_id = auth.uid();
    if not found or v_admin.status <> 'ACTIVE' or v_admin.school_id is null
        or v_admin.role not in ('ADMIN_B', 'ADMIN_C')
        or (p_write and v_admin.role <> 'ADMIN_B') then
        raise exception using errcode = '42501', message = 'ADMIN_SCHOOL_ACCESS_DENIED';
    end if;
    return query select v_admin.id, v_admin.school_id, v_admin.role;
end;
$$;

create function public.get_admin_students_v1()
returns table (student_id uuid, name text, email text, registration text,
    class_id uuid, class_name text, status text, points_student_balance integer,
    class_points_balance integer)
language plpgsql stable security definer set search_path = '' as $$
declare v_admin record;
begin
    select * into v_admin from public.require_school_admin_v1(false);
    return query select s.id, s.name, s.email, s.registration, s.class_id,
        c.name, s.status, s.points_student_balance, c.points_class_balance
        from public.students s join public.classes c on c.id = s.class_id
            and c.school_id = s.school_id
        where s.school_id = v_admin.school_id order by s.name, s.id;
end;
$$;

create function public.get_admin_classes_v1()
returns table (class_id uuid, segment text, grade text, name text,
    points_class_balance integer, student_count bigint)
language plpgsql stable security definer set search_path = '' as $$
declare v_admin record;
begin
    select * into v_admin from public.require_school_admin_v1(false);
    return query select c.id, c.segment, c.grade, c.name, c.points_class_balance,
        (select count(*) from public.students s where s.class_id = c.id and s.school_id = c.school_id)
        from public.classes c where c.school_id = v_admin.school_id order by c.name, c.id;
end;
$$;

create function public.create_admin_student_v1(p_name text, p_email text,
    p_registration text, p_class_id uuid, p_status text default 'ACTIVE')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_admin record; v_id uuid; v_constraint text;
begin
    select * into v_admin from public.require_school_admin_v1(true);
    p_name := regexp_replace(p_name, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    p_registration := regexp_replace(p_registration, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    p_email := regexp_replace(p_email, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    if p_name is null or p_name = '' or p_registration is null or p_registration = ''
        or p_email = '' or p_class_id is null or p_status is null or p_status not in ('ACTIVE', 'INACTIVE') then
        raise exception using errcode = '22023', message = 'ADMIN_STUDENT_INVALID_INPUT';
    end if;
    perform 1 from public.classes c where c.id = p_class_id and c.school_id = v_admin.school_id for share;
    if not found then
        raise exception using errcode = '42501', message = 'ADMIN_CLASS_ACCESS_DENIED';
    end if;
    insert into public.students (school_id, class_id, name, email, registration, status)
        values (v_admin.school_id, p_class_id, p_name, p_email, p_registration, p_status) returning id into v_id;
    insert into public.audit_logs (school_id, actor_type, actor_id, action, metadata)
        values (v_admin.school_id, 'ADMIN', v_admin.admin_id, 'ADMIN_STUDENT_CREATED_V1',
            jsonb_build_object('student_id', v_id, 'class_id', p_class_id, 'status', p_status));
    return v_id;
exception when unique_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint = 'students_school_registration_unique' then
        raise exception using errcode = '23505', message = 'ADMIN_REGISTRATION_CONFLICT';
    end if;
    raise;
end;
$$;

create function public.update_admin_student_v1(p_student_id uuid, p_name text,
    p_email text, p_registration text, p_class_id uuid, p_status text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_admin record; v_old public.students%rowtype; v_constraint text;
begin
    select * into v_admin from public.require_school_admin_v1(true);
    select s.* into v_old from public.students s
        where s.id = p_student_id and s.school_id = v_admin.school_id for update;
    if not found then
        raise exception using errcode = '42501', message = 'ADMIN_STUDENT_ACCESS_DENIED';
    end if;
    p_name := regexp_replace(p_name, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    p_registration := regexp_replace(p_registration, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    p_email := regexp_replace(p_email, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    if p_name is null or p_name = '' or p_registration is null or p_registration = ''
        or p_email = '' or p_class_id is null or p_status is null or p_status not in ('ACTIVE', 'INACTIVE') then
        raise exception using errcode = '22023', message = 'ADMIN_STUDENT_INVALID_INPUT';
    end if;
    perform 1 from public.classes c where c.id = p_class_id and c.school_id = v_admin.school_id for share;
    if not found then
        raise exception using errcode = '42501', message = 'ADMIN_CLASS_ACCESS_DENIED';
    end if;
    update public.students set name = p_name, email = p_email, registration = p_registration,
        class_id = p_class_id, status = p_status, updated_at = now() where id = v_old.id;
    insert into public.audit_logs (school_id, actor_type, actor_id, action, metadata)
        values (v_admin.school_id, 'ADMIN', v_admin.admin_id, 'ADMIN_STUDENT_UPDATED_V1',
            jsonb_build_object('student_id', v_old.id,
                'old', jsonb_build_object('name', v_old.name, 'email', v_old.email,
                    'registration', v_old.registration, 'class_id', v_old.class_id, 'status', v_old.status),
                'new', jsonb_build_object('name', p_name, 'email', p_email,
                    'registration', p_registration, 'class_id', p_class_id, 'status', p_status)));
    return v_old.id;
exception when unique_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint = 'students_school_registration_unique' then
        raise exception using errcode = '23505', message = 'ADMIN_REGISTRATION_CONFLICT';
    end if;
    raise;
end;
$$;

create function public.create_admin_class_v1(p_segment text, p_grade text, p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_admin record; v_id uuid;
begin
    select * into v_admin from public.require_school_admin_v1(true);
    p_segment := regexp_replace(p_segment, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    p_grade := regexp_replace(p_grade, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    p_name := regexp_replace(p_name, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    if p_segment is null or p_segment = '' or p_grade is null or p_grade = '' or p_name is null or p_name = '' then
        raise exception using errcode = '22023', message = 'ADMIN_CLASS_INVALID_INPUT';
    end if;
    insert into public.classes (school_id, segment, grade, name)
        values (v_admin.school_id, p_segment, p_grade, p_name) returning id into v_id;
    insert into public.audit_logs (school_id, actor_type, actor_id, action, metadata)
        values (v_admin.school_id, 'ADMIN', v_admin.admin_id, 'ADMIN_CLASS_CREATED_V1',
            jsonb_build_object('class_id', v_id, 'segment', p_segment, 'grade', p_grade, 'name', p_name));
    return v_id;
end;
$$;

create function public.update_admin_class_v1(p_class_id uuid, p_segment text, p_grade text, p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_admin record; v_old public.classes%rowtype;
begin
    select * into v_admin from public.require_school_admin_v1(true);
    select c.* into v_old from public.classes c
        where c.id = p_class_id and c.school_id = v_admin.school_id for update;
    if not found then
        raise exception using errcode = '42501', message = 'ADMIN_CLASS_ACCESS_DENIED';
    end if;
    p_segment := regexp_replace(p_segment, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    p_grade := regexp_replace(p_grade, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    p_name := regexp_replace(p_name, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    if p_segment is null or p_segment = '' or p_grade is null or p_grade = '' or p_name is null or p_name = '' then
        raise exception using errcode = '22023', message = 'ADMIN_CLASS_INVALID_INPUT';
    end if;
    update public.classes set segment = p_segment, grade = p_grade, name = p_name,
        updated_at = now() where id = v_old.id;
    insert into public.audit_logs (school_id, actor_type, actor_id, action, metadata)
        values (v_admin.school_id, 'ADMIN', v_admin.admin_id, 'ADMIN_CLASS_UPDATED_V1',
            jsonb_build_object('class_id', v_old.id,
                'old', jsonb_build_object('segment', v_old.segment, 'grade', v_old.grade, 'name', v_old.name),
                'new', jsonb_build_object('segment', p_segment, 'grade', p_grade, 'name', p_name)));
    return v_old.id;
end;
$$;

revoke all on function public.require_school_admin_v1(boolean) from public, anon, authenticated, service_role;
revoke all on function public.get_admin_students_v1() from public, anon, authenticated, service_role;
revoke all on function public.get_admin_classes_v1() from public, anon, authenticated, service_role;
revoke all on function public.create_admin_student_v1(text,text,text,uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.update_admin_student_v1(uuid,text,text,text,uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.create_admin_class_v1(text,text,text) from public, anon, authenticated, service_role;
revoke all on function public.update_admin_class_v1(uuid,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.get_admin_students_v1(), public.get_admin_classes_v1(),
    public.create_admin_student_v1(text,text,text,uuid,text),
    public.update_admin_student_v1(uuid,text,text,text,uuid,text),
    public.create_admin_class_v1(text,text,text), public.update_admin_class_v1(uuid,text,text,text) to authenticated;

-- Nenhuma policy/grant de tabela muda: Mobile continua restrito ao proprio aluno.
commit;
