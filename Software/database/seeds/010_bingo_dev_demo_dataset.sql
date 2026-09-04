-- BinGo V1
-- Seed: 010_bingo_dev_demo_dataset.sql
--
-- Dataset de demonstracao do projeto hospedado bingo-dev.
--
-- Esta seed e complementar a 009_remote_dev_smoke_test.sql:
-- - preserva os UUIDs da escola, primeira turma, aluno smoke e maquina;
-- - amplia a escola demo para 7 turmas e 70 alunos (10 por turma);
-- - nao cria usuarios em auth.users;
-- - nao altera auth_user_id, PINs, ativacao, saldos ou a credencial de uma
--   maquina que ja exista;
-- - nao cria descartes, resgates, rankings, missoes ou historico;
-- - nao remove dados.
--
-- Turmas e alunos adicionais ficam fora do conjunto deterministico validado
-- por esta seed e sao preservados sem impedir sua reexecucao.

begin;


-- ============================================================
-- Fotografias de estado que a seed nao pode alterar
-- ============================================================

create temporary table bingo_dev_seed_auth_before
on commit drop
as
select id, auth_user_id
from public.students;

create temporary table bingo_dev_seed_student_balances_before
on commit drop
as
select id, points_student_balance
from public.students
where school_id = '10000000-0000-4000-8000-000000000001';

create temporary table bingo_dev_seed_class_balances_before
on commit drop
as
select id, points_class_balance
from public.classes
where school_id = '10000000-0000-4000-8000-000000000001';

create temporary table bingo_dev_seed_machine_credentials_before
on commit drop
as
select id, api_key_hash
from public.machines
where id = '40000000-0000-4000-8000-000000000001';

do $$
begin
    if exists (
        select 1
        from public.classes
        where id in (
            select ('20000000-0000-4000-8000-' || lpad(class_number::text, 12, '0'))::uuid
            from generate_series(1, 7) as generated(class_number)
        )
          and school_id <> '10000000-0000-4000-8000-000000000001'
    ) then
        raise exception 'Seed bingo-dev abortada: UUID de turma demo pertence a outra escola.';
    end if;

    if exists (
        select 1
        from public.students
        where id in (
            select ('30000000-0000-4000-8000-' || lpad(student_number::text, 12, '0'))::uuid
            from generate_series(1, 70) as generated(student_number)
        )
          and school_id <> '10000000-0000-4000-8000-000000000001'
    ) then
        raise exception 'Seed bingo-dev abortada: UUID de aluno demo pertence a outra escola.';
    end if;

    if exists (
        select 1
        from public.machines
        where id = '40000000-0000-4000-8000-000000000001'
          and school_id <> '10000000-0000-4000-8000-000000000001'
    ) then
        raise exception 'Seed bingo-dev abortada: UUID da maquina DEV pertence a outra escola.';
    end if;
end;
$$;


-- ============================================================
-- Escola e configuracoes vigentes
-- ============================================================

insert into public.schools (
    id,
    name
)
values (
    '10000000-0000-4000-8000-000000000001',
    'Escola Demo BinGo'
)
on conflict (id) do update
set
    name = excluded.name,
    updated_at = now()
where public.schools.name is distinct from excluded.name;

insert into public.school_settings (
    school_id,
    deposit_bincoins_base,
    deposit_class_xp_base,
    class_weekly_xp_goal,
    redemption_expiration_hours,
    redemption_daily_limit,
    redemption_max_pending
)
values (
    '10000000-0000-4000-8000-000000000001',
    8,
    19,
    100,
    72,
    3,
    3
)
on conflict (school_id) do update
set
    deposit_bincoins_base = excluded.deposit_bincoins_base,
    deposit_class_xp_base = excluded.deposit_class_xp_base,
    class_weekly_xp_goal = excluded.class_weekly_xp_goal,
    redemption_expiration_hours = excluded.redemption_expiration_hours,
    redemption_daily_limit = excluded.redemption_daily_limit,
    redemption_max_pending = excluded.redemption_max_pending,
    updated_at = now()
where (
    public.school_settings.deposit_bincoins_base,
    public.school_settings.deposit_class_xp_base,
    public.school_settings.class_weekly_xp_goal,
    public.school_settings.redemption_expiration_hours,
    public.school_settings.redemption_daily_limit,
    public.school_settings.redemption_max_pending
) is distinct from (
    excluded.deposit_bincoins_base,
    excluded.deposit_class_xp_base,
    excluded.class_weekly_xp_goal,
    excluded.redemption_expiration_hours,
    excluded.redemption_daily_limit,
    excluded.redemption_max_pending
);


-- ============================================================
-- Sete turmas deterministicas
--
-- points_class_balance e omitido no insert e no update. Novas turmas usam
-- o default zero; turmas existentes conservam o XP acumulado.
-- ============================================================

