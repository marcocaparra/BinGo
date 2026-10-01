begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();
create function pg_temp.raises_state(command text, expected_state text)
returns boolean language plpgsql as $$
begin execute command; return false;
exception when others then return sqlstate = expected_state; end;
$$;

insert into public.schools(id,name) values
 ('ab100000-0000-4000-8000-000000000001','School management 1'),
 ('ab100000-0000-4000-8000-000000000002','School management 2');
insert into public.classes(id,school_id,segment,grade,name,points_class_balance) values
 ('ab200000-0000-4000-8000-000000000001','ab100000-0000-4000-8000-000000000001','Livre','1','Original',123),
 ('ab200000-0000-4000-8000-000000000002','ab100000-0000-4000-8000-000000000001','Livre','2','Destino',456),
 ('ab200000-0000-4000-8000-000000000003','ab100000-0000-4000-8000-000000000002','Livre','1','Outra escola',789);
insert into public.students(id,school_id,class_id,name,registration,email,points_student_balance,auth_user_id,pin_hash,is_activated) values
 ('ab300000-0000-4000-8000-000000000001','ab100000-0000-4000-8000-000000000001','ab200000-0000-4000-8000-000000000001','Historico','001','original@example.test',888,'ab900000-0000-4000-8000-000000000009','protected-pin',true),
 ('ab300000-0000-4000-8000-000000000002','ab100000-0000-4000-8000-000000000002','ab200000-0000-4000-8000-000000000003','Outra escola','001',null,999,null,null,false);
insert into public.admins(id,school_id,name,email,role,auth_user_id,status) values
 ('ab400000-0000-4000-8000-000000000001',null,'A','a@school.test','ADMIN_A','ab900000-0000-4000-8000-000000000001','ACTIVE'),
 ('ab400000-0000-4000-8000-000000000002','ab100000-0000-4000-8000-000000000001','B','b@school.test','ADMIN_B','ab900000-0000-4000-8000-000000000002','ACTIVE'),
 ('ab400000-0000-4000-8000-000000000003','ab100000-0000-4000-8000-000000000001','C','c@school.test','ADMIN_C','ab900000-0000-4000-8000-000000000003','ACTIVE'),
 ('ab400000-0000-4000-8000-000000000004','ab100000-0000-4000-8000-000000000001','Inactive','inactive@school.test','ADMIN_B','ab900000-0000-4000-8000-000000000004','INACTIVE'),
 ('ab400000-0000-4000-8000-000000000005','ab100000-0000-4000-8000-000000000002','B2','b2@school.test','ADMIN_B','ab900000-0000-4000-8000-000000000005','ACTIVE');

insert into public.machines(id,school_id,name,status) values
 ('ab500000-0000-4000-8000-000000000001','ab100000-0000-4000-8000-000000000001','Historical machine','ONLINE');
insert into public.deposits(event_id,school_id,machine_id,class_id,student_id,is_valid,points_awarded_student,points_awarded_class,waste_category_id,category_source)
 values('ab600000-0000-4000-8000-000000000001','ab100000-0000-4000-8000-000000000001','ab500000-0000-4000-8000-000000000001','ab200000-0000-4000-8000-000000000001','ab300000-0000-4000-8000-000000000001',true,800,1900,(select id from public.waste_categories where code='PERIPHERAL'),'AI_CONFIRMED');
create temporary table historical_deposit as select * from public.deposits where event_id='ab600000-0000-4000-8000-000000000001';

select extensions.has_column('public','students','registration','registration existe');
select extensions.has_column('public','students','email','email existe');
select extensions.hasnt_column('public','classes','status','turma nao possui status');
select extensions.ok(pg_temp.raises_state($$insert into public.students(school_id,class_id,name,registration) values('ab100000-0000-4000-8000-000000000001','ab200000-0000-4000-8000-000000000001','Duplicado','001')$$,'23505'),'duplicado na mesma escola falha');
select extensions.is((select count(*) from public.students where registration='001'),2::bigint,'matricula repetida em escolas distintas permitida');
select extensions.lives_ok($$insert into public.students(school_id,class_id,name) values('ab100000-0000-4000-8000-000000000001','ab200000-0000-4000-8000-000000000001','Null historico 1'),('ab100000-0000-4000-8000-000000000001','ab200000-0000-4000-8000-000000000001','Null historico 2')$$,'varios NULL historicos permitidos');
select extensions.ok(pg_temp.raises_state(format('update public.students set registration=%L where id=%L',v,'ab300000-0000-4000-8000-000000000001'),'23514'),'matricula sem whitespace ambiguo: ' || v) from (values(''),(' '),(E'\t'),(' 001 ')) t(v);
select extensions.ok(pg_temp.raises_state($$update public.students set email=' ' where id='ab300000-0000-4000-8000-000000000001'$$,'23514'),'email vazio rejeitado');

