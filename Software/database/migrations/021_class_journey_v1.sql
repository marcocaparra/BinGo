-- BinGo V1
-- Migration: 021_class_journey_v1.sql
--
-- Cria o dominio semestral da Jornada da Turma. Descartes continuam
-- derivados de public.deposits; somente contribuicoes de conclusoes de
-- Missoes sao fotografadas em ledger historico e idempotente.

begin;

create extension if not exists btree_gist with schema extensions;

create table public.journey_campaigns (
    id uuid primary key default gen_random_uuid(),
    school_id uuid not null
        references public.schools(id) on delete restrict,
    starts_at timestamptz not null,
    ends_at timestamptz not null,
    timezone text not null default 'America/Sao_Paulo',
    discard_units integer not null,
    student_mission_units integer not null,
    class_mission_units integer not null,
    created_at timestamptz not null default now(),
    constraint journey_campaigns_period_order_check
        check (starts_at < ends_at),
    constraint journey_campaigns_timezone_check
        check (timezone = 'America/Sao_Paulo'),
    constraint journey_campaigns_weights_check
        check (
            discard_units > 0
            and student_mission_units > 0
            and class_mission_units > 0
        ),
    constraint journey_campaigns_semester_check
        check (
            (starts_at at time zone timezone)
                = date_trunc('day', starts_at at time zone timezone)
            and extract(month from starts_at at time zone timezone) in (1, 7)
            and (ends_at at time zone timezone)
                = (starts_at at time zone timezone) + interval '6 months'
        ),
    constraint journey_campaigns_school_period_unique
        unique (school_id, starts_at, ends_at),
    constraint journey_campaigns_school_period_exclude
        exclude using gist (
            school_id with =,
            tstzrange(starts_at, ends_at, '[)') with &&
        )
);

comment on table public.journey_campaigns is
    'Campanhas semestrais da Jornada com pesos historicos por escola.';

create table public.journey_stages (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null
        references public.journey_campaigns(id) on delete restrict,
    stage_code text not null,
    stage_order integer not null,
    target_units bigint not null,
    created_at timestamptz not null default now(),
    constraint journey_stages_code_check
        check (
            stage_code in (
                'CENTRAL_SQUARE',
                'SPRING_PARK',
                'CREATIVE_SCHOOL'
            )
        ),
    constraint journey_stages_order_check
        check (stage_order > 0),
    constraint journey_stages_target_check
        check (target_units > 0),
    constraint journey_stages_campaign_code_unique
        unique (campaign_id, stage_code),
    constraint journey_stages_campaign_order_unique
        unique (campaign_id, stage_order)
);

comment on table public.journey_stages is
    'Estagios sequenciais e targets historicos de cada campanha.';

create table public.journey_mission_contributions (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null
        references public.journey_campaigns(id) on delete restrict,
    class_id uuid not null
        references public.classes(id) on delete restrict,
    mission_completion_id uuid not null
        references public.mission_completions(id) on delete restrict,
    completion_scope text not null,
    achievement_deposit_id uuid
        references public.deposits(id) on delete restrict,
    units_applied integer not null,
    contributed_at timestamptz not null,
    created_at timestamptz not null default now(),
    constraint journey_mission_contributions_scope_check
        check (completion_scope in ('STUDENT', 'CLASS')),
    constraint journey_mission_contributions_units_check
        check (units_applied > 0),
    constraint journey_mission_contributions_source_check
        check (
            (completion_scope = 'STUDENT' and achievement_deposit_id is not null)
            or
            (completion_scope = 'CLASS' and achievement_deposit_id is null)
        ),
    constraint journey_mission_contributions_completion_unique
        unique (campaign_id, mission_completion_id)
);

comment on table public.journey_mission_contributions is
    'Ledger imutavel das contribuicoes de Missoes para a Jornada; a turma STUDENT vem do deposito que atingiu a meta.';

create index idx_journey_mission_contributions_campaign_class
    on public.journey_mission_contributions(campaign_id, class_id);

