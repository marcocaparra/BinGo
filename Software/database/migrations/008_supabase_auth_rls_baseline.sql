-- BinGo V1
-- Migration: 008_supabase_auth_rls_baseline.sql
--
-- Estabelece o baseline de autorizacao para clientes Supabase. Leituras
-- privadas usam Supabase Auth + RLS; operacoes criticas permanecem restritas
-- a Edge Functions e RPCs server-side.

-- Remove privilegios herdados dos defaults da plataforma, inclusive
-- TRUNCATE, REFERENCES, TRIGGER e MAINTAIN. Grants necessarios sao
-- reconstruidos explicitamente abaixo.
revoke all privileges on all tables in schema public
from public, anon, authenticated, service_role;

-- REVOKE em nivel de tabela nao remove grants concedidos diretamente em
-- colunas. A leitura tecnica existente e retirada para ser reconstituida de
-- forma explicita depois da habilitacao do RLS.
revoke select (id, school_id, api_key_hash)
on public.machines
from service_role;

-- Novas relacoes criadas por migrations executadas como postgres nao devem
-- voltar a receber privilegios implicitos dos papeis expostos pela API.
alter default privileges for role postgres in schema public
    revoke all privileges on tables
    from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema public
    revoke all privileges on sequences
    from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema public
    revoke execute on functions
    from public, anon, authenticated, service_role;

alter table public.schools enable row level security;
alter table public.classes enable row level security;
alter table public.students enable row level security;
alter table public.admins enable row level security;
alter table public.machines enable row level security;
alter table public.rewards enable row level security;
alter table public.deposits enable row level security;
alter table public.redemptions enable row level security;
alter table public.audit_logs enable row level security;
alter table public.school_settings enable row level security;
alter table public.waste_categories enable row level security;

create policy students_select_own_v1
on public.students
for select
to authenticated
using (auth_user_id = (select auth.uid()));

create policy classes_select_own_v1
on public.classes
for select
to authenticated
using (
    exists (
        select 1
        from public.students as current_student
        where current_student.auth_user_id = (select auth.uid())
          and current_student.class_id = classes.id
          and current_student.school_id = classes.school_id
    )
);

create policy schools_select_own_v1
on public.schools
for select
to authenticated
using (
    exists (
        select 1
        from public.students as current_student
        where current_student.auth_user_id = (select auth.uid())
          and current_student.school_id = schools.id
    )
);

create policy waste_categories_select_public_v1
on public.waste_categories
for select
to anon, authenticated
using (true);

-- auth_user_id e necessario para que as policies de classes e schools
-- consultem students sob o papel authenticated. A RLS de students limita a
-- exposicao dessa coluna ao proprio vinculo do usuario.
grant select (
    id,
    name,
    school_id,
    class_id,
    points_student_balance,
    status,
    auth_user_id
)
on public.students
to authenticated;

grant select (
    id,
    school_id,
    segment,
    grade,
    name,
    points_class_balance
)
on public.classes
to authenticated;

grant select (id, name)
on public.schools
to authenticated;

-- Catalogo global integralmente publico para leitura, inclusive registros
-- inativos. Qualquer filtro por is_active exige decisao de produto propria.
grant select
on public.waste_categories
to anon, authenticated;

-- Grant tecnico minimo usado por authenticateMachine. service_role continua
-- sem escrita e sem leitura das demais colunas de machines.
grant select (id, school_id, api_key_hash)
on public.machines
to service_role;
