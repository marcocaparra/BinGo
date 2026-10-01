begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();
create function pg_temp.raises_state(command text, expected_state text)
returns boolean language plpgsql as $$begin execute command; return false;
exception when others then return sqlstate = expected_state; end;$$;
insert into public.schools(id,name) values('ac100000-0000-4000-8000-000000000001','Request school'),('ac100000-0000-4000-8000-000000000002','External school');
insert into public.classes(id,school_id,segment,grade,name,points_class_balance) values
 ('ac200000-0000-4000-8000-000000000001','ac100000-0000-4000-8000-000000000001','s','1','Origem',100),
 ('ac200000-0000-4000-8000-000000000002','ac100000-0000-4000-8000-000000000001','s','2','Destino',200),
 ('ac200000-0000-4000-8000-000000000003','ac100000-0000-4000-8000-000000000001','s','3','Mais recente',300),
 ('ac200000-0000-4000-8000-000000000004','ac100000-0000-4000-8000-000000000002','s','1','Externa',400);
insert into public.students(id,school_id,class_id,name,registration,pin_hash,auth_user_id,is_activated,points_student_balance) values
 ('ac300000-0000-4000-8000-000000000001','ac100000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000001','Aluno','001','protected-pin','ac900000-0000-4000-8000-000000000009',true,800),
 ('ac300000-0000-4000-8000-000000000002','ac100000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000001','Segundo','002',null,null,false,0),
 ('ac300000-0000-4000-8000-000000000003','ac100000-0000-4000-8000-000000000002','ac200000-0000-4000-8000-000000000004','Externo',null,null,null,false,0);
insert into public.admins(id,school_id,name,email,role,auth_user_id,status) values
 ('ac400000-0000-4000-8000-000000000001',null,'A','a@requests.test','ADMIN_A','ac900000-0000-4000-8000-000000000001','ACTIVE'),
 ('ac400000-0000-4000-8000-000000000002','ac100000-0000-4000-8000-000000000001','B','b@requests.test','ADMIN_B','ac900000-0000-4000-8000-000000000002','ACTIVE'),
 ('ac400000-0000-4000-8000-000000000003','ac100000-0000-4000-8000-000000000001','C','c@requests.test','ADMIN_C','ac900000-0000-4000-8000-000000000003','ACTIVE'),
 ('ac400000-0000-4000-8000-000000000004','ac100000-0000-4000-8000-000000000001','Outro C','c2@requests.test','ADMIN_C','ac900000-0000-4000-8000-000000000004','ACTIVE'),
 ('ac400000-0000-4000-8000-000000000005','ac100000-0000-4000-8000-000000000002','B externo','b2@requests.test','ADMIN_B','ac900000-0000-4000-8000-000000000005','ACTIVE'),
 ('ac400000-0000-4000-8000-000000000006','ac100000-0000-4000-8000-000000000001','Inativo','inactive@requests.test','ADMIN_C','ac900000-0000-4000-8000-000000000006','INACTIVE');
insert into public.machines(id,school_id,name,status) values('ac500000-0000-4000-8000-000000000001','ac100000-0000-4000-8000-000000000001','Historica','ONLINE');
insert into public.deposits(event_id,school_id,machine_id,class_id,student_id,is_valid,waste_category_id,category_source,points_awarded_student,points_awarded_class)
 values('ac600000-0000-4000-8000-000000000001','ac100000-0000-4000-8000-000000000001','ac500000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000001','ac300000-0000-4000-8000-000000000001',true,(select id from public.waste_categories where code='PERIPHERAL'),'AI_CONFIRMED',800,1900);
