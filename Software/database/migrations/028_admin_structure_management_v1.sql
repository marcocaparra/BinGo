-- 028: estrutura administrativa real; identidade de dominio sem provisionar Auth.
begin;
create table public.admin_structure_creation_receipts (
    entity_kind text not null check (entity_kind in ('SCHOOL','ADMIN')),
    entity_id uuid not null,
    created_by_admin_id uuid not null references public.admins(id) on delete restrict,
    payload jsonb not null,
    created_at timestamptz not null default now(),
    primary key(entity_kind,entity_id)
);
alter table public.admin_structure_creation_receipts enable row level security;
revoke all on public.admin_structure_creation_receipts from public,anon,authenticated,service_role;
comment on table public.admin_structure_creation_receipts is
 'Recibos privados imutaveis da intencao de criacao. Nao adicionam atributos de dominio a schools nem vinculo Auth a admins.';

-- VOLATILE: nas mutations a leitura ocorre DEPOIS do lock e ve o ator atualizado.
create function public.require_admin_structure_actor_v1(p_global boolean)
returns table(admin_id uuid,role text,school_id uuid)
language plpgsql security definer set search_path='' as $$
begin
 return query select a.id,a.role,a.school_id from public.admins a
 where a.auth_user_id=auth.uid() and a.status='ACTIVE'
 and (a.role='ADMIN_A' or (not p_global and a.role='ADMIN_B'));
 if not found then raise exception using errcode='42501',message='ADMIN_STRUCTURE_ACCESS_DENIED'; end if;
end; $$;

