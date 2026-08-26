-- BinGo V1
-- Migration: 005_deposit_v1_scoring.sql
--
-- Este arquivo deve permanecer funcionalmente equivalente a
-- database/migrations/005_deposit_v1_scoring.sql.

create table public.waste_categories (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    display_name text not null,
    bonus_rate numeric(8, 4) not null default 0 check (bonus_rate >= 0),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint waste_categories_code_format_check
        check (code ~ '^[A-Z][A-Z0-9_]*$')
);

comment on table public.waste_categories is
    'Catalogo global e canonico de categorias de lixo eletronico. Registros sao desativados, nao excluidos.';
comment on column public.waste_categories.bonus_rate is
    'Percentual adicional de BinCoins: 1.0000 = bonus de 100%. Em producao nasce zerado ate aprovacao formal.';

insert into public.waste_categories (code, display_name, bonus_rate)
values
    ('BATTERY', 'Pilha ou bateria', 0),
    ('MOBILE_DEVICE', 'Celular ou tablet', 0),
    ('CABLE_WIRE', 'Cabo ou fio', 0),
    ('PERIPHERAL', 'Periferico', 0),
    ('OTHER_EWASTE', 'Outro lixo eletronico', 0),
    ('UNKNOWN', 'Lixo eletronico nao identificado', 0);

alter table public.school_settings
    add column deposit_bincoins_base integer not null default 8
        check (deposit_bincoins_base >= 0),
    add column deposit_class_xp_base integer not null default 19
        check (deposit_class_xp_base >= 0),
    add column class_weekly_xp_goal integer not null default 100
        check (class_weekly_xp_goal >= 0);

alter table public.deposits
    add column waste_category_id uuid references public.waste_categories(id) on delete restrict,
    add column category_source text,
    add column bonus_rate_applied numeric(8, 4) not null default 0,
    add column bonus_bincoins_awarded integer not null default 0;

update public.deposits
set
    waste_category_id = (
        select wc.id
        from public.waste_categories as wc
        where wc.code = 'UNKNOWN'
    ),
    category_source = 'UNIDENTIFIED'
where is_valid;

alter table public.deposits
    add constraint deposits_category_source_check
        check (category_source in ('AI_CONFIRMED', 'USER_CORRECTED', 'UNIDENTIFIED')),
    add constraint deposits_bonus_rate_applied_check
        check (bonus_rate_applied >= 0),
    add constraint deposits_bonus_bincoins_awarded_check
        check (bonus_bincoins_awarded >= 0),
    add constraint deposits_bonus_not_greater_than_total_check
        check (bonus_bincoins_awarded <= points_awarded_student),
    add constraint deposits_valid_category_check
        check (
            (is_valid and waste_category_id is not null and category_source is not null)
            or
            (not is_valid and waste_category_id is null and category_source is null)
        );

create index idx_deposits_waste_category_created_at
    on public.deposits(waste_category_id, created_at);

alter table public.deposits
    drop column size;

alter table public.school_settings
    drop column small_item_daily_limit,
    drop column points_small_student,
    drop column points_small_class,
    drop column points_medium_student,
    drop column points_medium_class,
    drop column points_large_student,
    drop column points_large_class;