alter table public.journey_campaigns enable row level security;
alter table public.journey_stages enable row level security;
alter table public.journey_mission_contributions enable row level security;

revoke all privileges on table
    public.journey_campaigns,
    public.journey_stages,
    public.journey_mission_contributions
from public, anon, authenticated, service_role;

create function public.prevent_journey_contribution_mutation_v1()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    raise exception using
        errcode = '55000',
        message = 'journey_mission_contributions is immutable';
end;
$$;

comment on function public.prevent_journey_contribution_mutation_v1() is
    'Impede UPDATE e DELETE no ledger historico da Jornada.';

revoke all on function public.prevent_journey_contribution_mutation_v1()
from public, anon, authenticated, service_role;

create trigger journey_mission_contributions_immutable_v1
before update or delete on public.journey_mission_contributions
for each row
execute function public.prevent_journey_contribution_mutation_v1();

create function public.resolve_journey_student_achievement_v1(
    p_completion_id uuid
)
returns table (
    deposit_id uuid,
    event_id uuid,
    class_id uuid,
    created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_completion public.mission_completions%rowtype;
    v_cycle public.mission_cycles%rowtype;
begin
    select completion.*
    into strict v_completion
    from public.mission_completions as completion
    where completion.id = p_completion_id;

    select cycle.*
    into strict v_cycle
    from public.mission_cycles as cycle
    where cycle.id = v_completion.cycle_id;

    if v_completion.participant_scope <> 'STUDENT'
       or v_completion.student_id is null
       or v_cycle.scope <> 'STUDENT'
       or v_cycle.metric <> 'VALID_DEPOSIT_COUNT' then
        raise exception using
            errcode = '23514',
            message = 'Journey STUDENT completion is not VALID_DEPOSIT_COUNT';
    end if;

    return query
    with ranked_deposits as (
        select
            deposit.id,
            deposit.event_id,
            deposit.class_id,
            deposit.school_id,
            deposit.created_at,
            row_number() over (
                order by deposit.created_at, deposit.id
            ) as position
        from public.deposits as deposit
        where deposit.student_id = v_completion.student_id
          and deposit.is_valid = true
          and deposit.created_at >= v_cycle.starts_at
          and deposit.created_at < v_cycle.ends_at
    ),
    resolved as (
        select ranked.*
        from ranked_deposits as ranked
        where ranked.position = v_cycle.target
    )
    select
        resolved.id,
        resolved.event_id,
        resolved.class_id,
        resolved.created_at
    from resolved
    join public.classes as class_row
      on class_row.id = resolved.class_id
     and class_row.school_id = v_cycle.school_id
    where resolved.school_id = v_cycle.school_id
      and resolved.created_at = v_completion.achieved_at;

    if not found then
        raise exception using
            errcode = '23514',
            message = format(
                'Could not deterministically resolve Journey achievement deposit for completion %s',
                p_completion_id
            );
    end if;
end;
$$;

comment on function public.resolve_journey_student_achievement_v1(uuid) is
    'Resolve internamente o deposito STUDENT na posicao target e exige igualdade com achieved_at.';

revoke all on function public.resolve_journey_student_achievement_v1(uuid)
from public, anon, authenticated, service_role;

create function public.record_journey_mission_contribution_v1(
    p_completion_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_completion public.mission_completions%rowtype;
    v_cycle public.mission_cycles%rowtype;
    v_campaign public.journey_campaigns%rowtype;
    v_achievement record;
    v_class_id uuid;
    v_deposit_id uuid;
    v_units integer;
begin
    select completion.*
    into strict v_completion
    from public.mission_completions as completion
    where completion.id = p_completion_id;

    select cycle.*
    into strict v_cycle
    from public.mission_cycles as cycle
    where cycle.id = v_completion.cycle_id;

    select campaign.*
    into v_campaign
    from public.journey_campaigns as campaign
    where campaign.school_id = v_cycle.school_id
      and v_completion.achieved_at >= campaign.starts_at
      and v_completion.achieved_at < campaign.ends_at;

    if not found then
        return false;
    end if;

    if v_completion.participant_scope = 'STUDENT' then
        select resolved.*
        into strict v_achievement
        from public.resolve_journey_student_achievement_v1(
            v_completion.id
        ) as resolved;

        v_class_id := v_achievement.class_id;
        v_deposit_id := v_achievement.deposit_id;
        v_units := v_campaign.student_mission_units;
    elsif v_completion.participant_scope = 'CLASS' then
        if not exists (
            select 1
            from public.classes as class_row
            where class_row.id = v_completion.class_id
              and class_row.school_id = v_cycle.school_id
        ) then
            raise exception using
                errcode = '23514',
                message = format(
                    'Journey CLASS completion %s has an inconsistent class',
                    v_completion.id
                );
        end if;

        v_class_id := v_completion.class_id;
        v_deposit_id := null;
        v_units := v_campaign.class_mission_units;
    else
        raise exception using
            errcode = '23514',
            message = 'Unsupported Journey mission completion scope';
    end if;

    insert into public.journey_mission_contributions (
        campaign_id,
        class_id,
        mission_completion_id,
        completion_scope,
        achievement_deposit_id,
        units_applied,
        contributed_at
    ) values (
        v_campaign.id,
        v_class_id,
        v_completion.id,
        v_completion.participant_scope,
        v_deposit_id,
        v_units,
        v_completion.achieved_at
    )
    on conflict (campaign_id, mission_completion_id) do nothing;

    return found;
end;
$$;

comment on function public.record_journey_mission_contribution_v1(uuid) is
    'Registra idempotentemente a contribuicao da Jornada sem alterar recompensas de Missoes.';

revoke all on function public.record_journey_mission_contribution_v1(uuid)
from public, anon, authenticated, service_role;

create function public.capture_journey_mission_completion_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.record_journey_mission_contribution_v1(new.id);
    return new;
end;
$$;

comment on function public.capture_journey_mission_completion_v1() is
    'Trigger interno que captura novas mission_completions para a Jornada.';

revoke all on function public.capture_journey_mission_completion_v1()
from public, anon, authenticated, service_role;

create trigger mission_completions_capture_journey_v1
after insert on public.mission_completions
for each row
execute function public.capture_journey_mission_completion_v1();

create function public.backfill_journey_campaign_v1(p_campaign_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_campaign public.journey_campaigns%rowtype;
    v_completion record;
    v_inserted integer := 0;
begin
    select campaign.*
    into strict v_campaign
    from public.journey_campaigns as campaign
    where campaign.id = p_campaign_id;

    for v_completion in
        select completion.id
        from public.mission_completions as completion
        join public.mission_cycles as cycle
          on cycle.id = completion.cycle_id
        where cycle.school_id = v_campaign.school_id
          and completion.achieved_at >= v_campaign.starts_at
          and completion.achieved_at < v_campaign.ends_at
        order by completion.achieved_at, completion.id
    loop
        if public.record_journey_mission_contribution_v1(
            v_completion.id
        ) then
            v_inserted := v_inserted + 1;
        end if;
    end loop;

    return v_inserted;
end;
$$;

comment on function public.backfill_journey_campaign_v1(uuid) is
    'Backfill interno, validado e idempotente das completions de uma campanha provisionada.';

revoke all on function public.backfill_journey_campaign_v1(uuid)
from public, anon, authenticated, service_role;

create function public.get_class_journey_v1()
returns table (
    campaign_id uuid,
    starts_at timestamptz,
    ends_at timestamptz,
    stage_code text,
    stage_order integer,
    target_units bigint,
    progress_units bigint,
    progress_ratio numeric,
    state text,
    total_units bigint,
    valid_deposit_count bigint,
    student_mission_completion_count bigint,
    class_mission_completion_count bigint,
    remaining_units bigint
)
language sql
stable
security definer
set search_path = ''
as $$
    with current_student as materialized (
        select
            student.school_id,
            student.class_id
        from public.students as student
        join public.classes as class_row
          on class_row.id = student.class_id
         and class_row.school_id = student.school_id
        where student.auth_user_id = auth.uid()
    ),
    current_campaign as materialized (
        select
            campaign.*,
            current_student.class_id
        from current_student
        join public.journey_campaigns as campaign
          on campaign.school_id = current_student.school_id
         and pg_catalog.now() >= campaign.starts_at
         and pg_catalog.now() < campaign.ends_at
    ),
    deposit_totals as materialized (
        select
            campaign.id as campaign_id,
            count(deposit.id)::bigint as valid_deposit_count
        from current_campaign as campaign
        left join public.deposits as deposit
          on deposit.class_id = campaign.class_id
         and deposit.is_valid = true
         and deposit.created_at >= campaign.starts_at
         and deposit.created_at < campaign.ends_at
        group by campaign.id
    ),
    mission_totals as materialized (
        select
            campaign.id as campaign_id,
            coalesce(sum(contribution.units_applied), 0)::bigint
                as mission_units,
            count(contribution.id) filter (
                where contribution.completion_scope = 'STUDENT'
            )::bigint as student_count,
            count(contribution.id) filter (
                where contribution.completion_scope = 'CLASS'
            )::bigint as class_count
        from current_campaign as campaign
        left join public.journey_mission_contributions as contribution
          on contribution.campaign_id = campaign.id
         and contribution.class_id = campaign.class_id
        group by campaign.id
    ),
    totals as materialized (
        select
            campaign.*,
            deposit_totals.valid_deposit_count,
            mission_totals.student_count,
            mission_totals.class_count,
            (
                deposit_totals.valid_deposit_count
                * campaign.discard_units::bigint
                + mission_totals.mission_units
            )::bigint as total_units
        from current_campaign as campaign
        join deposit_totals on deposit_totals.campaign_id = campaign.id
        join mission_totals on mission_totals.campaign_id = campaign.id
    ),
    staged as (
        select
            stage.*,
            totals.starts_at,
            totals.ends_at,
            totals.total_units,
            totals.valid_deposit_count,
            totals.student_count,
            totals.class_count,
            coalesce(
                sum(stage.target_units) over (
                    partition by stage.campaign_id
                    order by stage.stage_order
                    rows between unbounded preceding and 1 preceding
                ),
                0
            )::bigint as prior_target_units
        from totals
        join public.journey_stages as stage
          on stage.campaign_id = totals.id
    ),
    progress as (
        select
            staged.*,
            least(
                staged.target_units,
                greatest(
                    staged.total_units - staged.prior_target_units,
                    0::bigint
                )
            )::bigint as stage_progress_units
        from staged
    )
    select
        progress.campaign_id,
        progress.starts_at,
        progress.ends_at,
        progress.stage_code,
        progress.stage_order,
        progress.target_units,
        progress.stage_progress_units as progress_units,
        least(
            1::numeric,
            greatest(
                0::numeric,
                progress.stage_progress_units::numeric
                    / progress.target_units::numeric
            )
        ) as progress_ratio,
        case
            when progress.stage_progress_units >= progress.target_units
                then 'COMPLETED'
            when progress.total_units >= progress.prior_target_units
                then 'ACTIVE'
            else 'LOCKED'
        end as state,
        progress.total_units,
        progress.valid_deposit_count,
        progress.student_count as student_mission_completion_count,
        progress.class_count as class_mission_completion_count,
        greatest(
            progress.target_units - progress.stage_progress_units,
            0::bigint
        )::bigint as remaining_units
    from progress
    order by progress.stage_order;
$$;

comment on function public.get_class_journey_v1() is
    'Retorna a Jornada vigente da turma autenticada, derivando descartes e ledger de Missoes.';

revoke all on function public.get_class_journey_v1()
from public, anon, authenticated, service_role;

grant execute on function public.get_class_journey_v1()
to authenticated;

commit;
