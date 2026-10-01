begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

create function pg_temp.denied(command text) returns boolean language plpgsql as $$
begin execute command; return false;
exception when insufficient_privilege then return true; end; $$;

insert into public.schools(id, name) values
 ('ad100000-0000-4000-8000-000000000001', 'Descartes Norte'),
 ('ad100000-0000-4000-8000-000000000002', 'Descartes Sul');
insert into public.classes(id, school_id, segment, grade, name) values
 ('ad200000-0000-4000-8000-000000000001', 'ad100000-0000-4000-8000-000000000001', 'FUNDAMENTAL_II', '9', '9A'),
 ('ad200000-0000-4000-8000-000000000002', 'ad100000-0000-4000-8000-000000000002', 'FUNDAMENTAL_II', '8', '8B');
insert into public.students(id, school_id, class_id, name, status) values
 ('ad300000-0000-4000-8000-000000000001', 'ad100000-0000-4000-8000-000000000001', 'ad200000-0000-4000-8000-000000000001', 'Aluno Identificado', 'ACTIVE'),
 ('ad300000-0000-4000-8000-000000000002', 'ad100000-0000-4000-8000-000000000002', 'ad200000-0000-4000-8000-000000000002', 'Aluno Sul', 'ACTIVE');
insert into public.machines(id, school_id, name, status) values
 ('ad800000-0000-4000-8000-000000000001', 'ad100000-0000-4000-8000-000000000001', 'Totem Norte', 'ONLINE'),
 ('ad800000-0000-4000-8000-000000000002', 'ad100000-0000-4000-8000-000000000002', 'Totem Sul', 'ONLINE');
insert into public.admins(name, email, role, school_id, auth_user_id, status) values
 ('A', 'a@deposits.test', 'ADMIN_A', null, 'ad900000-0000-4000-8000-000000000001', 'ACTIVE'),
 ('B', 'b@deposits.test', 'ADMIN_B', 'ad100000-0000-4000-8000-000000000001', 'ad900000-0000-4000-8000-000000000002', 'ACTIVE'),
 ('C', 'c@deposits.test', 'ADMIN_C', 'ad100000-0000-4000-8000-000000000002', 'ad900000-0000-4000-8000-000000000003', 'ACTIVE'),
 ('I', 'i@deposits.test', 'ADMIN_A', null, 'ad900000-0000-4000-8000-000000000004', 'INACTIVE');

insert into public.deposits(
 id, event_id, school_id, machine_id, class_id, student_id, is_valid, detected_type,
 points_awarded_student, points_awarded_class, waste_category_id, category_source,
 bonus_rate_applied, bonus_bincoins_awarded, created_at
) values
 ('ad700000-0000-4000-8000-000000000001', 'ae700000-0000-4000-8000-000000000001', 'ad100000-0000-4000-8000-000000000001', 'ad800000-0000-4000-8000-000000000001', 'ad200000-0000-4000-8000-000000000001', 'ad300000-0000-4000-8000-000000000001', true, 'BATTERY', 1600, 1900, (select id from public.waste_categories where code='BATTERY'), 'AI_CONFIRMED', 1.0000, 800, '2026-10-01T10:00:00Z'),
 ('ad700000-0000-4000-8000-000000000002', 'ae700000-0000-4000-8000-000000000002', 'ad100000-0000-4000-8000-000000000001', 'ad800000-0000-4000-8000-000000000001', 'ad200000-0000-4000-8000-000000000001', null, true, null, 0, 1900, (select id from public.waste_categories where code='UNKNOWN'), 'UNIDENTIFIED', 0, 0, '2026-10-01T11:00:00Z'),
 ('ad700000-0000-4000-8000-000000000003', 'ae700000-0000-4000-8000-000000000003', 'ad100000-0000-4000-8000-000000000001', 'ad800000-0000-4000-8000-000000000001', 'ad200000-0000-4000-8000-000000000001', null, false, null, 0, 0, null, null, 0, 0, '2026-10-01T12:00:00Z'),
 ('ad700000-0000-4000-8000-000000000004', 'ae700000-0000-4000-8000-000000000004', 'ad100000-0000-4000-8000-000000000001', 'ad800000-0000-4000-8000-000000000001', 'ad200000-0000-4000-8000-000000000001', null, false, 'UNSUPPORTED', 0, 0, null, null, 0, 0, '2026-10-01T13:00:00Z'),
 ('ad700000-0000-4000-8000-000000000005', 'ae700000-0000-4000-8000-000000000005', 'ad100000-0000-4000-8000-000000000001', 'ad800000-0000-4000-8000-000000000001', 'ad200000-0000-4000-8000-000000000001', null, false, 'UNSUPPORTED', 0, 0, null, null, 0, 0, '2026-10-01T13:00:00Z'),
 ('ad700000-0000-4000-8000-000000000006', 'ae700000-0000-4000-8000-000000000006', 'ad100000-0000-4000-8000-000000000002', 'ad800000-0000-4000-8000-000000000002', 'ad200000-0000-4000-8000-000000000002', 'ad300000-0000-4000-8000-000000000002', true, 'CABLE_WIRE', 900, 1900, (select id from public.waste_categories where code='CABLE_WIRE'), 'USER_CORRECTED', 0.1250, 100, '2026-10-01T14:00:00Z');

