-- BinGo V1
-- Seed DEV: campanha da Jornada H2/2026
--
-- Provisionamento idempotente e controlado para a escola demo do bingo-dev.
-- Nao faz parte da migration estrutural e nao deve ser aplicado em producao
-- sem uma decisao explicita de provisionamento.

begin;

insert into public.journey_campaigns (
    id,
    school_id,
    starts_at,
    ends_at,
    timezone,
    discard_units,
    student_mission_units,
    class_mission_units
)
values (
    '61000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '2026-07-01 00:00:00 America/Sao_Paulo',
    '2027-01-01 00:00:00 America/Sao_Paulo',
    'America/Sao_Paulo',
    1,
    3,
    5
)
on conflict (school_id, starts_at, ends_at) do nothing;

do $$
begin
    if not exists (
        select 1
        from public.journey_campaigns as campaign
        where campaign.id = '61000000-0000-4000-8000-000000000001'
          and campaign.school_id = '10000000-0000-4000-8000-000000000001'
          and campaign.starts_at = '2026-07-01 00:00:00 America/Sao_Paulo'
          and campaign.ends_at = '2027-01-01 00:00:00 America/Sao_Paulo'
          and campaign.timezone = 'America/Sao_Paulo'
          and campaign.discard_units = 1
          and campaign.student_mission_units = 3
          and campaign.class_mission_units = 5
    ) then
        raise exception
            'Campanha DEV H2/2026 conflita com o snapshot esperado.';
    end if;
end;
$$;

insert into public.journey_stages (
    id,
    campaign_id,
    stage_code,
    stage_order,
    target_units
)
values
    (
        '62000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        'CENTRAL_SQUARE',
        1,
        20
    ),
    (
        '62000000-0000-4000-8000-000000000002',
        '61000000-0000-4000-8000-000000000001',
        'SPRING_PARK',
        2,
        25
    ),
    (
        '62000000-0000-4000-8000-000000000003',
        '61000000-0000-4000-8000-000000000001',
        'CREATIVE_SCHOOL',
        3,
        30
    )
on conflict (campaign_id, stage_code) do nothing;

do $$
begin
    if (
        select count(*)
        from public.journey_stages as stage
        where stage.campaign_id = '61000000-0000-4000-8000-000000000001'
          and (stage.stage_code, stage.stage_order, stage.target_units) in (
              ('CENTRAL_SQUARE', 1, 20),
              ('SPRING_PARK', 2, 25),
              ('CREATIVE_SCHOOL', 3, 30)
          )
    ) <> 3 then
        raise exception
            'Estagios DEV H2/2026 conflitam com o snapshot esperado.';
    end if;
end;
$$;

select public.backfill_journey_campaign_v1(
    '61000000-0000-4000-8000-000000000001'
);

commit;
