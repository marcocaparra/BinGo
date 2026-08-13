-- BinGo V1
-- Migration: 007_machine_auth_service_role_select.sql
--
-- Espelho cronologico de
-- database/migrations/007_machine_auth_service_role_select.sql.

grant select (id, school_id, api_key_hash)
on public.machines
to service_role;

