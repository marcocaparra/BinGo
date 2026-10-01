begin;

create table public.class_change_requests (
    id uuid primary key,
    school_id uuid not null references public.schools(id) on delete restrict,
    student_id uuid not null references public.students(id) on delete restrict,
    source_class_id uuid not null references public.classes(id) on delete restrict,
    destination_class_id uuid not null references public.classes(id) on delete restrict,
    requested_by_admin_id uuid not null references public.admins(id) on delete restrict,
    status text not null default 'PENDING',
    resolved_by_admin_id uuid references public.admins(id) on delete restrict,
    created_at timestamptz not null default now(),
    resolved_at timestamptz,
    constraint class_change_requests_classes_check check (source_class_id <> destination_class_id),
    constraint class_change_requests_status_check check (status in ('PENDING','APPROVED','REJECTED','CANCELED')),
    constraint class_change_requests_resolution_check check (
        (status = 'PENDING' and resolved_by_admin_id is null and resolved_at is null)
        or (status <> 'PENDING' and resolved_by_admin_id is not null and resolved_at is not null)
    )
);
create index class_change_requests_school_created_idx on public.class_change_requests(school_id, created_at desc, id);
create index class_change_requests_author_created_idx on public.class_change_requests(requested_by_admin_id, created_at desc, id);
create index class_change_requests_student_idx on public.class_change_requests(student_id);
alter table public.class_change_requests enable row level security;
revoke all on table public.class_change_requests from public, anon, authenticated, service_role;
comment on table public.class_change_requests is 'Solicitacoes C decididas por B. Historico preservado; stale e derivado da turma atual, nunca status persistido.';

create function public.get_class_change_requests_v1()
returns table (request_id uuid, student_id uuid, student_name text, registration text,
    source_class_id uuid, source_class_name text, destination_class_id uuid, destination_class_name text,
    current_class_id uuid, current_class_name text, status text, is_stale boolean,
    requested_by_admin_id uuid, requested_by_admin_name text, created_at timestamptz,
    resolved_by_admin_id uuid, resolved_by_admin_name text, resolved_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare v_admin record;
begin
    select * into v_admin from public.require_school_admin_v1(false);
    return query select r.id, s.id, s.name, s.registration,
        src.id, src.name, dst.id, dst.name, cur.id, cur.name,
        r.status, r.status = 'PENDING' and s.class_id <> r.source_class_id,
        author.id, author.name, r.created_at, resolver.id, resolver.name, r.resolved_at
        from public.class_change_requests r
        join public.students s on s.id = r.student_id and s.school_id = r.school_id
        join public.classes src on src.id = r.source_class_id and src.school_id = r.school_id
        join public.classes dst on dst.id = r.destination_class_id and dst.school_id = r.school_id
        join public.classes cur on cur.id = s.class_id and cur.school_id = r.school_id
        join public.admins author on author.id = r.requested_by_admin_id
        left join public.admins resolver on resolver.id = r.resolved_by_admin_id
        where r.school_id = v_admin.school_id
            and (v_admin.role = 'ADMIN_B' or r.requested_by_admin_id = v_admin.admin_id)
        order by r.created_at desc, r.id;
end;
$$;

create function public.create_class_change_request_v1(p_request_id uuid, p_student_id uuid, p_destination_class_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_admin record; v_existing public.class_change_requests%rowtype; v_source uuid;
begin
    select * into v_admin from public.require_school_admin_v1(false);
    if v_admin.role <> 'ADMIN_C' then
        raise exception using errcode = '42501', message = 'CLASS_CHANGE_ACCESS_DENIED';
    end if;
    if p_request_id is null or p_student_id is null or p_destination_class_id is null then
        raise exception using errcode = '22023', message = 'CLASS_CHANGE_INVALID_INPUT';
    end if;
    -- Serializa o UUID inclusive antes da existencia da linha. Colisoes de hash
    -- apenas serializam UUIDs distintos, sem comprometer identidade/unicidade.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text, 25));
    select r.* into v_existing from public.class_change_requests r where r.id = p_request_id for update;
    if found then
        if v_existing.school_id <> v_admin.school_id or v_existing.requested_by_admin_id <> v_admin.admin_id
            or v_existing.student_id <> p_student_id or v_existing.destination_class_id <> p_destination_class_id then
            raise exception using errcode = '23505', message = 'CLASS_CHANGE_REQUEST_ID_CONFLICT';
        end if;
        -- Origem foi capturada no primeiro envio, nao e payload de replay.
        return v_existing.id;
    end if;
    select s.class_id into v_source from public.students s
        where s.id = p_student_id and s.school_id = v_admin.school_id for update;
    if not found then
        raise exception using errcode = '42501', message = 'CLASS_CHANGE_ACCESS_DENIED';
    end if;
    perform 1 from public.classes c where c.id = v_source and c.school_id = v_admin.school_id for share;
    if not found then raise exception using errcode = '42501', message = 'CLASS_CHANGE_ACCESS_DENIED'; end if;
    perform 1 from public.classes c where c.id = p_destination_class_id and c.school_id = v_admin.school_id for share;
    if not found then raise exception using errcode = '42501', message = 'CLASS_CHANGE_ACCESS_DENIED'; end if;
    if v_source = p_destination_class_id then
        raise exception using errcode = '22023', message = 'CLASS_CHANGE_SAME_CLASS';
    end if;
    insert into public.class_change_requests(id,school_id,student_id,source_class_id,destination_class_id,requested_by_admin_id)
        values(p_request_id,v_admin.school_id,p_student_id,v_source,p_destination_class_id,v_admin.admin_id);
    insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
        values(v_admin.school_id,'ADMIN',v_admin.admin_id,'CLASS_CHANGE_REQUEST_CREATED_V1',
            jsonb_build_object('request_id',p_request_id,'student_id',p_student_id,
                'source_class_id',v_source,'destination_class_id',p_destination_class_id,'status','PENDING'));
    return p_request_id;