insert into public.classes (
    id,
    school_id,
    segment,
    grade,
    name
)
values
    ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'FUNDAMENTAL_2', '6', U&'6\00BA Ano A'),
    ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'FUNDAMENTAL_2', '7', U&'7\00BA Ano A'),
    ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'FUNDAMENTAL_2', '8', U&'8\00BA Ano A'),
    ('20000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', 'FUNDAMENTAL_2', '9', U&'9\00BA Ano A'),
    ('20000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', 'ENSINO_MEDIO', '1', U&'1\00AA S\00E9rie A'),
    ('20000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001', 'ENSINO_MEDIO', '2', U&'2\00AA S\00E9rie A'),
    ('20000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000001', 'ENSINO_MEDIO', '3', U&'3\00AA S\00E9rie A')
on conflict (id) do update
set
    school_id = excluded.school_id,
    segment = excluded.segment,
    grade = excluded.grade,
    name = excluded.name,
    updated_at = now()
where (
    public.classes.school_id,
    public.classes.segment,
    public.classes.grade,
    public.classes.name
) is distinct from (
    excluded.school_id,
    excluded.segment,
    excluded.grade,
    excluded.name
);


-- ============================================================
-- Setenta alunos deterministas, dez por turma
--
-- O aluno 001 e a fixture smoke da seed 009. Os demais nomes sao gerados de
-- forma deterministica para evitar dados pessoais reais.
--
-- auth_user_id, pin_hash, is_activated e points_student_balance sao omitidos
-- tanto do insert quanto do update. Assim, novos alunos recebem os defaults
-- atuais e qualquer estado existente permanece intacto.
-- ============================================================

with demo_students as (
    select
        student_number,
        ((student_number - 1) / 10) + 1 as class_number,
        case
            when student_number = 1 then 'Aluno Smoke Test'
            else format(
                'Aluno Demo %s %s',
                (array[
                    'Aline', 'Bruno', 'Carla', 'Diego', 'Elisa',
                    'Fabio', 'Giovana', 'Heitor', 'Iara', 'Jonas'
                ])[((student_number - 1) % 10) + 1],
                (array[
                    'Almeida', 'Barbosa', 'Cardoso', 'Duarte',
                    'Esteves', 'Ferreira', 'Gomes'
                ])[((student_number - 1) / 10) + 1]
            )
        end as name
    from generate_series(1, 70) as generated(student_number)
)
insert into public.students (
    id,
    school_id,
    class_id,
    name,
    status
)
select
    ('30000000-0000-4000-8000-' || lpad(student_number::text, 12, '0'))::uuid,
    '10000000-0000-4000-8000-000000000001'::uuid,
    ('20000000-0000-4000-8000-' || lpad(class_number::text, 12, '0'))::uuid,
    name,
    'ACTIVE'
from demo_students
on conflict (id) do update
set
    school_id = excluded.school_id,
    class_id = excluded.class_id,
    name = excluded.name,
    status = excluded.status,
    updated_at = now()
where (
    public.students.school_id,
    public.students.class_id,
    public.students.name,
    public.students.status
) is distinct from (
    excluded.school_id,
    excluded.class_id,
    excluded.name,
    excluded.status
);


-- ============================================================
-- Maquina DEV preservada
--
-- O hash abaixo e o mesmo valor versionado pela fixture smoke 009 e serve
-- somente para criar a maquina quando ela ainda nao existe. Em conflito, a
-- seed nao altera api_key_hash nem o estado operacional existente.
-- ============================================================

insert into public.machines (
    id,
    school_id,
    name,
    status,
    firmware_version,
    bin_full,
    camera_ok,
    net_ok,
    api_key_hash
)
values (
    '40000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'Totem Dev Cloud 01',
    'ONLINE',
    'demo-v0',
    false,
    true,
    true,
    '4CaC2F/9+xw2j2640Tpl3Q==$LGc7MJp9nep4fsg2pegdx3pvnHlePPNRK/DXfEFFXdc='
)
on conflict (id) do update
set
    school_id = excluded.school_id,
    name = excluded.name,
    updated_at = now()
where (
    public.machines.school_id,
    public.machines.name
) is distinct from (
    excluded.school_id,
    excluded.name
);


-- ============================================================
-- Validacoes transacionais
-- ============================================================

