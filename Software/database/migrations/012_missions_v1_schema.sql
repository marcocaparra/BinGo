-- BinGo V1
-- Migration: 012_missions_v1_schema.sql
--
-- Cria somente a fundacao estrutural de Missoes V1. Progresso continua
-- derivado de deposits.created_at; processamento, saldos e auditoria ficam
-- para migrations posteriores.

begin;

create table public.mission_definitions (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    title text not null,
    description text,
    scope text not null,
    metric text not null,
    recurrence text not null,
    target bigint not null,
    reward_bincoins integer not null default 0,
    reward_xp integer not null default 0,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint mission_definitions_scope_check
        check (scope in ('STUDENT', 'CLASS')),
    constraint mission_definitions_metric_check
        check (metric in ('VALID_DEPOSIT_COUNT', 'CLASS_XP_EARNED')),
    constraint mission_definitions_recurrence_check
        check (recurrence in ('MONTHLY')),
    constraint mission_definitions_scope_metric_check
        check (
            (scope = 'STUDENT' and metric = 'VALID_DEPOSIT_COUNT')
            or
            (scope = 'CLASS' and metric = 'CLASS_XP_EARNED')
        ),
    constraint mission_definitions_target_check
        check (target > 0),
    constraint mission_definitions_reward_bincoins_check
        check (reward_bincoins >= 0),
    constraint mission_definitions_reward_xp_check
        check (reward_xp >= 0),
    constraint mission_definitions_reward_required_check
        check (reward_bincoins > 0 or reward_xp > 0)
);

comment on table public.mission_definitions is
    'Catalogo global de templates de Missoes V1. Nao pertence a uma escola.';

create table public.mission_cycles (
    id uuid primary key default gen_random_uuid(),
    definition_id uuid not null
        references public.mission_definitions(id) on delete restrict,
    school_id uuid not null
        references public.schools(id) on delete restrict,
    starts_at timestamptz not null,
    ends_at timestamptz not null,
    timezone text not null default 'America/Sao_Paulo',
    scope text not null,
    metric text not null,
    recurrence text not null,
    target bigint not null,
    reward_bincoins integer not null,
    reward_xp integer not null,
    created_at timestamptz not null default now(),
    constraint mission_cycles_id_scope_unique unique (id, scope),
    constraint mission_cycles_definition_school_period_unique
        unique (definition_id, school_id, starts_at),
    constraint mission_cycles_period_order_check
        check (starts_at < ends_at),
    constraint mission_cycles_timezone_check
        check (timezone = 'America/Sao_Paulo'),
    constraint mission_cycles_scope_check
        check (scope in ('STUDENT', 'CLASS')),
    constraint mission_cycles_metric_check
        check (metric in ('VALID_DEPOSIT_COUNT', 'CLASS_XP_EARNED')),
    constraint mission_cycles_recurrence_check
        check (recurrence in ('MONTHLY')),
    constraint mission_cycles_scope_metric_check
        check (
            (scope = 'STUDENT' and metric = 'VALID_DEPOSIT_COUNT')
            or
            (scope = 'CLASS' and metric = 'CLASS_XP_EARNED')
        ),
    constraint mission_cycles_target_check
        check (target > 0),
    constraint mission_cycles_reward_bincoins_check
        check (reward_bincoins >= 0),
    constraint mission_cycles_reward_xp_check
        check (reward_xp >= 0),
    constraint mission_cycles_reward_required_check
        check (reward_bincoins > 0 or reward_xp > 0),
    constraint mission_cycles_monthly_period_check
        check (
            (starts_at at time zone timezone)
                = date_trunc('month', starts_at at time zone timezone)
            and
            (ends_at at time zone timezone)
                = date_trunc('month', starts_at at time zone timezone)
                    + interval '1 month'
        )
);

comment on table public.mission_cycles is
    'Snapshot historico e imutavel por contrato de uma definicao para uma escola e periodo.';