select extensions.ok(p.prosecdef and p.proconfig=array['search_path=""'],'search_path controlado: '||p.proname)
from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('require_school_admin_v1','get_admin_students_v1','get_admin_classes_v1','create_admin_student_v1','update_admin_student_v1','create_admin_class_v1','update_admin_class_v1');
select extensions.ok(not has_function_privilege('anon',p.oid,'execute') and has_function_privilege('authenticated',p.oid,'execute') and not has_function_privilege('service_role',p.oid,'execute'),'grant exclusivo authenticated: '||p.proname)
from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('get_admin_students_v1','get_admin_classes_v1','create_admin_student_v1','update_admin_student_v1','create_admin_class_v1','update_admin_class_v1');
select extensions.ok(not has_function_privilege('authenticated','public.require_school_admin_v1(boolean)','execute'),'helper inacessivel ao cliente');
select extensions.ok(pg_temp.raises_state('set local role anon; select * from public.get_admin_students_v1()','42501'),'anon realmente nao executa');
select extensions.ok(pg_temp.raises_state('set local role authenticated; select * from public.require_school_admin_v1(false)','42501'),'cliente nao invoca helper');
select extensions.ok(not has_table_privilege('authenticated','public.'||t,'insert') and not has_table_privilege('authenticated','public.'||t,'update') and not has_table_privilege('authenticated','public.'||t,'delete'),'sem escrita direta em '||t) from (values('students'),('classes'),('admins'),('audit_logs')) tables(t);
select extensions.ok(not has_table_privilege('authenticated','public.students','select') and not has_column_privilege('authenticated','public.students','email','select') and not has_column_privilege('authenticated','public.students','registration','select'),'nao amplia leitura Mobile');
select extensions.is((select count(*) from pg_policies where schemaname='public'),5::bigint,'baseline de cinco policies preservado');
select extensions.is(pg_get_function_result('public.get_admin_students_v1()'::regprocedure),'TABLE(student_id uuid, name text, email text, registration text, class_id uuid, class_name text, status text, points_student_balance integer, class_points_balance integer)','retorno nao expoe dados tecnicos');
select extensions.ok(not exists(select 1 from pg_proc p cross join unnest(p.proargnames[1:p.pronargs]) n where p.pronamespace='public'::regnamespace and p.proname in ('get_admin_students_v1','get_admin_classes_v1','create_admin_student_v1','update_admin_student_v1','create_admin_class_v1','update_admin_class_v1') and n in ('p_school_id','p_actor_id','p_admin_id','p_role','p_points_student_balance','p_pin_hash','p_auth_user_id','p_is_activated','p_points_class_balance')),'contratos nao aceitam autoridade/economia/credenciais');