create function public.get_admin_schools_v1()
returns table(school_id uuid,name text,student_count bigint,class_count bigint,admin_count bigint,machine_count bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 perform * from public.require_admin_structure_actor_v1(true);
 return query select s.id,s.name,
 (select count(*) from public.students x where x.school_id=s.id),
 (select count(*) from public.classes x where x.school_id=s.id),
 (select count(*) from public.admins x where x.school_id=s.id),
 (select count(*) from public.machines x where x.school_id=s.id)
 from public.schools s order by s.name,s.id;
end; $$;

create function public.create_admin_school_v1(p_school_id uuid,p_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare a record; receipt public.admin_structure_creation_receipts%rowtype;
begin
 select * into a from public.require_admin_structure_actor_v1(true);
 p_name:=regexp_replace(p_name,'^[[:space:]]+|[[:space:]]+$','','g');
 if p_school_id is null or p_name is null or p_name='' then
  raise exception using errcode='22023',message='ADMIN_SCHOOL_INVALID_INPUT'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('school:'||p_school_id::text,28));
 select r.* into receipt from public.admin_structure_creation_receipts r
 where r.entity_kind='SCHOOL' and r.entity_id=p_school_id;
 if found then
  if receipt.created_by_admin_id<>a.admin_id or receipt.payload<>jsonb_build_object('name',p_name) then
   raise exception using errcode='23505',message='ADMIN_SCHOOL_ID_CONFLICT'; end if;
  return p_school_id;
 end if;
 if exists(select 1 from public.schools s where s.id=p_school_id) then
  raise exception using errcode='23505',message='ADMIN_SCHOOL_ID_CONFLICT'; end if;
 insert into public.schools(id,name) values(p_school_id,p_name);
 insert into public.admin_structure_creation_receipts(entity_kind,entity_id,created_by_admin_id,payload)
 values('SCHOOL',p_school_id,a.admin_id,jsonb_build_object('name',p_name));
 insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
 values(null,'ADMIN',a.admin_id,'ADMIN_SCHOOL_CREATED_V1',jsonb_build_object('school_id',p_school_id,'name',p_name));
 return p_school_id;
end; $$;

create function public.get_managed_admins_v1()
returns table(admin_id uuid,name text,email text,role text,school_id uuid,school_name text,status text,access_linked boolean)
language plpgsql stable security definer set search_path='' as $$
declare a record;
begin
 select * into a from public.require_admin_structure_actor_v1(false);
 return query select x.id,x.name,x.email,x.role,x.school_id,s.name,x.status,x.auth_user_id is not null
 from public.admins x left join public.schools s on s.id=x.school_id
 where a.role='ADMIN_A' or (x.role='ADMIN_C' and x.school_id=a.school_id)
 order by x.name,x.id;
end; $$;

create function public.create_managed_admin_v1(p_admin_id uuid,p_name text,p_email text,
 p_role text,p_school_id uuid,p_status text)
returns uuid language plpgsql security definer set search_path='' as $$
declare a record; scope uuid; payload jsonb; receipt public.admin_structure_creation_receipts%rowtype;
begin
 -- Mesmo lock para todas as mutations de contas: ordem lock -> ator -> alvo.
 -- Nunca confiar no ACTIVE lido antes de aguardar uma inativacao concorrente.
 perform pg_catalog.pg_advisory_xact_lock(28001,1);
 select * into a from public.require_admin_structure_actor_v1(false);
 -- Row lock tambem detecta snapshot antigo em REPEATABLE READ (40001).
 perform 1 from public.admins x where x.id=a.admin_id and x.status='ACTIVE' for update;
 if not found then raise exception using errcode='42501',message='ADMIN_STRUCTURE_ACCESS_DENIED'; end if;
 p_name:=regexp_replace(p_name,'^[[:space:]]+|[[:space:]]+$','','g');
 p_email:=regexp_replace(p_email,'^[[:space:]]+|[[:space:]]+$','','g');
 if p_admin_id is null or p_name is null or p_name='' or p_email is null
 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+$'
 or p_role is null or p_role not in ('ADMIN_A','ADMIN_B','ADMIN_C')
 or p_status is null or p_status not in ('ACTIVE','INACTIVE') then
  raise exception using errcode='22023',message='MANAGED_ADMIN_INVALID_INPUT'; end if;
 if a.role='ADMIN_B' then
  if p_role<>'ADMIN_C' or p_school_id is not null then
   raise exception using errcode='42501',message='MANAGED_ADMIN_ACCESS_DENIED'; end if;
  scope:=a.school_id;
 else
  scope:=p_school_id;
  if (p_role='ADMIN_A' and scope is not null) or (p_role<>'ADMIN_A' and scope is null) then
   raise exception using errcode='22023',message='MANAGED_ADMIN_INVALID_SCOPE'; end if;
 end if;
 if scope is not null and not exists(select 1 from public.schools s where s.id=scope) then
  raise exception using errcode='22023',message='MANAGED_ADMIN_INVALID_SCOPE'; end if;
 payload:=jsonb_build_object('name',p_name,'email',p_email,'role',p_role,'school_id',scope,'status',p_status);
 select r.* into receipt from public.admin_structure_creation_receipts r where r.entity_kind='ADMIN' and r.entity_id=p_admin_id;
 if found then
  if receipt.created_by_admin_id<>a.admin_id or receipt.payload<>payload then
   raise exception using errcode='23505',message='MANAGED_ADMIN_ID_CONFLICT'; end if;
  return p_admin_id;
 end if;
 if exists(select 1 from public.admins x where x.id=p_admin_id) then
  raise exception using errcode='23505',message='MANAGED_ADMIN_ID_CONFLICT'; end if;
 begin
  insert into public.admins(id,name,email,role,school_id,status) values(p_admin_id,p_name,p_email,p_role,scope,p_status);
 exception when unique_violation then
  raise exception using errcode='23505',message='MANAGED_ADMIN_EMAIL_CONFLICT';
 end;
 insert into public.admin_structure_creation_receipts(entity_kind,entity_id,created_by_admin_id,payload)
 values('ADMIN',p_admin_id,a.admin_id,payload);
 insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
 values(scope,'ADMIN',a.admin_id,'MANAGED_ADMIN_CREATED_V1',jsonb_build_object('admin_id',p_admin_id,'admin',payload));
 return p_admin_id;
end; $$;

create function public.update_managed_admin_v1(p_admin_id uuid,p_name text,p_email text,p_status text)
returns uuid language plpgsql security definer set search_path='' as $$
declare a record; old public.admins%rowtype;
begin
 perform pg_catalog.pg_advisory_xact_lock(28001,1);
 select * into a from public.require_admin_structure_actor_v1(false);
 -- Row lock tambem detecta snapshot antigo em REPEATABLE READ (40001).
 perform 1 from public.admins x where x.id=a.admin_id and x.status='ACTIVE' for update;
 if not found then raise exception using errcode='42501',message='ADMIN_STRUCTURE_ACCESS_DENIED'; end if;
 select x.* into old from public.admins x where x.id=p_admin_id for update;
 if not found or (a.role='ADMIN_B' and (old.role<>'ADMIN_C' or old.school_id<>a.school_id)) then
  raise exception using errcode='42501',message='MANAGED_ADMIN_ACCESS_DENIED'; end if;
 p_name:=regexp_replace(p_name,'^[[:space:]]+|[[:space:]]+$','','g');
 p_email:=regexp_replace(p_email,'^[[:space:]]+|[[:space:]]+$','','g');
 if p_name is null or p_name='' or p_email is null or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+$'
 or p_status is null or p_status not in ('ACTIVE','INACTIVE') then
  raise exception using errcode='22023',message='MANAGED_ADMIN_INVALID_INPUT'; end if;
 if old.role='ADMIN_A' and old.status='ACTIVE' and p_status='INACTIVE'
 and (select count(*) from public.admins x where x.role='ADMIN_A' and x.status='ACTIVE')<=1 then
  raise exception using errcode='55000',message='MANAGED_ADMIN_LAST_ACTIVE_A'; end if;
 if old.id=a.admin_id and p_status='INACTIVE' then
  raise exception using errcode='55000',message='MANAGED_ADMIN_SELF_DEACTIVATION'; end if;
 if row(old.name,old.email,old.status) is not distinct from row(p_name,p_email,p_status) then return old.id; end if;
 begin
  update public.admins set name=p_name,email=p_email,status=p_status,updated_at=now() where id=old.id;
 exception when unique_violation then
  raise exception using errcode='23505',message='MANAGED_ADMIN_EMAIL_CONFLICT';
 end;
 insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
 values(old.school_id,'ADMIN',a.admin_id,'MANAGED_ADMIN_UPDATED_V1',jsonb_build_object('admin_id',old.id,
 'old',jsonb_build_object('name',old.name,'email',old.email,'status',old.status),
 'new',jsonb_build_object('name',p_name,'email',p_email,'status',p_status)));
 return old.id;
end; $$;
revoke all on function public.require_admin_structure_actor_v1(boolean) from public,anon,authenticated,service_role;
revoke all on function public.get_admin_schools_v1() from public,anon,authenticated,service_role;
revoke all on function public.create_admin_school_v1(uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.get_managed_admins_v1() from public,anon,authenticated,service_role;
revoke all on function public.create_managed_admin_v1(uuid,text,text,text,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.update_managed_admin_v1(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.get_admin_schools_v1(),public.create_admin_school_v1(uuid,text),
 public.get_managed_admins_v1(),public.create_managed_admin_v1(uuid,text,text,text,uuid,text),
 public.update_managed_admin_v1(uuid,text,text,text) to authenticated;
-- Nenhum DELETE, alteracao de role/escola/Auth/hash ou grant de tabela.
commit;
