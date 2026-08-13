-- BinGo V1
-- Migration: 007_machine_auth_service_role_select.sql
--
-- Permite que a fundacao compartilhada de autenticacao tecnica consulte
-- exclusivamente a identidade e a credencial da maquina. Nenhuma escrita ou
-- leitura das demais colunas e concedida por esta migration.

grant select (id, school_id, api_key_hash)
on public.machines
to service_role;