select extensions.ok((select prosecdef and provolatile='s' and pronargs=0 and proconfig=array['search_path=""'] from pg_proc where oid='public.get_admin_deposits_v1()'::regprocedure),'RPC STABLE SECURITY DEFINER sem parametros e search_path vazio');
select extensions.is(pg_get_function_result('public.get_admin_deposits_v1()'::regprocedure),'TABLE(deposit_id uuid, event_id uuid, school_id uuid, school_name text, machine_id uuid, machine_name text, class_id uuid, class_name text, student_id uuid, student_name text, is_valid boolean, detected_type text, waste_category_code text, category_source text, bonus_rate_applied numeric, bonus_bincoins_awarded integer, points_awarded_student integer, points_awarded_class integer, created_at timestamp with time zone)','retorno exato aprovado');
select extensions.ok(has_function_privilege('authenticated','public.get_admin_deposits_v1()','execute') and not has_function_privilege('anon','public.get_admin_deposits_v1()','execute') and not has_function_privilege('service_role','public.get_admin_deposits_v1()','execute'),'EXECUTE somente authenticated');
select extensions.ok(pg_temp.denied('set local role anon; select * from public.get_admin_deposits_v1()'),'anon recusado');
reset role;
select extensions.ok(not has_column_privilege('authenticated','public.deposits','event_id','select') and not has_column_privilege('authenticated','public.deposits','school_id','select') and not has_column_privilege('authenticated','public.deposits','machine_id','select') and not has_column_privilege('authenticated','public.deposits','class_id','select') and not has_column_privilege('authenticated','public.deposits','bonus_rate_applied','select'),'nenhuma ampliacao de SELECT direto em deposits');
select extensions.is((select count(*) from pg_policies where schemaname='public' and tablename='deposits'),1::bigint,'RLS de deposits preserva somente policy Mobile existente');

select set_config('request.jwt.claim.sub','ad900000-0000-4000-8000-000000000001',true);
set local role authenticated;
select extensions.is((select count(distinct school_id) from public.get_admin_deposits_v1() where deposit_id::text like 'ad700000%'),2::bigint,'A ve descartes de multiplas escolas');
select extensions.ok((select student_id is null and student_name is null and waste_category_code='UNKNOWN' and category_source='UNIDENTIFIED' and points_awarded_student=0 and points_awarded_class=1900 from public.get_admin_deposits_v1() where deposit_id='ad700000-0000-4000-8000-000000000002'),'evento valido anonimo preserva aluno NULL e snapshots');
select extensions.ok((select student_name='Aluno Identificado' and school_name='Descartes Norte' and machine_name='Totem Norte' and class_name='9A' and waste_category_code='BATTERY' and bonus_rate_applied=1.0000 and bonus_bincoins_awarded=800 and points_awarded_student=1600 and points_awarded_class=1900 from public.get_admin_deposits_v1() where deposit_id='ad700000-0000-4000-8000-000000000001'),'evento valido identificado deriva nomes e preserva snapshots economicos');
select extensions.ok((select not is_valid and waste_category_code is null and category_source is null and points_awarded_student=0 and points_awarded_class=0 from public.get_admin_deposits_v1() where deposit_id='ad700000-0000-4000-8000-000000000003'),'evento invalido preserva categoria/origem NULL e 0/0');
select extensions.results_eq($$select deposit_id from public.get_admin_deposits_v1() where deposit_id in ('ad700000-0000-4000-8000-000000000004','ad700000-0000-4000-8000-000000000005')$$,$$values ('ad700000-0000-4000-8000-000000000005'::uuid),('ad700000-0000-4000-8000-000000000004'::uuid)$$,'ordem deterministica por created_at DESC, deposit_id DESC');
reset role;

select set_config('request.jwt.claim.sub','ad900000-0000-4000-8000-000000000002',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_admin_deposits_v1()),5::bigint,'B ve somente propria escola');
select extensions.ok((select bool_and(school_id='ad100000-0000-4000-8000-000000000001') from public.get_admin_deposits_v1()),'B nao vaza outra escola');
reset role;
select set_config('request.jwt.claim.sub','ad900000-0000-4000-8000-000000000003',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_admin_deposits_v1()),1::bigint,'C ve somente propria escola');
select extensions.ok((select bool_and(school_id='ad100000-0000-4000-8000-000000000002') from public.get_admin_deposits_v1()),'C nao vaza outra escola');
reset role;

select set_config('request.jwt.claim.sub','ad900000-0000-4000-8000-000000000004',true);
set local role authenticated;
select extensions.ok(pg_temp.denied('select * from public.get_admin_deposits_v1()'),'admin INACTIVE recusado');
reset role;
select set_config('request.jwt.claim.sub','ad900000-0000-4000-8000-000000000005',true);
set local role authenticated;
select extensions.ok(pg_temp.denied('select * from public.get_admin_deposits_v1()'),'Auth sem admin recusado');
reset role;

select * from extensions.finish();
rollback;