end;
$$;

-- Interno: wrappers abaixo fecham o contrato; nenhum EXECUTE para clientes.
create function public.resolve_class_change_request_v1(p_request_id uuid, p_status text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_admin record; v_request public.class_change_requests%rowtype; v_current uuid;
begin
    select * into v_admin from public.require_school_admin_v1(false);
    if p_status not in ('APPROVED','REJECTED','CANCELED') or p_status is null or p_request_id is null then
        raise exception using errcode = '22023', message = 'CLASS_CHANGE_INVALID_INPUT';
    end if;
    if (p_status = 'CANCELED' and v_admin.role <> 'ADMIN_C')
        or (p_status <> 'CANCELED' and v_admin.role <> 'ADMIN_B') then
        raise exception using errcode = '42501', message = 'CLASS_CHANGE_ACCESS_DENIED';
    end if;
    select r.* into v_request from public.class_change_requests r
        where r.id = p_request_id and r.school_id = v_admin.school_id for update;
    if not found or (p_status = 'CANCELED' and v_request.requested_by_admin_id <> v_admin.admin_id) then
        raise exception using errcode = '42501', message = 'CLASS_CHANGE_ACCESS_DENIED';
    end if;
    if v_request.status = p_status then return v_request.id; end if;
    if v_request.status <> 'PENDING' then
        raise exception using errcode = 'P0001', message = 'CLASS_CHANGE_DECISION_CONFLICT';
    end if;
    -- Ordem de locks: request -> aluno. Mesmo lock de aluno usado pelo update
    -- direto B em 024; nenhuma decisao pode aprovar com uma origem ja superada.
    select s.class_id into v_current from public.students s
        where s.id = v_request.student_id and s.school_id = v_admin.school_id for update;
    if not found then raise exception using errcode = '42501', message = 'CLASS_CHANGE_ACCESS_DENIED'; end if;
    if p_status = 'APPROVED' then
        if v_current <> v_request.source_class_id then
            raise exception using errcode = 'P0001', message = 'CLASS_CHANGE_REQUEST_STALE';
        end if;
        perform 1 from public.classes c where c.id = v_request.destination_class_id and c.school_id = v_admin.school_id for share;
        if not found then raise exception using errcode = '42501', message = 'CLASS_CHANGE_ACCESS_DENIED'; end if;
        -- Somente a turma atual; saldos/credenciais/timestamps e historicos intactos.
        update public.students set class_id = v_request.destination_class_id where id = v_request.student_id;
    end if;
    update public.class_change_requests set status = p_status,
        resolved_by_admin_id = v_admin.admin_id, resolved_at = now() where id = v_request.id;
    insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
        values(v_admin.school_id,'ADMIN',v_admin.admin_id,'CLASS_CHANGE_REQUEST_' || p_status || '_V1',
            jsonb_build_object('request_id',v_request.id,'student_id',v_request.student_id,
                'source_class_id',v_request.source_class_id,'destination_class_id',v_request.destination_class_id,
                'old_class_id',v_current,'new_class_id',case when p_status = 'APPROVED' then v_request.destination_class_id else v_current end,
                'old_status','PENDING','new_status',p_status));
    return v_request.id;
end;
$$;

create function public.approve_class_change_request_v1(p_request_id uuid)
returns uuid language sql security definer set search_path = '' as $$
    select public.resolve_class_change_request_v1(p_request_id,'APPROVED');
$$;
create function public.reject_class_change_request_v1(p_request_id uuid)
returns uuid language sql security definer set search_path = '' as $$
    select public.resolve_class_change_request_v1(p_request_id,'REJECTED');
$$;
create function public.cancel_class_change_request_v1(p_request_id uuid)
returns uuid language sql security definer set search_path = '' as $$
    select public.resolve_class_change_request_v1(p_request_id,'CANCELED');
$$;

revoke all on function public.resolve_class_change_request_v1(uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.get_class_change_requests_v1() from public, anon, authenticated, service_role;
revoke all on function public.create_class_change_request_v1(uuid,uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function public.approve_class_change_request_v1(uuid) from public, anon, authenticated, service_role;
revoke all on function public.reject_class_change_request_v1(uuid) from public, anon, authenticated, service_role;
revoke all on function public.cancel_class_change_request_v1(uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_class_change_requests_v1(), public.create_class_change_request_v1(uuid,uuid,uuid),
    public.approve_class_change_request_v1(uuid), public.reject_class_change_request_v1(uuid),
    public.cancel_class_change_request_v1(uuid) to authenticated;
commit;
