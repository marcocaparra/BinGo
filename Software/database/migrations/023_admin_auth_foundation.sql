-- Admin Web V1: identidade de dominio, independente de credenciais Auth.
-- Nao existe equivalencia aprovada entre papeis historicos e ADMIN_A/B/C.
-- Aborta antes de qualquer DDL se uma promocao exigir decisao manual.
begin;

lock table public.admins in access exclusive mode;
do $$
begin
    if exists (
        select 1 from public.admins
        where role not in ('ADMIN_A', 'ADMIN_B', 'ADMIN_C')
    ) then
        raise exception 'Admin Auth V1: existem admins com papeis legados. Classifique manualmente cada identidade como ADMIN_A/B/C e ajuste escola (A NULL; B/C NOT NULL), preservando IDs e historico, antes de promover esta migration.';
    end if;
end;
$$;

alter table public.admins
    add column auth_user_id uuid,
    add column status text not null default 'ACTIVE',
    alter column school_id drop not null,
    drop constraint admins_role_check,
    add constraint admins_auth_user_id_unique unique (auth_user_id),
    add constraint admins_status_check check (status in ('ACTIVE', 'INACTIVE')),
    add constraint admins_role_check check (role in ('ADMIN_A', 'ADMIN_B', 'ADMIN_C')),
    add constraint admins_role_school_check check (
        (role = 'ADMIN_A' and school_id is null)
        or (role in ('ADMIN_B', 'ADMIN_C') and school_id is not null)
    );

-- Mesmo padrao de students.auth_user_id: vinculo logico, sem presumir auth.users.
-- Nenhuma FK/ID/historico existente e removido ou recriado.
comment on column public.admins.auth_user_id is
    'Vinculo unico opcional com Supabase Auth. Identidade administrativa resolvida server-side.';
comment on column public.admins.password_hash is
    'Legado FastAPI somente. Admin Web usa Supabase Auth; nunca sincronizar senhas para este campo.';

create function public.get_my_admin_context_v1()
returns table (
    id uuid,
    name text,
    email text,
    role text,
    school_id uuid,
    status text
)
language sql
stable
security definer
set search_path = ''
as $$
    select admin.id, admin.name, admin.email, admin.role, admin.school_id, admin.status
    from public.admins as admin
    where admin.auth_user_id = (select auth.uid());
$$;

-- INACTIVE e retornado somente para informar o bloqueio da propria conta.
-- Futuras RPCs de dominio DEVEM validar status = ACTIVE server-side, alem de role/school.
comment on function public.get_my_admin_context_v1() is
    'Contexto proprio por auth.uid(), inclusive INACTIVE para informar bloqueio. Nao autoriza operacoes: futuras RPCs devem validar ACTIVE, role e school server-side.';

revoke all on function public.get_my_admin_context_v1()
from public, anon, authenticated, service_role;
grant execute on function public.get_my_admin_context_v1() to authenticated;

-- Mantem baseline fail-closed; nao cria policies nem grants de tabela.
commit;