select set_config('request.jwt.claim.sub','ab900000-0000-4000-8000-000000000002',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_admin_students_v1()),3::bigint,'B ve somente tres alunos da escola');
select extensions.results_eq($$select class_id from public.get_admin_classes_v1() order by class_id$$,$$values ('ab200000-0000-4000-8000-000000000001'::uuid),('ab200000-0000-4000-8000-000000000002'::uuid)$$,'B ve somente suas turmas');
select extensions.is((select student_count from public.get_admin_classes_v1() where class_id='ab200000-0000-4000-8000-000000000001'),3::bigint,'contagem autoritativa');
select extensions.is((select count(*) from public.students),0::bigint,'admin nao ganha SELECT escolar direto pela policy Mobile');
select extensions.ok(pg_temp.raises_state($$select public.create_admin_student_v1('Aluno',null,'004','ab200000-0000-4000-8000-000000000003')$$,'42501'),'B nao usa turma externa');
select extensions.ok(pg_temp.raises_state($$select public.update_admin_student_v1('ab300000-0000-4000-8000-000000000002','Forjado',null,'004','ab200000-0000-4000-8000-000000000001','ACTIVE')$$,'42501'),'B nao altera aluno externo');
select extensions.ok(pg_temp.raises_state($$select public.update_admin_student_v1('ab300000-0000-4000-8000-000000000001','Forjado',null,'004','ab200000-0000-4000-8000-000000000003','ACTIVE')$$,'42501'),'B nao move aluno proprio para turma externa');
select extensions.ok(pg_temp.raises_state($$select public.update_admin_class_v1('ab200000-0000-4000-8000-000000000003','s','g','Forjada')$$,'42501'),'B nao altera turma externa');
select extensions.ok(pg_temp.raises_state($$select public.create_admin_student_v1('Aluno',null,'001','ab200000-0000-4000-8000-000000000001')$$,'23505'),'RPC duplicado previsivel');
select extensions.throws_ok($$select public.create_admin_student_v1('Aluno',null,' 001 ','ab200000-0000-4000-8000-000000000001')$$,'23505','ADMIN_REGISTRATION_CONFLICT','whitespace nao contorna unicidade');
select extensions.ok(pg_temp.raises_state($$select public.create_admin_student_v1(' ',null,'004','ab200000-0000-4000-8000-000000000001')$$,'22023'),'nome vazio rejeitado');
select extensions.ok(pg_temp.raises_state($$select public.create_admin_student_v1('Aluno',null,E'\t','ab200000-0000-4000-8000-000000000001')$$,'22023'),'RA whitespace rejeitado');
select extensions.ok(pg_temp.raises_state($$select public.create_admin_student_v1('Aluno',' ','004','ab200000-0000-4000-8000-000000000001')$$,'22023'),'email informado vazio rejeitado');
select extensions.ok(pg_temp.raises_state($$select public.create_admin_student_v1('Aluno',null,'004','ab200000-0000-4000-8000-000000000001','INVALID')$$,'22023'),'status invalido rejeitado');
select extensions.lives_ok($$select public.create_admin_student_v1('  Novo  ',null,' 004 ','ab200000-0000-4000-8000-000000000001')$$,'B cria sem credencial');
select extensions.lives_ok($$select public.update_admin_student_v1('ab300000-0000-4000-8000-000000000001','Editado','novo@example.test','0001','ab200000-0000-4000-8000-000000000002','INACTIVE')$$,'B edita dados/turma/status');
select extensions.lives_ok($$select public.create_admin_class_v1('Segmento livre','Serie livre','Nova turma')$$,'B cria estrutura textual livre');
select extensions.lives_ok($$select public.update_admin_class_v1('ab200000-0000-4000-8000-000000000002','Novo segmento','Nova serie','Destino editado')$$,'B edita turma');
reset role;
select extensions.results_eq($$select school_id,registration,email,points_student_balance,pin_hash,auth_user_id,is_activated from public.students where name='Novo'$$,$$values ('ab100000-0000-4000-8000-000000000001'::uuid,'004'::text,null::text,0,null::text,null::uuid,false)$$,'novo na escola derivada com defaults protegidos');
select extensions.results_eq($$select name,email,registration,class_id,status,points_student_balance,pin_hash,auth_user_id,is_activated from public.students where id='ab300000-0000-4000-8000-000000000001'$$,$$values ('Editado'::text,'novo@example.test'::text,'0001'::text,'ab200000-0000-4000-8000-000000000002'::uuid,'INACTIVE'::text,888,'protected-pin'::text,'ab900000-0000-4000-8000-000000000009'::uuid,true)$$,'update preserva saldo/PIN/Auth/ativacao e IDs');
select extensions.is((select points_class_balance from public.classes where name='Nova turma'),0,'nova turma XP default zero');
select extensions.is((select points_class_balance from public.classes where id='ab200000-0000-4000-8000-000000000002'),456,'update nao muda XP');
select extensions.results_eq($$select * from public.deposits where event_id='ab600000-0000-4000-8000-000000000001'$$,$$select * from historical_deposit$$,'troca atual preserva fotografia completa do deposito historico');
select extensions.is((select count(*) from public.audit_logs where actor_id='ab400000-0000-4000-8000-000000000002'),4::bigint,'uma auditoria por mutation, falhas sem eventos parciais');
select extensions.is((select count(distinct action) from public.audit_logs where actor_id='ab400000-0000-4000-8000-000000000002'),4::bigint,'audita criacao e edicao de alunos e turmas');
select extensions.ok((select actor_type='ADMIN' and school_id='ab100000-0000-4000-8000-000000000001' and metadata#>>'{old,class_id}'='ab200000-0000-4000-8000-000000000001' and metadata#>>'{new,class_id}'='ab200000-0000-4000-8000-000000000002' and metadata#>>'{old,status}'='ACTIVE' and metadata#>>'{new,status}'='INACTIVE' from public.audit_logs where actor_id='ab400000-0000-4000-8000-000000000002' and action='ADMIN_STUDENT_UPDATED_V1'),'auditoria ator derivado e old/new turma/status');

create function pg_temp.fail_audit() returns trigger language plpgsql as $$begin raise exception 'audit unavailable'; end;$$;
create trigger test_audit_failure before insert on public.audit_logs for each row execute function pg_temp.fail_audit();
select extensions.ok(pg_temp.raises_state($$select public.update_admin_student_v1('ab300000-0000-4000-8000-000000000001','Nao persistir',null,'0001','ab200000-0000-4000-8000-000000000001','ACTIVE')$$,'P0001'),'falha da auditoria aborta update');
select extensions.ok(pg_temp.raises_state($$select public.create_admin_student_v1('Nao persistir',null,'005','ab200000-0000-4000-8000-000000000001')$$,'P0001'),'falha da auditoria aborta create');
select extensions.ok(pg_temp.raises_state($$select public.create_admin_class_v1('s','g','Nao persistir')$$,'P0001'),'falha da auditoria aborta create turma');
select extensions.ok(pg_temp.raises_state($$select public.update_admin_class_v1('ab200000-0000-4000-8000-000000000002','s','g','Nao persistir')$$,'P0001'),'falha da auditoria aborta update turma');
select extensions.is((select name from public.students where id='ab300000-0000-4000-8000-000000000001'),'Editado','update revertido junto com auditoria');
select extensions.is((select count(*) from public.students where registration='005'),0::bigint,'create revertido junto com auditoria');
select extensions.is((select count(*) from public.classes where name='Nao persistir'),0::bigint,'mutations de turma revertidas junto com auditoria');
drop trigger test_audit_failure on public.audit_logs;

select set_config('request.jwt.claim.sub','ab900000-0000-4000-8000-000000000003',true);
set local role authenticated;
select extensions.is((select count(*) from public.get_admin_students_v1()),4::bigint,'C ve somente alunos da escola');
select extensions.results_eq($$select points_student_balance,class_points_balance,status from public.get_admin_students_v1() where student_id='ab300000-0000-4000-8000-000000000001'$$,$$values (888,456,'INACTIVE'::text)$$,'C recebe saldo/XP/status em leitura');
select extensions.is((select count(*) from public.get_admin_classes_v1()),3::bigint,'C consulta lookup de turmas da escola');
select extensions.ok(pg_temp.raises_state($$select public.create_admin_student_v1('Forjado',null,'006','ab200000-0000-4000-8000-000000000001')$$,'42501'),'C nao cria aluno');
select extensions.ok(pg_temp.raises_state($$select public.update_admin_student_v1('ab300000-0000-4000-8000-000000000001','Forjado',null,'006','ab200000-0000-4000-8000-000000000001','ACTIVE')$$,'42501'),'C nao edita aluno');
select extensions.ok(pg_temp.raises_state($$select public.create_admin_class_v1('s','g','Forjada')$$,'42501'),'C nao cria turma');
select extensions.ok(pg_temp.raises_state($$select public.update_admin_class_v1('ab200000-0000-4000-8000-000000000001','s','g','Forjada')$$,'42501'),'C nao edita turma');
reset role;

select set_config('request.jwt.claim.sub','ab900000-0000-4000-8000-000000000005',true);
set local role authenticated;
select extensions.results_eq($$select student_id from public.get_admin_students_v1()$$,$$values ('ab300000-0000-4000-8000-000000000002'::uuid)$$,'segunda escola isolada');
reset role;
select extensions.ok(pg_temp.raises_state(format('select set_config(''request.jwt.claim.sub'',%L,true); set local role authenticated; select * from public.get_admin_students_v1()', uid),'42501'),'sem leitura escolar: '||label)
from (values('ab900000-0000-4000-8000-000000000001','ADMIN_A sem escola alvo'),('ab900000-0000-4000-8000-000000000004','admin inativo'),('ab900000-0000-4000-8000-000000000008','Auth sem admin'),('','sem auth.uid')) identities(uid,label);
select extensions.ok(pg_temp.raises_state(format('select set_config(''request.jwt.claim.sub'',%L,true); set local role authenticated; select * from public.get_admin_classes_v1()', uid),'42501'),'sem turmas: '||label)
from (values('ab900000-0000-4000-8000-000000000001','ADMIN_A'),('ab900000-0000-4000-8000-000000000004','inativo'),('ab900000-0000-4000-8000-000000000008','sem admin')) identities(uid,label);
select * from extensions.finish();
rollback;