create or replace function public.register_deposit_v1(
    p_event_id uuid,
    p_machine_id uuid,
    p_class_id uuid,
    p_is_valid boolean,
    p_student_id uuid default null,
    p_detected_type text default null,
    p_waste_category_code text default null,
    p_category_source text default null
)
returns table (
    deposit_id uuid,
    event_id uuid,
    waste_category_code text,
    bonus_rate_applied numeric,
    bonus_bincoins_awarded integer,
    points_awarded_student integer,
    points_awarded_class integer,
    created_at timestamptz,
    was_replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_school_id uuid;
    v_category_id uuid;
    v_category_code text;
    v_bonus_rate numeric(8, 4) := 0;
    v_bincoins_base integer;
    v_class_xp_base integer;
    v_bonus_bincoins integer := 0;
    v_student_points integer := 0;
    v_class_points integer := 0;
    v_inserted_id uuid;
    v_existing public.deposits%rowtype;
begin
    select m.school_id into v_school_id
    from public.machines as m
    where m.id = p_machine_id;

    if v_school_id is null then
        raise exception using errcode = 'P0002', message = 'Maquina nao encontrada.';
    end if;

    select d.* into v_existing
    from public.deposits as d
    where d.event_id = p_event_id;

    if found then
        if v_existing.school_id <> v_school_id
            or v_existing.machine_id <> p_machine_id
            or v_existing.class_id <> p_class_id
            or v_existing.student_id is distinct from p_student_id
            or v_existing.is_valid <> p_is_valid
            or v_existing.detected_type is distinct from p_detected_type
            or (select wc.code from public.waste_categories as wc where wc.id = v_existing.waste_category_id)
                is distinct from p_waste_category_code
            or v_existing.category_source is distinct from p_category_source
        then
            raise exception using errcode = '23505', message = 'event_id reutilizado com dados diferentes.';
        end if;

        return query
        select d.id, d.event_id, wc.code, d.bonus_rate_applied,
               d.bonus_bincoins_awarded, d.points_awarded_student,
               d.points_awarded_class, d.created_at, true
        from public.deposits as d
        left join public.waste_categories as wc on wc.id = d.waste_category_id
        where d.id = v_existing.id;
        return;
    end if;

    if not exists (
        select 1 from public.classes as c
        where c.id = p_class_id and c.school_id = v_school_id
    ) then
        raise exception using errcode = '23503', message = 'Turma invalida para a escola da maquina.';
    end if;

    if p_student_id is not null and not exists (
        select 1 from public.students as s
        where s.id = p_student_id
          and s.school_id = v_school_id
          and s.class_id = p_class_id
          and s.status = 'ACTIVE'
    ) then
        raise exception using errcode = '23503', message = 'Aluno invalido para a escola e turma informadas.';
    end if;

    select ss.deposit_bincoins_base, ss.deposit_class_xp_base
    into v_bincoins_base, v_class_xp_base
    from public.school_settings as ss
    where ss.school_id = v_school_id;

    if not found then
        raise exception using errcode = 'P0002', message = 'A escola nao possui configuracoes operacionais.';
    end if;

    if p_is_valid then
        if p_waste_category_code is null or p_category_source is null then
            raise exception using errcode = '23514', message = 'Categoria canonica e origem sao obrigatorias para descarte valido.';
        end if;

        if p_category_source not in ('AI_CONFIRMED', 'USER_CORRECTED', 'UNIDENTIFIED') then
            raise exception using errcode = '23514', message = 'Origem da categoria invalida.';
        end if;

        if p_waste_category_code = 'UNKNOWN' and p_category_source <> 'UNIDENTIFIED' then
            raise exception using errcode = '23514', message = 'A categoria UNKNOWN exige origem UNIDENTIFIED.';
        end if;

        if p_waste_category_code <> 'UNKNOWN' and p_category_source = 'UNIDENTIFIED' then
            raise exception using errcode = '23514', message = 'A origem UNIDENTIFIED exige categoria UNKNOWN.';
        end if;

        select wc.id, wc.code, wc.bonus_rate
        into v_category_id, v_category_code, v_bonus_rate
        from public.waste_categories as wc
        where wc.code = p_waste_category_code and wc.is_active;

        if not found then
            raise exception using errcode = 'P0002', message = 'Categoria de lixo eletronico inexistente ou inativa.';
        end if;

        v_class_points := v_class_xp_base;
        if p_student_id is not null then
            v_bonus_bincoins := round(v_bincoins_base * v_bonus_rate)::integer;
            v_student_points := v_bincoins_base + v_bonus_bincoins;
        end if;
    else
        if p_waste_category_code is not null or p_category_source is not null then
            raise exception using errcode = '23514', message = 'Descarte invalido nao aceita categoria canonica ou origem.';
        end if;
    end if;

    insert into public.deposits (
        event_id, school_id, machine_id, class_id, student_id, is_valid,
        detected_type, waste_category_id, category_source, bonus_rate_applied,
        bonus_bincoins_awarded, points_awarded_student, points_awarded_class
    )
    values (
        p_event_id, v_school_id, p_machine_id, p_class_id, p_student_id,
        p_is_valid, p_detected_type, v_category_id, p_category_source,
        v_bonus_rate, v_bonus_bincoins, v_student_points, v_class_points
    )
    on conflict on constraint deposits_event_id_key do nothing
    returning id into v_inserted_id;

    if v_inserted_id is null then
        select d.* into strict v_existing
        from public.deposits as d
        where d.event_id = p_event_id;

        if v_existing.school_id <> v_school_id
            or v_existing.machine_id <> p_machine_id
            or v_existing.class_id <> p_class_id
            or v_existing.student_id is distinct from p_student_id
            or v_existing.is_valid <> p_is_valid
            or v_existing.detected_type is distinct from p_detected_type
            or v_existing.waste_category_id is distinct from v_category_id
            or v_existing.category_source is distinct from p_category_source
        then
            raise exception using errcode = '23505', message = 'event_id reutilizado com dados diferentes.';
        end if;

        return query
        select d.id, d.event_id, wc.code, d.bonus_rate_applied,
               d.bonus_bincoins_awarded, d.points_awarded_student,
               d.points_awarded_class, d.created_at, true
        from public.deposits as d
        left join public.waste_categories as wc on wc.id = d.waste_category_id
        where d.id = v_existing.id;
        return;
    end if;

    update public.classes
    set points_class_balance = points_class_balance + v_class_points,
        updated_at = now()
    where id = p_class_id;

    if p_student_id is not null then
        update public.students
        set points_student_balance = points_student_balance + v_student_points,
            updated_at = now()
        where id = p_student_id;
    end if;

    insert into public.audit_logs (school_id, actor_type, actor_id, action, metadata)
    values (
        v_school_id, 'MACHINE', p_machine_id, 'DEPOSIT_REGISTERED',
        jsonb_build_object(
            'event_id', p_event_id,
            'detected_type', p_detected_type,
            'waste_category_code', v_category_code,
            'category_source', p_category_source,
            'bonus_rate_applied', v_bonus_rate,
            'bonus_bincoins_awarded', v_bonus_bincoins,
            'points_awarded_student', v_student_points,
            'points_awarded_class', v_class_points
        )
    );

    return query
    select d.id, d.event_id, wc.code, d.bonus_rate_applied,
           d.bonus_bincoins_awarded, d.points_awarded_student,
           d.points_awarded_class, d.created_at, false
    from public.deposits as d
    left join public.waste_categories as wc on wc.id = d.waste_category_id
    where d.id = v_inserted_id;
end;
$$;

comment on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text) is
    'Registra descarte, recompensa, saldos e auditoria atomicamente. Uso exclusivo da Edge Function.';

revoke all on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text) from public;
revoke all on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text) from anon, authenticated;
grant execute on function public.register_deposit_v1(uuid, uuid, uuid, boolean, uuid, text, text, text) to service_role;

revoke insert, update, delete on table public.deposits from anon, authenticated;
revoke insert, update, delete on table public.students from anon, authenticated;
revoke insert, update, delete on table public.classes from anon, authenticated;
revoke insert, update, delete on table public.audit_logs from anon, authenticated;
revoke insert, update, delete on table public.school_settings from anon, authenticated;
revoke insert, update, delete on table public.waste_categories from anon, authenticated;

grant select on table public.waste_categories to anon, authenticated;