create temporary table historic_deposit as select * from public.deposits where event_id='ac600000-0000-4000-8000-000000000001';
create temporary table original_student as select * from public.students where id='ac300000-0000-4000-8000-000000000001';
select extensions.has_table('public','class_change_requests','modelo persistido');
select extensions.ok((select relrowsecurity from pg_class where oid='public.class_change_requests'::regclass),'RLS habilitado');
select extensions.is((select count(*) from pg_policies where tablename='class_change_requests'),0::bigint,'sem policies diretas');
select extensions.is((select count(*) from pg_constraint where conrelid='public.class_change_requests'::regclass and contype='f' and confdeltype='r'),6::bigint,'seis FKs RESTRICT sem cascade');
select extensions.ok(not has_table_privilege(r,'public.class_change_requests','select') and not has_table_privilege(r,'public.class_change_requests','insert') and not has_table_privilege(r,'public.class_change_requests','update') and not has_table_privilege(r,'public.class_change_requests','delete'),'sem grants diretos '||r) from (values('anon'),('authenticated')) roles(r);
select extensions.ok(prosecdef and proconfig=array['search_path=""'],'SECURITY DEFINER seguro '||proname) from pg_proc where pronamespace='public'::regnamespace and proname in ('get_class_change_requests_v1','create_class_change_request_v1','approve_class_change_request_v1','reject_class_change_request_v1','cancel_class_change_request_v1','resolve_class_change_request_v1');
select extensions.ok(has_function_privilege('authenticated',oid,'execute') and not has_function_privilege('anon',oid,'execute') and not has_function_privilege('service_role',oid,'execute'),'grants estreitos '||proname) from pg_proc where pronamespace='public'::regnamespace and proname in ('get_class_change_requests_v1','create_class_change_request_v1','approve_class_change_request_v1','reject_class_change_request_v1','cancel_class_change_request_v1');
select extensions.ok(not has_function_privilege('authenticated','public.resolve_class_change_request_v1(uuid,text)','execute'),'helper interno inacessivel');
select extensions.ok(pg_temp.raises_state('set local role anon; select * from public.get_class_change_requests_v1()','42501'),'anon nao executa');
select extensions.ok(pg_temp.raises_state('set local role authenticated; select * from public.class_change_requests','42501'),'leitura direta bloqueada');
select extensions.ok(not exists(select 1 from pg_proc p cross join unnest(p.proargnames[1:p.pronargs]) a where p.pronamespace='public'::regnamespace and p.proname in ('get_class_change_requests_v1','create_class_change_request_v1','approve_class_change_request_v1','reject_class_change_request_v1','cancel_class_change_request_v1') and a in ('p_school_id','p_source_class_id','p_actor_id','p_status')),'cliente nao escolhe autoridade/origem/status');
select set_config('request.jwt.claim.sub','ac900000-0000-4000-8000-000000000003',true);
set local role authenticated;
select extensions.is(public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000001','ac300000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000002'),'ac700000-0000-4000-8000-000000000001'::uuid,'C cria');
select extensions.is(public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000001','ac300000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000002'),'ac700000-0000-4000-8000-000000000001'::uuid,'replay identico retorna mesmo UUID');
select extensions.ok(pg_temp.raises_state($$select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000001','ac300000-0000-4000-8000-000000000002','ac200000-0000-4000-8000-000000000002')$$,'23505'),'UUID divergente conflita');
select extensions.ok(pg_temp.raises_state($$select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000001','ac300000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000003')$$,'23505'),'destino divergente conflita');
select extensions.ok(pg_temp.raises_state($$select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000008','ac300000-0000-4000-8000-000000000003','ac200000-0000-4000-8000-000000000002')$$,'42501'),'C nao solicita aluno externo');
select extensions.ok(pg_temp.raises_state($$select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000008','ac300000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000004')$$,'42501'),'C nao solicita destino externo');
select extensions.ok(pg_temp.raises_state($$select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000008','ac300000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000001')$$,'22023'),'origem igual destino rejeitada');
select extensions.is((select current_class_id from public.get_class_change_requests_v1()),'ac200000-0000-4000-8000-000000000001'::uuid,'criacao nao muda turma');
select extensions.ok(not (select is_stale from public.get_class_change_requests_v1()),'pending atual nao stale');
select extensions.ok(pg_temp.raises_state($$select public.approve_class_change_request_v1('ac700000-0000-4000-8000-000000000001')$$,'42501'),'C nao aprova');
select extensions.ok(pg_temp.raises_state($$select public.reject_class_change_request_v1('ac700000-0000-4000-8000-000000000001')$$,'42501'),'C nao rejeita');
reset role;
select extensions.is((select count(*) from public.audit_logs where action='CLASS_CHANGE_REQUEST_CREATED_V1' and school_id='ac100000-0000-4000-8000-000000000001'),1::bigint,'replay nao duplica auditoria criacao');
select extensions.ok(pg_temp.raises_state($$update public.class_change_requests set status='STALE' where id='ac700000-0000-4000-8000-000000000001'$$,'23514'),'STALE nao e status persistido');
select extensions.ok(pg_temp.raises_state($$update public.class_change_requests set source_class_id=destination_class_id where id='ac700000-0000-4000-8000-000000000001'$$,'23514'),'constraint origem != destino');
select extensions.ok(pg_temp.raises_state($$update public.class_change_requests set resolved_by_admin_id='ac400000-0000-4000-8000-000000000002' where id='ac700000-0000-4000-8000-000000000001'$$,'23514'),'PENDING sem resolved fields');
select extensions.ok(pg_temp.raises_state($$update public.class_change_requests set status='APPROVED' where id='ac700000-0000-4000-8000-000000000001'$$,'23514'),'terminal exige resolved fields');
select set_config('request.jwt.claim.sub','ac900000-0000-4000-8000-000000000004',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_class_change_requests_v1()),0::bigint,'outro C nao ve requests do autor');
select extensions.ok(pg_temp.raises_state($$select public.cancel_class_change_request_v1('ac700000-0000-4000-8000-000000000001')$$,'42501'),'outro C nao cancela');
select extensions.ok(pg_temp.raises_state($$select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000001','ac300000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000002')$$,'23505'),'outro ator nao faz replay');
reset role;
select set_config('request.jwt.claim.sub','ac900000-0000-4000-8000-000000000005',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_class_change_requests_v1()),0::bigint,'B externo nao ve');
select extensions.ok(pg_temp.raises_state($$select public.approve_class_change_request_v1('ac700000-0000-4000-8000-000000000001')$$,'42501'),'B externo nao decide');
reset role;
select set_config('request.jwt.claim.sub','ac900000-0000-4000-8000-000000000002',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_class_change_requests_v1()),1::bigint,'B lista escola');
select extensions.ok(pg_temp.raises_state($$select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000008','ac300000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000002')$$,'42501'),'B nao cria request');
select extensions.ok(pg_temp.raises_state($$select public.cancel_class_change_request_v1('ac700000-0000-4000-8000-000000000001')$$,'42501'),'B nao cancela');
select extensions.lives_ok($$select public.approve_class_change_request_v1('ac700000-0000-4000-8000-000000000001')$$,'B aprova');
select extensions.lives_ok($$select public.approve_class_change_request_v1('ac700000-0000-4000-8000-000000000001')$$,'retry approve idempotente');
select extensions.ok(pg_temp.raises_state($$select public.reject_class_change_request_v1('ac700000-0000-4000-8000-000000000001')$$,'P0001'),'decisao terminal incompativel conflita');
reset role;
select extensions.is((select class_id from public.students where id='ac300000-0000-4000-8000-000000000001'),'ac200000-0000-4000-8000-000000000002'::uuid,'aprovacao muda turma');
select extensions.ok((select (to_jsonb(s)-'class_id')=(to_jsonb(o)-'class_id') from public.students s cross join original_student o where s.id=o.id),'somente class_id mudou');
select extensions.results_eq($$select * from public.deposits where event_id='ac600000-0000-4000-8000-000000000001'$$,$$select * from historic_deposit$$,'historico completo deposito preservado');
select extensions.is((select count(*) from public.audit_logs where action='CLASS_CHANGE_REQUEST_APPROVED_V1' and school_id='ac100000-0000-4000-8000-000000000001'),1::bigint,'retry nao duplica auditoria approve');
select extensions.ok((select actor_id='ac400000-0000-4000-8000-000000000002' and metadata->>'old_class_id'='ac200000-0000-4000-8000-000000000001' and metadata->>'new_class_id'='ac200000-0000-4000-8000-000000000002' and metadata->>'old_status'='PENDING' and metadata->>'new_status'='APPROVED' from public.audit_logs where action='CLASS_CHANGE_REQUEST_APPROVED_V1' and school_id='ac100000-0000-4000-8000-000000000001'),'auditoria ator e old/new');
select public.update_admin_student_v1('ac300000-0000-4000-8000-000000000001','Aluno',null,'001','ac200000-0000-4000-8000-000000000003','ACTIVE');
select extensions.lives_ok($$select public.approve_class_change_request_v1('ac700000-0000-4000-8000-000000000001')$$,'retry de APPROVED apos mudanca posterior retorna sem reexecutar');
select extensions.is((select class_id from public.students where id='ac300000-0000-4000-8000-000000000001'),'ac200000-0000-4000-8000-000000000003'::uuid,'retry aprovado nao sobrescreve turma posterior');
select extensions.is((select count(*) from public.audit_logs where action='CLASS_CHANGE_REQUEST_APPROVED_V1' and school_id='ac100000-0000-4000-8000-000000000001'),1::bigint,'retry posterior nao duplica auditoria');
select set_config('request.jwt.claim.sub','ac900000-0000-4000-8000-000000000003',true);
set local role authenticated;
select extensions.lives_ok($$select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000001','ac300000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000002')$$,'replay apos conclusao nao recaptura origem');
select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000002','ac300000-0000-4000-8000-000000000002','ac200000-0000-4000-8000-000000000002');
select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000003','ac300000-0000-4000-8000-000000000002','ac200000-0000-4000-8000-000000000003');
select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000004','ac300000-0000-4000-8000-000000000002','ac200000-0000-4000-8000-000000000002');
select extensions.lives_ok($$select public.cancel_class_change_request_v1('ac700000-0000-4000-8000-000000000004')$$,'autor cancela');
select extensions.lives_ok($$select public.cancel_class_change_request_v1('ac700000-0000-4000-8000-000000000004')$$,'retry cancel idempotente');
reset role;
select extensions.is((select count(*) from public.class_change_requests where student_id='ac300000-0000-4000-8000-000000000002'),3::bigint,'varios requests mesmo aluno permitidos');
select set_config('request.jwt.claim.sub','ac900000-0000-4000-8000-000000000002',true);
set local role authenticated;
select public.update_admin_student_v1('ac300000-0000-4000-8000-000000000002','Segundo',null,'002','ac200000-0000-4000-8000-000000000003','ACTIVE');
select extensions.ok((select is_stale from public.get_class_change_requests_v1() where request_id='ac700000-0000-4000-8000-000000000002'),'stale derivado apos mudanca direta B');
select extensions.throws_ok($$select public.approve_class_change_request_v1('ac700000-0000-4000-8000-000000000002')$$,'P0001','CLASS_CHANGE_REQUEST_STALE','stale conflita');
select extensions.lives_ok($$select public.reject_class_change_request_v1('ac700000-0000-4000-8000-000000000002')$$,'B rejeita stale');
select extensions.lives_ok($$select public.reject_class_change_request_v1('ac700000-0000-4000-8000-000000000002')$$,'retry reject idempotente');
select extensions.ok(pg_temp.raises_state($$select public.approve_class_change_request_v1('ac700000-0000-4000-8000-000000000004')$$,'P0001'),'canceled nao aprova');
reset role;
select extensions.is((select class_id from public.students where id='ac300000-0000-4000-8000-000000000002'),'ac200000-0000-4000-8000-000000000003'::uuid,'stale/reject/cancel preservam turma recente');
select extensions.is((select status from public.class_change_requests where id='ac700000-0000-4000-8000-000000000003'),'PENDING','stale nao vira status persistido');
select extensions.is((select count(*) from public.audit_logs where action in ('CLASS_CHANGE_REQUEST_REJECTED_V1','CLASS_CHANGE_REQUEST_CANCELED_V1') and school_id='ac100000-0000-4000-8000-000000000001'),2::bigint,'retries reject/cancel nao duplicam logs');

-- Falha de auditoria aborta aprovacao e criacao por inteiro.
create function pg_temp.fail_audit() returns trigger language plpgsql as $$begin raise exception 'audit unavailable'; end;$$;
create trigger test_request_audit_failure before insert on public.audit_logs for each row execute function pg_temp.fail_audit();
select set_config('request.jwt.claim.sub','ac900000-0000-4000-8000-000000000002',true);
select extensions.ok(pg_temp.raises_state($$select public.update_admin_student_v1('ac300000-0000-4000-8000-000000000002','Segundo',null,'002','ac200000-0000-4000-8000-000000000001','ACTIVE')$$,'P0001'),'auditoria tambem continua transacional na troca direta');
-- Usa aluno na origem capturada para provar rollback de uma aprovacao valida.
update public.students set class_id='ac200000-0000-4000-8000-000000000001' where id='ac300000-0000-4000-8000-000000000002';
select extensions.throws_ok($$select public.approve_class_change_request_v1('ac700000-0000-4000-8000-000000000003')$$,'P0001','audit unavailable','falha de audit aborta aprovacao');
select extensions.is((select status from public.class_change_requests where id='ac700000-0000-4000-8000-000000000003'),'PENDING','request rollback');
select extensions.is((select class_id from public.students where id='ac300000-0000-4000-8000-000000000002'),'ac200000-0000-4000-8000-000000000001'::uuid,'aluno rollback');
select set_config('request.jwt.claim.sub','ac900000-0000-4000-8000-000000000003',true);
select extensions.throws_ok($$select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000008','ac300000-0000-4000-8000-000000000002','ac200000-0000-4000-8000-000000000002')$$,'P0001','audit unavailable','falha de audit aborta criacao');
select extensions.is((select count(*) from public.class_change_requests where id='ac700000-0000-4000-8000-000000000008'),0::bigint,'criacao rollback');
drop trigger test_request_audit_failure on public.audit_logs;
select extensions.ok(pg_temp.raises_state(format('select set_config(''request.jwt.claim.sub'',%L,true); set local role authenticated; select * from public.get_class_change_requests_v1()',uid),'42501'),'sem acesso '||label) from (values('ac900000-0000-4000-8000-000000000001','A'),('ac900000-0000-4000-8000-000000000006','inativo'),('ac900000-0000-4000-8000-000000000008','sem admin'),('','sem uid')) identities(uid,label);
select set_config('request.jwt.claim.sub','ac900000-0000-4000-8000-000000000001',true);
select extensions.ok(pg_temp.raises_state($$select public.create_class_change_request_v1('ac700000-0000-4000-8000-000000000008','ac300000-0000-4000-8000-000000000001','ac200000-0000-4000-8000-000000000002')$$,'42501'),'A nao cria');
select extensions.ok(pg_temp.raises_state($$select public.approve_class_change_request_v1('ac700000-0000-4000-8000-000000000003')$$,'42501'),'A nao decide');
select * from extensions.finish();
rollback;
