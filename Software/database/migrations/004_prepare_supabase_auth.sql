-- BinGo V1
-- Migration: 004_prepare_supabase_auth.sql

-- Prepara a entidade de domínio students para vínculo futuro com Supabase Auth.
-- Em Postgres local não existe o schema auth.users, então a FK real fica para
-- uma migration específica de Supabase, se o projeto decidir adicioná-la.

alter table students
    add column if not exists auth_user_id uuid;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'students_auth_user_id_unique'
          and conrelid = 'students'::regclass
    ) then
        alter table students
            add constraint students_auth_user_id_unique unique (auth_user_id);
    end if;
end $$;
