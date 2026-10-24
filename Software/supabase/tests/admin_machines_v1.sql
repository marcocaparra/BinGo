begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();
create function pg_temp.denied(command text) returns boolean language plpgsql as $$
begin execute command; return false;
exception when insufficient_privilege then return true; end; $$;
insert into public.schools(id,name) values
 ('af100000-0000-4000-8000-000000000001','Totens Norte'),
 ('af100000-0000-4000-8000-000000000002','Totens Sul');
insert into public.admins(name,email,role,school_id,auth_user_id,status) values
 ('A','a@machines.test','ADMIN_A',null,'af900000-0000-4000-8000-000000000001','ACTIVE'),
 ('B','b@machines.test','ADMIN_B','af100000-0000-4000-8000-000000000001','af900000-0000-4000-8000-000000000002','ACTIVE'),
 ('C','c@machines.test','ADMIN_C','af100000-0000-4000-8000-000000000002','af900000-0000-4000-8000-000000000003','ACTIVE'),
 ('I','i@machines.test','ADMIN_A',null,'af900000-0000-4000-8000-000000000004','INACTIVE');
insert into public.machines(id,school_id,name,status,firmware_version,last_seen,bin_full,camera_ok,net_ok,api_key_hash) values
 ('af800000-0000-4000-8000-000000000001','af100000-0000-4000-8000-000000000001','M1','ONLINE',null,null,false,true,false,'not-exposed'),
 ('af800000-0000-4000-8000-000000000002','af100000-0000-4000-8000-000000000001','M2','OFFLINE','v1','2026-10-01T00:00:00Z',true,false,true,'not-exposed'),
 ('af800000-0000-4000-8000-000000000003','af100000-0000-4000-8000-000000000002','M3','MAINTENANCE',null,null,false,true,true,null),
 ('af800000-0000-4000-8000-000000000004','af100000-0000-4000-8000-000000000002','M4','OUT_OF_SERVICE',null,null,false,true,true,null);
select extensions.ok((select prosecdef and provolatile='s' and pronargs=0 and proconfig=array['search_path=""'] from pg_proc where oid='public.get_admin_machines_v1()'::regprocedure),'RPC STABLE SECURITY DEFINER sem parametros e search_path vazio');
select extensions.is(pg_get_function_result('public.get_admin_machines_v1()'::regprocedure),'TABLE(machine_id uuid, school_id uuid, school_name text, name text, status text, firmware_version text, last_seen timestamp with time zone, bin_full boolean, camera_ok boolean, net_ok boolean)','retorno exato sem hash');
select extensions.ok(has_function_privilege('authenticated','public.get_admin_machines_v1()','execute') and not has_function_privilege('anon','public.get_admin_machines_v1()','execute') and not has_function_privilege('service_role','public.get_admin_machines_v1()','execute'),'EXECUTE somente authenticated');
select extensions.ok(pg_temp.denied('set local role anon; select * from public.get_admin_machines_v1()'),'anon recusado');
reset role;
select extensions.ok(not has_any_column_privilege('authenticated','public.machines','select') and not has_table_privilege('authenticated','public.machines','select'),'nenhum SELECT direto concedido');
select extensions.ok(pg_temp.denied('set local role authenticated; select * from public.machines'),'leitura direta recusada');
reset role;
select extensions.ok((select relrowsecurity from pg_class where oid='public.machines'::regclass) and not exists(select 1 from pg_policies where schemaname='public' and tablename='machines'),'RLS fail-closed preservado');
select extensions.ok(has_column_privilege('service_role','public.machines','api_key_hash','select') and not has_column_privilege('service_role','public.machines','name','select'),'autenticacao tecnica minima preservada');
select set_config('request.jwt.claim.sub','af900000-0000-4000-8000-000000000001',true);
set local role authenticated;
select extensions.is((select count(distinct school_id) from public.get_admin_machines_v1() where machine_id::text like 'af800000%'),2::bigint,'A ve multiplas escolas');
select extensions.results_eq($$select status from public.get_admin_machines_v1() where machine_id::text like 'af800000%' order by name$$,$$values ('ONLINE'::text),('OFFLINE'),('MAINTENANCE'),('OUT_OF_SERVICE')$$,'quatro status persistidos');
select extensions.ok((select firmware_version is null and last_seen is null and not bin_full and camera_ok and not net_ok from public.get_admin_machines_v1() where name='M1'),'NULL e flags preservados');
select extensions.is((select school_name from public.get_admin_machines_v1() where name='M1'),'Totens Norte','nome escolar derivado do join');
select extensions.ok((select not (to_jsonb(m) ? 'api_key_hash') from public.get_admin_machines_v1() m where name='M1'),'hash ausente no JSON');
reset role;
select set_config('request.jwt.claim.sub','af900000-0000-4000-8000-000000000002',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_admin_machines_v1()),2::bigint,'B ve somente propria escola');
select extensions.ok((select bool_and(school_id='af100000-0000-4000-8000-000000000001') from public.get_admin_machines_v1()),'B sem acesso Sul');
reset role;
select set_config('request.jwt.claim.sub','af900000-0000-4000-8000-000000000003',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_admin_machines_v1()),2::bigint,'C ve somente propria escola');
select extensions.ok((select bool_and(school_id='af100000-0000-4000-8000-000000000002') from public.get_admin_machines_v1()),'C sem acesso Norte');
reset role;
select set_config('request.jwt.claim.sub','af900000-0000-4000-8000-000000000004',true);
set local role authenticated;
select extensions.ok(pg_temp.denied('select * from public.get_admin_machines_v1()'),'inativo recusado');
reset role;
select set_config('request.jwt.claim.sub','af900000-0000-4000-8000-000000000005',true);
set local role authenticated;
select extensions.ok(pg_temp.denied('select * from public.get_admin_machines_v1()'),'Auth sem admin recusado');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select extensions.ok(pg_temp.denied('select * from public.get_admin_machines_v1()'),'sem auth.uid recusado');
reset role;
select * from extensions.finish();
rollback;
