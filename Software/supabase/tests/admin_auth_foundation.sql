begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

create function pg_temp.raises_state(command text, expected_state text)
returns boolean language plpgsql as $$
begin
    execute command;
    return false;
exception when others then return sqlstate = expected_state;
end;
$$;

insert into public.schools (id, name) values
    ('aa100000-0000-4000-8000-000000000001', 'Escola Admin Auth 1'),
    ('aa100000-0000-4000-8000-000000000002', 'Escola Admin Auth 2');

select extensions.lives_ok($$insert into public.admins (id,name,email,role,school_id,auth_user_id)
values ('aa400000-0000-4000-8000-000000000001','Admin A','a@admin-auth.test','ADMIN_A',null,'aa900000-0000-4000-8000-000000000001')$$, 'aceita A global sem escola');
select extensions.lives_ok($$insert into public.admins (id,name,email,role,school_id,auth_user_id)
values ('aa400000-0000-4000-8000-000000000002','Admin B','b@admin-auth.test','ADMIN_B','aa100000-0000-4000-8000-000000000001','aa900000-0000-4000-8000-000000000002')$$, 'aceita B vinculado a escola');
select extensions.lives_ok($$insert into public.admins (id,name,email,role,school_id,auth_user_id)
values ('aa400000-0000-4000-8000-000000000003','Admin C','c@admin-auth.test','ADMIN_C','aa100000-0000-4000-8000-000000000002','aa900000-0000-4000-8000-000000000003')$$, 'aceita C vinculado a outra escola');
select extensions.lives_ok($$insert into public.admins (id,name,email,role,school_id,auth_user_id,status)
values ('aa400000-0000-4000-8000-000000000004','Admin inativo','inactive@admin-auth.test','ADMIN_C','aa100000-0000-4000-8000-000000000002','aa900000-0000-4000-8000-000000000004','INACTIVE')$$, 'aceita INACTIVE');
select extensions.is((select status from public.admins where email='a@admin-auth.test'),'ACTIVE', 'default ACTIVE');
select extensions.lives_ok($$update public.admins set status='ACTIVE' where email='b@admin-auth.test'$$, 'aceita ACTIVE explicito');

select extensions.ok(pg_temp.raises_state($$insert into public.admins(name,email,role,school_id) values('invalid','invalid@admin-auth.test','ADMIN_A','aa100000-0000-4000-8000-000000000001')$$,'23514'), 'rejeita A com escola');
select extensions.ok(pg_temp.raises_state($$insert into public.admins(name,email,role) values('invalid','invalid@admin-auth.test','ADMIN_B')$$,'23514'), 'rejeita B sem escola');
select extensions.ok(pg_temp.raises_state($$insert into public.admins(name,email,role) values('invalid','invalid@admin-auth.test','ADMIN_C')$$,'23514'), 'rejeita C sem escola');
select extensions.ok(pg_temp.raises_state($$update public.admins set role='INVALID' where email='a@admin-auth.test'$$,'23514'), 'rejeita role invalido');
select extensions.ok(pg_temp.raises_state(format('update public.admins set role=%L where email=%L', legacy.role, 'b@admin-auth.test'),'23514'), 'rejeita papel legado ' || legacy.role)
from (values ('ADMIN'),('ADMIN_CONQUISTA'),('BINGO_ADMIN')) legacy(role);
select extensions.ok(pg_temp.raises_state($$update public.admins set status='INVALID' where email='a@admin-auth.test'$$,'23514'), 'rejeita status invalido');
select extensions.ok(pg_temp.raises_state($$update public.admins set auth_user_id='aa900000-0000-4000-8000-000000000001' where email='b@admin-auth.test'$$,'23505'), 'Auth nao pode representar dois admins');
select extensions.lives_ok($$insert into public.admins(name,email,role) values('Nao vinculado 1','unlinked1@admin-auth.test','ADMIN_A'),('Nao vinculado 2','unlinked2@admin-auth.test','ADMIN_A')$$, 'permite varios admins sem vinculo Auth');