do $$
begin
    if (select count(*) from public.schools where name = 'Escola Demo BinGo') <> 1
       or not exists (
           select 1
           from public.schools
           where id = '10000000-0000-4000-8000-000000000001'
             and name = 'Escola Demo BinGo'
       ) then
        raise exception 'Seed bingo-dev invalida: a escola demo esperada nao foi preservada.';
    end if;

    if (
        select count(*)
        from public.classes
        where id in (
            select ('20000000-0000-4000-8000-' || lpad(class_number::text, 12, '0'))::uuid
            from generate_series(1, 7) as generated(class_number)
        )
          and school_id = '10000000-0000-4000-8000-000000000001'
    ) <> 7 then
        raise exception 'Seed bingo-dev invalida: as 7 turmas demo devem existir na escola esperada.';
    end if;

    if (
        select count(*)
        from public.students
        where id in (
            select ('30000000-0000-4000-8000-' || lpad(student_number::text, 12, '0'))::uuid
            from generate_series(1, 70) as generated(student_number)
        )
          and school_id = '10000000-0000-4000-8000-000000000001'
    ) <> 70 then
        raise exception 'Seed bingo-dev invalida: os 70 alunos demo devem existir na escola esperada.';
    end if;

    if exists (
        select 1
        from generate_series(1, 70) as generated(student_number)
        left join public.students as s
          on s.id = ('30000000-0000-4000-8000-' || lpad(student_number::text, 12, '0'))::uuid
        where s.id is null
           or s.school_id <> '10000000-0000-4000-8000-000000000001'
           or s.class_id <> (
               '20000000-0000-4000-8000-'
               || lpad((((student_number - 1) / 10) + 1)::text, 12, '0')
           )::uuid
    ) then
        raise exception 'Seed bingo-dev invalida: aluno demo associado a turma diferente da esperada.';
    end if;

    if exists (
        select 1
        from generate_series(1, 7) as generated(class_number)
        where (
              select count(*)
              from public.students as s
              where s.id in (
                  select ('30000000-0000-4000-8000-' || lpad(student_number::text, 12, '0'))::uuid
                  from generate_series(1, 70) as seed_students(student_number)
              )
                and s.class_id = (
                    '20000000-0000-4000-8000-'
                    || lpad(class_number::text, 12, '0')
                )::uuid
          ) <> 10
    ) then
        raise exception 'Seed bingo-dev invalida: cada turma demo deve possuir exatamente 10 alunos do conjunto da seed.';
    end if;

    if exists (
        select 1
        from bingo_dev_seed_auth_before as before_state
        left join public.students as current_state on current_state.id = before_state.id
        where current_state.id is null
           or current_state.auth_user_id is distinct from before_state.auth_user_id
    ) then
        raise exception 'Seed bingo-dev invalida: um auth_user_id existente foi alterado.';
    end if;

    if exists (
        select 1
        from bingo_dev_seed_student_balances_before as before_state
        left join public.students as current_state on current_state.id = before_state.id
        where current_state.id is null
           or current_state.points_student_balance is distinct from before_state.points_student_balance
    ) then
        raise exception 'Seed bingo-dev invalida: um saldo de aluno existente foi alterado.';
    end if;

    if exists (
        select 1
        from bingo_dev_seed_class_balances_before as before_state
        left join public.classes as current_state on current_state.id = before_state.id
        where current_state.id is null
           or current_state.points_class_balance is distinct from before_state.points_class_balance
    ) then
        raise exception 'Seed bingo-dev invalida: um saldo de turma existente foi alterado.';
    end if;

    if not exists (
        select 1
        from public.machines
        where id = '40000000-0000-4000-8000-000000000001'
          and school_id = '10000000-0000-4000-8000-000000000001'
          and name = 'Totem Dev Cloud 01'
    ) then
        raise exception 'Seed bingo-dev invalida: a maquina DEV esperada nao foi preservada.';
    end if;

    if exists (
        select 1
        from bingo_dev_seed_machine_credentials_before as before_state
        join public.machines as current_state on current_state.id = before_state.id
        where current_state.api_key_hash is distinct from before_state.api_key_hash
    ) then
        raise exception 'Seed bingo-dev invalida: a credencial existente da maquina DEV foi alterada.';
    end if;
end;
$$;

commit;


-- Resumo de conferencia. A preservacao de auth_user_id, saldos e credencial
-- e comprovada pelas validacoes transacionais acima, que abortam em divergencia.
select
    (select count(*) from public.schools where name = 'Escola Demo BinGo') as demo_schools,
    (
        select count(*)
        from public.classes
        where id in (
            select ('20000000-0000-4000-8000-' || lpad(class_number::text, 12, '0'))::uuid
            from generate_series(1, 7) as generated(class_number)
        )
    ) as demo_classes,
    (
        select count(*)
        from public.students
        where id in (
            select ('30000000-0000-4000-8000-' || lpad(student_number::text, 12, '0'))::uuid
            from generate_series(1, 70) as generated(student_number)
        )
    ) as demo_students,
    (select count(*) from public.machines where id = '40000000-0000-4000-8000-000000000001' and name = 'Totem Dev Cloud 01') as dev_machines;
