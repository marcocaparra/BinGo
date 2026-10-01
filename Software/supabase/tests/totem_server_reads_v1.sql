begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();
select extensions.ok(p.prosecdef and p.proconfig @> array['search_path=""'] and
    not has_function_privilege('anon', p.oid, 'execute') and
    not has_function_privilege('authenticated', p.oid, 'execute') and
    has_function_privilege('service_role', p.oid, 'execute'), p.proname || ' server-only seguro')
from pg_proc p where p.proname in ('get_totem_context_v1','get_totem_student_pin_record_v1',
    'get_totem_student_summary_v1','get_totem_rankings_v1');
select extensions.ok(not has_column_privilege('authenticated','public.students','pin_hash','select')
    and not has_column_privilege('anon','public.students','pin_hash','select')
    and not has_column_privilege('service_role','public.students','pin_hash','select'), 'Hash sem SELECT direto');
select extensions.ok(not has_table_privilege('authenticated','public.deposits','INSERT,UPDATE,DELETE'), 'Sem escrita direta');
select extensions.ok((select relrowsecurity from pg_class where oid='public.students'::regclass), 'RLS preservado');

insert into public.schools(id,name) values ('11111111-1111-4111-8111-111111111111','Outra escola');
insert into public.classes(id,school_id,segment,grade,name) values
    ('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','Teste','1','Outra turma');
insert into public.students(id,school_id,class_id,name,status) values
    ('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Outro aluno','ACTIVE');
update public.students set status='INACTIVE', is_activated=false where id='30000000-0000-4000-8000-000000000002';
update public.students set is_activated=false where id='30000000-0000-4000-8000-000000000001';
update public.machines set status='OFFLINE' where id='40000000-0000-4000-8000-000000000001';
create temp table context_snapshot as select public.get_totem_context_v1('40000000-0000-4000-8000-000000000001') as body;
select extensions.is((select body->'school'->>'id' from context_snapshot),'10000000-0000-4000-8000-000000000001','Contexto da escola da maquina');
select extensions.ok((select body::text not like '%Outra%' and body::text not like '%Bruno Valente%' from context_snapshot), 'Outra escola e INACTIVE invisiveis no contexto');
select extensions.ok((select body::text not like '%pin_hash%' and body::text not like '%auth_user_id%' and body::text not like '%email%' and body::text not like '%registration%' from context_snapshot), 'Projecao publica minima');
select extensions.ok(public.get_totem_student_pin_record_v1('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001')->>'pin_hash' is not null, 'PIN ACTIVE independente de is_activated e machine.status');
select extensions.ok(public.get_totem_student_pin_record_v1('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002') is null, 'PIN INACTIVE bloqueado');
select extensions.ok(public.get_totem_student_pin_record_v1('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000001') is null, 'Turma divergente bloqueada');
select extensions.ok(public.get_totem_student_pin_record_v1('40000000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333') is null, 'PIN cross-school bloqueado');
select extensions.ok(public.get_totem_student_summary_v1('40000000-0000-4000-8000-000000000001','33333333-3333-4333-8333-333333333333') is null, 'Resumo cross-school bloqueado');
select extensions.ok(public.get_totem_context_v1('49999999-9999-4999-8999-999999999999') is null, 'Maquina inexistente sem contexto');
select extensions.ok(public.get_totem_rankings_v1('40000000-0000-4000-8000-000000000001')::text like '%Bruno Valente%', 'Ranking preserva INACTIVE legado');
select extensions.ok(public.get_totem_rankings_v1('40000000-0000-4000-8000-000000000001')::text not like '%Outro aluno%', 'Ranking somente escola');
select extensions.throws_ok($$set local role authenticated; select public.get_totem_student_pin_record_v1('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001');$$, '42501','permission denied for function get_totem_student_pin_record_v1','Browser nao executa RPC de hash');
select * from extensions.finish();
rollback;