select extensions.ok((select prosecdef and provolatile='s' and pronargs=0 and proconfig=array['search_path=""'] from pg_proc where oid='public.get_my_admin_context_v1()'::regprocedure), 'RPC STABLE SECURITY DEFINER sem parametros e search_path vazio');
select extensions.is(pg_get_function_result('public.get_my_admin_context_v1()'::regprocedure), 'TABLE(id uuid, name text, email text, role text, school_id uuid, status text)', 'retorno minimo sem password_hash/auth_user_id');
select extensions.ok(not has_function_privilege('anon','public.get_my_admin_context_v1()','execute') and has_function_privilege('authenticated','public.get_my_admin_context_v1()','execute') and not has_function_privilege('service_role','public.get_my_admin_context_v1()','execute'), 'EXECUTE somente authenticated');
select extensions.ok(pg_temp.raises_state($$set local role anon; select * from public.get_my_admin_context_v1()$$,'42501'), 'anon nao executa realmente');

select extensions.ok(to_regprocedure('public.get_my_admin_context_v1(uuid)') is null and to_regprocedure('public.get_my_admin_context_v1(text)') is null, 'sem overloads para escolher identidade');
select extensions.ok(pg_temp.raises_state($$select * from public.get_my_admin_context_v1(admin_id => 'aa400000-0000-4000-8000-000000000002'::uuid)$$,'42883'), 'nao aceita admin_id');
select extensions.ok(pg_temp.raises_state($$select * from public.get_my_admin_context_v1(school_id => 'aa100000-0000-4000-8000-000000000002'::uuid)$$,'42883'), 'nao aceita school_id');
select extensions.ok(pg_temp.raises_state($$select * from public.get_my_admin_context_v1(role => 'ADMIN_A'::text)$$,'42883'), 'nao aceita role');

select set_config('request.jwt.claim.sub','aa900000-0000-4000-8000-000000000001',true);
set local role authenticated;
select extensions.results_eq($$select * from public.get_my_admin_context_v1()$$,$$values ('aa400000-0000-4000-8000-000000000001'::uuid,'Admin A'::text,'a@admin-auth.test'::text,'ADMIN_A'::text,null::uuid,'ACTIVE'::text)$$, 'A obtem somente si proprio e escola nula');
reset role;
select set_config('request.jwt.claim.sub','aa900000-0000-4000-8000-000000000002',true);
set local role authenticated;
select extensions.results_eq($$select id,role,school_id from public.get_my_admin_context_v1()$$,$$values ('aa400000-0000-4000-8000-000000000002'::uuid,'ADMIN_B'::text,'aa100000-0000-4000-8000-000000000001'::uuid)$$, 'B recebe somente seu papel e sua escola');
reset role;
select set_config('request.jwt.claim.sub','aa900000-0000-4000-8000-000000000003',true);
set local role authenticated;
select extensions.results_eq($$select id,role,school_id from public.get_my_admin_context_v1()$$,$$values ('aa400000-0000-4000-8000-000000000003'::uuid,'ADMIN_C'::text,'aa100000-0000-4000-8000-000000000002'::uuid)$$, 'C recebe somente seu papel e sua escola');
reset role;
select set_config('request.jwt.claim.sub','aa900000-0000-4000-8000-000000000004',true);
set local role authenticated;
select extensions.is((select status from public.get_my_admin_context_v1()), 'INACTIVE', 'inativo identificavel no proprio contexto');
reset role;
select set_config('request.jwt.claim.sub','aa900000-0000-4000-8000-000000000005',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_my_admin_context_v1()),0::bigint,'Auth sem admin recebe zero linhas');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_my_admin_context_v1()),0::bigint,'sem auth.uid nao recebe contexto');
reset role;

select extensions.ok(not has_table_privilege('authenticated','public.admins','select') and not has_any_column_privilege('authenticated','public.admins','select'), 'nenhum SELECT amplo ou de coluna em admins');
select extensions.ok(not has_table_privilege('authenticated','public.admins','insert') and not has_table_privilege('authenticated','public.admins','update') and not has_table_privilege('authenticated','public.admins','delete'), 'nenhuma escrita direta concedida');
select extensions.ok(pg_temp.raises_state($$set local role authenticated; select * from public.admins$$,'42501'), 'leitura direta efetivamente bloqueada');
select extensions.ok(pg_temp.raises_state($$set local role authenticated; update public.admins set status='ACTIVE'$$,'42501'), 'escrita direta efetivamente bloqueada');
select extensions.ok((select relrowsecurity from pg_class where oid='public.admins'::regclass) and not exists(select 1 from pg_policies where schemaname='public' and tablename='admins'), 'admins permanece RLS fail-closed sem policy');
select extensions.ok(exists(select 1 from pg_constraint where conrelid='public.redemptions'::regclass and confrelid='public.admins'::regclass and confdeltype='r'), 'FK de entrega preservada com RESTRICT');
select * from extensions.finish();
rollback;