create index idx_mission_cycles_school_period
    on public.mission_cycles(school_id, starts_at, ends_at);

create table public.mission_completions (
    id uuid primary key default gen_random_uuid(),
    cycle_id uuid not null,
    participant_scope text not null,
    student_id uuid references public.students(id) on delete restrict,
    class_id uuid references public.classes(id) on delete restrict,
    progress_at_completion bigint not null,
    achieved_at timestamptz not null,
    materialized_at timestamptz not null default now(),
    constraint mission_completions_cycle_scope_fk
        foreign key (cycle_id, participant_scope)
        references public.mission_cycles(id, scope)
        on delete restrict,
    constraint mission_completions_participant_scope_check
        check (participant_scope in ('STUDENT', 'CLASS')),
    constraint mission_completions_participant_check
        check (
            (
                participant_scope = 'STUDENT'
                and student_id is not null
                and class_id is null
            )
            or
            (
                participant_scope = 'CLASS'
                and class_id is not null
                and student_id is null
            )
        ),
    constraint mission_completions_progress_check
        check (progress_at_completion > 0),
    constraint mission_completions_materialized_after_achieved_check
        check (materialized_at >= achieved_at)
);

comment on table public.mission_completions is
    'Conclusao materializada por participante; nao representa progresso mutavel.';
comment on column public.mission_completions.participant_scope is
    'Deve coincidir com o snapshot de scope do ciclo por FK composta.';

create unique index mission_completions_cycle_student_unique
    on public.mission_completions(cycle_id, student_id)
    where student_id is not null;

create unique index mission_completions_cycle_class_unique
    on public.mission_completions(cycle_id, class_id)
    where class_id is not null;

create table public.mission_reward_applications (
    id uuid primary key default gen_random_uuid(),
    completion_id uuid not null
        references public.mission_completions(id) on delete restrict,
    reward_type text not null,
    amount_applied integer not null,
    recipient_student_id uuid
        references public.students(id) on delete restrict,
    recipient_class_id uuid
        references public.classes(id) on delete restrict,
    applied_at timestamptz not null default now(),
    constraint mission_reward_applications_type_check
        check (reward_type in ('BINCOINS', 'XP')),
    constraint mission_reward_applications_amount_check
        check (amount_applied > 0),
    constraint mission_reward_applications_recipient_check
        check (
            (
                reward_type = 'BINCOINS'
                and recipient_student_id is not null
                and recipient_class_id is null
            )
            or
            (
                reward_type = 'XP'
                and recipient_class_id is not null
                and recipient_student_id is null
            )
        )
);

comment on table public.mission_reward_applications is
    'Ledger imutavel por contrato dos efeitos economicos realmente aplicados.';

create unique index mission_reward_applications_completion_student_unique
    on public.mission_reward_applications(
        completion_id,
        reward_type,
        recipient_student_id
    )
    where recipient_student_id is not null;

create unique index mission_reward_applications_completion_class_unique
    on public.mission_reward_applications(
        completion_id,
        reward_type,
        recipient_class_id
    )
    where recipient_class_id is not null;

-- Suporta a soma historica e a determinacao futura de achieved_at para
-- CLASS_XP_EARNED sem duplicar o indice existente de student_id/created_at.
create index idx_deposits_class_created_at_valid
    on public.deposits(class_id, created_at, id)
    include (points_awarded_class)
    where is_valid;

alter table public.mission_definitions enable row level security;
alter table public.mission_cycles enable row level security;
alter table public.mission_completions enable row level security;
alter table public.mission_reward_applications enable row level security;

-- A elegibilidade STUDENT (status ACTIVE, independentemente de is_activated)
-- e o fan-out CLASS para alunos ACTIVE serao regras da futura RPC. Nao sao
-- participacao persistida nem constraints destas tabelas estruturais.
revoke all privileges on table
    public.mission_definitions,
    public.mission_cycles,
    public.mission_completions,
    public.mission_reward_applications
from public, anon, authenticated, service_role;

commit;
