-- BinGo V1
-- Seed: 009_remote_dev_smoke_test.sql
--
-- Fixture mínima para smoke tests no projeto hospedado bingo-dev.
--
-- Objetivos:
--   1. testar autenticação técnica da máquina;
--   2. testar health-v1;
--   3. testar register-deposit-v1;
--   4. testar pontuação e idempotência remotamente.
--
-- IMPORTANTE:
-- - somente para ambiente de desenvolvimento;
-- - não contém a API key da máquina em texto puro;
-- - substitua __REPLACE_WITH_PBKDF2_HASH__ antes de executar;
-- - esta seed não cria usuários em auth.users;
-- - a execução repetida não deve zerar saldos já acumulados.

begin;


-- ============================================================
-- Escola de desenvolvimento
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
    updated_at = now();


-- ============================================================
-- Configurações da escola
-- ============================================================

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
    800,
    1900,
    10000,
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
    updated_at = now();


-- ============================================================
-- Bônus provisórios EXCLUSIVOS de desenvolvimento
-- ============================================================

update public.waste_categories
set
    bonus_rate = case code
        when 'BATTERY' then 1.0000
        when 'MOBILE_DEVICE' then 0.5000
        when 'CABLE_WIRE' then 0.2500
        else 0
    end,
    updated_at = now();


-- ============================================================
-- Turma mínima para teste
-- ============================================================

insert into public.classes (
    id,
    school_id,
    segment,
    grade,
    name,
    points_class_balance
)
values (
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'FUNDAMENTAL_2',
    '6',
    '6º Ano A',
    0
)
on conflict (id) do update
set
    school_id = excluded.school_id,
    segment = excluded.segment,
    grade = excluded.grade,
    name = excluded.name,
    updated_at = now();


-- ============================================================
-- Aluno mínimo para teste de descarte identificado
--
-- auth_user_id fica sem vínculo por enquanto.
-- O vínculo com Supabase Auth será feito quando formos testar o Mobile.
-- ============================================================

insert into public.students (
    id,
    school_id,
    class_id,
    name,
    pin_hash,
    is_activated,
    points_student_balance,
    status
)
values (
    '30000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'Aluno Smoke Test',
    null,
    false,
    0,
    'ACTIVE'
)
on conflict (id) do update
set
    school_id = excluded.school_id,
    class_id = excluded.class_id,
    name = excluded.name,
    status = excluded.status,
    updated_at = now();


-- ============================================================
-- Máquina de desenvolvimento
--
-- X-Machine-Id:
-- 40000000-0000-4000-8000-000000000001
--
-- NÃO coloque a X-Api-Key em texto puro neste arquivo.
-- Substitua abaixo apenas pelo hash PBKDF2 gerado localmente.
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
    status = excluded.status,
    firmware_version = excluded.firmware_version,
    bin_full = excluded.bin_full,
    camera_ok = excluded.camera_ok,
    net_ok = excluded.net_ok,
    api_key_hash = excluded.api_key_hash,
    updated_at = now();


commit;
