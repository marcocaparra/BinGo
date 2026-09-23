-- BinGo V1
-- Migration: 009_backend_readiness_v1.sql
--
-- Este arquivo deve permanecer funcionalmente equivalente a
-- database/migrations/009_backend_readiness_v1.sql.

create function public.check_backend_readiness_v1()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
    select
        not pg_catalog.pg_is_in_recovery()
        and pg_catalog.current_setting('default_transaction_read_only') = 'off';
$$;

comment on function public.check_backend_readiness_v1() is
    'Verifica somente se o PostgreSQL central está disponível em condição operacional de escrita, sem produzir efeitos.';

revoke all on function public.check_backend_readiness_v1()
from public, anon, authenticated, service_role;

grant execute on function public.check_backend_readiness_v1()
to service_role;
