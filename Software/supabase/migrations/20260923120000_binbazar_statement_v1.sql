-- BinGo V1
-- Migration: 20260923120000_binbazar_statement_v1.sql
--
-- BinBazar/Extrato autenticados. O saldo materializado continua em
-- students.points_student_balance; audit_logs nao e usado como ledger.

begin;

alter table public.redemptions
    add column client_request_id uuid,
    add column reward_name_snapshot text,
    add column cost_points_snapshot integer,
    add column stock_was_finite boolean,
    add column canceled_at timestamptz;

alter table public.redemptions
    drop constraint redemptions_request_channel_check,
    add constraint redemptions_request_channel_check
        check (request_channel in ('TOTEM', 'MOBILE')),
    add constraint redemptions_snapshot_pair_check
        check (
            (reward_name_snapshot is null and cost_points_snapshot is null)
            or
            (
                reward_name_snapshot is not null
                and btrim(reward_name_snapshot) <> ''
                and cost_points_snapshot > 0
            )
        );

comment on column public.redemptions.client_request_id is
    'Idempotency key supplied once per Mobile redemption intent; nullable only for legacy rows.';
comment on column public.redemptions.reward_name_snapshot is
    'Immutable reward name captured when the redemption is created; nullable only for legacy rows.';
comment on column public.redemptions.cost_points_snapshot is
    'Immutable amount charged when the redemption is created; nullable only for legacy rows.';
comment on column public.redemptions.stock_was_finite is
    'Whether this order reserved finite stock at creation; nullable only for legacy rows.';
comment on column public.redemptions.canceled_at is
    'Timestamp of the first transition to CANCELED.';

create unique index redemptions_client_request_id_unique
    on public.redemptions(client_request_id)
    where client_request_id is not null;

create index idx_redemptions_student_created_at_v1
    on public.redemptions(student_id, created_at desc, id desc);

create function public.get_my_binbazar_catalog_v1()
returns table (
    reward_id uuid,
    name text,
    description text,
    cost_points integer,
    is_active boolean,
    stock_qty integer
)
language sql
stable
security definer
set search_path = ''
as $$
    with current_student as materialized (
        select student.school_id
        from public.students as student
        where student.auth_user_id = auth.uid()
          and student.status = 'ACTIVE'
    )
    select
        reward.id,
        reward.name,
        reward.description,
        reward.cost_points,
        reward.is_active,
        reward.stock_qty
    from current_student as student
    join public.rewards as reward
      on reward.school_id = student.school_id
    where reward.is_active
    order by reward.name asc, reward.id asc;
$$;

comment on function public.get_my_binbazar_catalog_v1() is
    'Lists active rewards from the authenticated active student school; availability is based on is_active and stock_qty, never rewards.status.';

create function public.get_my_redemptions_v1()
returns table (
    redemption_id uuid,
    reward_id uuid,
    reward_name text,
    cost_points integer,
    code text,
    status text,
    request_channel text,
    created_at timestamptz,
    delivered_at timestamptz,
    canceled_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    with current_student as materialized (
        select student.id
        from public.students as student
        where student.auth_user_id = auth.uid()
    )
    select
        redemption.id,
        redemption.reward_id,
        redemption.reward_name_snapshot,
        redemption.cost_points_snapshot,
        redemption.code,
        redemption.status,
        redemption.request_channel,
        redemption.created_at,
        redemption.delivered_at,
        redemption.canceled_at
    from current_student as student
    join public.redemptions as redemption
      on redemption.student_id = student.id
    order by redemption.created_at desc, redemption.id desc;
$$;

comment on function public.get_my_redemptions_v1() is
    'Lists only the authenticated student redemptions using immutable product snapshots.';

create function public.request_redemption_v1(
    p_request_id uuid,
    p_reward_id uuid
)
returns table (
    redemption_id uuid,
    reward_id uuid,
    reward_name text,
    cost_points integer,
    code text,
    status text,
    request_channel text,
    created_at timestamptz,
    canceled_at timestamptz,
    points_student_balance integer,
    replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_student_id uuid;
    v_school_id uuid;
    v_student_status text;
    v_balance integer;
    v_reward_school_id uuid;
    v_reward_name text;
    v_cost_points integer;
    v_is_active boolean;
    v_stock_qty integer;
    v_redemption public.redemptions%rowtype;
    v_redemption_id uuid;
    v_code text;
begin
    if p_request_id is null or p_reward_id is null then
        raise exception using
            errcode = '23502',
            message = 'request_id e reward_id sao obrigatorios.';
    end if;

    -- Serializa a mesma chave globalmente, inclusive quando duas identidades
    -- tentam reutiliza-la ao mesmo tempo.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(p_request_id::text, 0)
    );

    -- Ordem autoritativa para criacao: aluno, depois reward.
    select
        student.id,
        student.school_id,
        student.status,
        student.points_student_balance
    into
        v_student_id,
        v_school_id,
        v_student_status,
        v_balance
    from public.students as student
    where student.auth_user_id = auth.uid()
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Conta autenticada sem aluno vinculado.';
    end if;

    select
        reward.school_id,
        reward.name,
        reward.cost_points,
        reward.is_active,
        reward.stock_qty
    into
        v_reward_school_id,
        v_reward_name,
        v_cost_points,
        v_is_active,
        v_stock_qty
    from public.rewards as reward
    where reward.id = p_reward_id
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Produto nao encontrado.';
    end if;

    select redemption.*
    into v_redemption
    from public.redemptions as redemption
    where redemption.client_request_id = p_request_id;

    if found then
        if v_redemption.student_id <> v_student_id
           or v_redemption.reward_id <> p_reward_id
        then
            raise exception using
                errcode = '23505',
                message = 'request_id reutilizado com semantica diferente.';
        end if;

        return query
        select
            v_redemption.id,
            v_redemption.reward_id,
            v_redemption.reward_name_snapshot,
            v_redemption.cost_points_snapshot,
            v_redemption.code,
            v_redemption.status,
            v_redemption.request_channel,
            v_redemption.created_at,
            v_redemption.canceled_at,
            v_balance,
            true;
        return;
    end if;

    if v_student_status <> 'ACTIVE' then
        raise exception using
            errcode = '23514',
            message = 'Aluno inativo nao pode solicitar resgate.';
    end if;

    if v_reward_school_id <> v_school_id then
        raise exception using
            errcode = '23503',
            message = 'Produto nao pertence a escola do aluno.';
    end if;

    if not v_is_active then
        raise exception using
            errcode = '23514',
            message = 'Produto indisponivel.';
    end if;

    if v_stock_qty is not null and v_stock_qty = 0 then
        raise exception using
            errcode = '23514',
            message = 'Produto esgotado.';
    end if;

    if v_balance < v_cost_points then
        raise exception using
            errcode = '23514',
            message = 'Saldo insuficiente.';
    end if;

    v_redemption_id := gen_random_uuid();
    v_code := 'BGO-' || upper(substr(replace(v_redemption_id::text, '-', ''), 1, 12));

    update public.students as charged_student
    set points_student_balance = charged_student.points_student_balance - v_cost_points,
        updated_at = now()
    where id = v_student_id;

    if v_stock_qty is not null then
        update public.rewards
        set stock_qty = stock_qty - 1,
            updated_at = now()
        where id = p_reward_id;
    end if;

    insert into public.redemptions (
        id,
        school_id,
        student_id,
        reward_id,
        code,
        status,
        request_channel,
        client_request_id,
        reward_name_snapshot,
        cost_points_snapshot,
        stock_was_finite,
        expires_at
    )
    values (
        v_redemption_id,
        v_school_id,
        v_student_id,
        p_reward_id,
        v_code,
        'PENDING',
        'MOBILE',
        p_request_id,
        v_reward_name,
        v_cost_points,
        v_stock_qty is not null,
        null
    )
    returning * into v_redemption;

    insert into public.audit_logs (
        school_id, actor_type, actor_id, action, metadata
    )
    values (
        v_school_id,
        'STUDENT',
        v_student_id,
        'REDEMPTION_REQUESTED_V1',
        pg_catalog.jsonb_build_object(
            'redemption_id', v_redemption_id,
            'client_request_id', p_request_id,
            'reward_id', p_reward_id,
            'reward_name_snapshot', v_reward_name,
            'cost_points_snapshot', v_cost_points,
            'request_channel', 'MOBILE'
        )
    );

    return query
    select
        v_redemption.id,
        v_redemption.reward_id,
        v_redemption.reward_name_snapshot,
        v_redemption.cost_points_snapshot,
        v_redemption.code,
        v_redemption.status,
        v_redemption.request_channel,
        v_redemption.created_at,
        v_redemption.canceled_at,
        v_balance - v_cost_points,
        false;
end;
$$;

comment on function public.request_redemption_v1(uuid, uuid) is
    'Atomically requests a Mobile redemption for auth.uid(), charging the immutable snapshot and reserving finite stock.';

create function public.cancel_my_redemption_v1(p_redemption_id uuid)
returns table (
    redemption_id uuid,
    reward_id uuid,
    reward_name text,
    cost_points integer,
    code text,
    status text,
    created_at timestamptz,
    canceled_at timestamptz,
    points_student_balance integer,
    replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_redemption public.redemptions%rowtype;
    v_student_id uuid;
    v_school_id uuid;
    v_balance integer;
    v_restored_stock_rows integer := 0;
begin
    if p_redemption_id is null then
        raise exception using
            errcode = '23502',
            message = 'redemption_id e obrigatorio.';
    end if;

    -- A redemption e sempre a primeira linha bloqueada: isso serializa a
    -- futura corrida entre cancelamento Mobile e entrega Admin.
    select redemption.*
    into v_redemption
    from public.redemptions as redemption
    where redemption.id = p_redemption_id
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Resgate nao encontrado.';
    end if;

    select
        student.id,
        student.school_id,
        student.points_student_balance
    into
        v_student_id,
        v_school_id,
        v_balance
    from public.students as student
    where student.auth_user_id = auth.uid()
    for update;

    if not found or v_student_id <> v_redemption.student_id then
        raise exception using
            errcode = 'P0002',
            message = 'Resgate nao encontrado.';
    end if;

    if v_redemption.status = 'CANCELED' then
        return query
        select
            v_redemption.id,
            v_redemption.reward_id,
            v_redemption.reward_name_snapshot,
            v_redemption.cost_points_snapshot,
            v_redemption.code,
            v_redemption.status,
            v_redemption.created_at,
            v_redemption.canceled_at,
            v_balance,
            true;
        return;
    end if;

    if v_redemption.status = 'DELIVERED' then
        raise exception using
            errcode = '55000',
            message = 'Resgate entregue nao pode ser cancelado.';
    end if;

    if v_redemption.status <> 'PENDING' then
        raise exception using
            errcode = '55000',
            message = 'Somente resgate pendente pode ser cancelado.';
    end if;

    if v_redemption.request_channel <> 'MOBILE'
       or v_redemption.cost_points_snapshot is null
       or v_redemption.reward_name_snapshot is null
       or v_redemption.stock_was_finite is null
    then
        raise exception using
            errcode = 'P0001',
            message = 'Resgate legado sem snapshot nao pode ser cancelado por este caminho.';
    end if;

    update public.students as refunded_student
    set points_student_balance = refunded_student.points_student_balance + v_redemption.cost_points_snapshot,
        updated_at = now()
    where id = v_student_id;

    if v_redemption.stock_was_finite then
        update public.rewards as restored_reward
        set stock_qty = restored_reward.stock_qty + 1,
            updated_at = now()
        where id = v_redemption.reward_id
          and stock_qty is not null;
        get diagnostics v_restored_stock_rows = row_count;
    end if;

    update public.redemptions
    set status = 'CANCELED',
        canceled_at = now()
    where id = v_redemption.id
    returning * into v_redemption;

    insert into public.audit_logs (
        school_id, actor_type, actor_id, action, metadata
    )
    values (
        v_school_id,
        'STUDENT',
        v_student_id,
        'REDEMPTION_CANCELED_V1',
        pg_catalog.jsonb_build_object(
            'redemption_id', v_redemption.id,
            'reward_id', v_redemption.reward_id,
            'reward_name_snapshot', v_redemption.reward_name_snapshot,
            'cost_points_refunded', v_redemption.cost_points_snapshot,
            'finite_stock_reserved', v_redemption.stock_was_finite,
            'finite_stock_restored', v_restored_stock_rows = 1
        )
    );

    return query
    select
        v_redemption.id,
        v_redemption.reward_id,
        v_redemption.reward_name_snapshot,
        v_redemption.cost_points_snapshot,
        v_redemption.code,
        v_redemption.status,
        v_redemption.created_at,
        v_redemption.canceled_at,
        v_balance + v_redemption.cost_points_snapshot,
        false;
end;
$$;

comment on function public.cancel_my_redemption_v1(uuid) is
    'Cancels only the authenticated student own PENDING Mobile redemption, refunding and restoring finite stock exactly once.';

create function public.get_my_bincoin_statement_v1()
returns table (
    movement_id text,
    occurred_at timestamptz,
    movement_type text,
    amount integer,
    title text,
    redemption_id uuid,
    source_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_student_id uuid;
begin
    select student.id
    into v_student_id
    from public.students as student
    where student.auth_user_id = auth.uid();

    if not found then
        return;
    end if;

    if exists (
        select 1
        from public.redemptions as redemption
        where redemption.student_id = v_student_id
          and (
              redemption.reward_name_snapshot is null
              or redemption.cost_points_snapshot is null
          )
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Extrato indisponivel: resgate historico sem snapshot.';
    end if;

    return query
    with movements as (
        select
            'DEPOSIT:' || deposit.id::text as movement_id,
            deposit.created_at as occurred_at,
            'DEPOSIT'::text as movement_type,
            deposit.points_awarded_student as amount,
            'Descarte validado'::text as title,
            null::uuid as redemption_id,
            deposit.id as source_id,
            1 as source_order
        from public.deposits as deposit
        where deposit.student_id = v_student_id
          and deposit.points_awarded_student > 0

        union all

        select
            'MISSION_REWARD:' || application.id::text,
            application.applied_at,
            'MISSION_REWARD'::text,
            application.amount_applied,
            'Recompensa de missao'::text,
            null::uuid,
            application.id,
            2
        from public.mission_reward_applications as application
        where application.recipient_student_id = v_student_id
          and application.reward_type = 'BINCOINS'

        union all

        select
            'REDEMPTION:' || redemption.id::text,
            redemption.created_at,
            'REDEMPTION'::text,
            -redemption.cost_points_snapshot,
            redemption.reward_name_snapshot,
            redemption.id,
            redemption.id,
            3
        from public.redemptions as redemption
        where redemption.student_id = v_student_id

        union all

        select
            'REDEMPTION_REFUND:' || redemption.id::text,
            redemption.canceled_at,
            'REDEMPTION_REFUND'::text,
            redemption.cost_points_snapshot,
            redemption.reward_name_snapshot,
            redemption.id,
            redemption.id,
            4
        from public.redemptions as redemption
        where redemption.student_id = v_student_id
          and redemption.status = 'CANCELED'
          and redemption.canceled_at is not null
    )
    select
        movements.movement_id,
        movements.occurred_at,
        movements.movement_type,
        movements.amount,
        movements.title,
        movements.redemption_id,
        movements.source_id
    from movements
    order by
        movements.occurred_at desc,
        movements.source_order asc,
        movements.source_id asc;
end;
$$;

comment on function public.get_my_bincoin_statement_v1() is
    'Consolidates the authenticated student BinCoin movements from domain ledgers; excludes XP and never uses audit_logs.';

revoke all on function public.get_my_binbazar_catalog_v1()
from public, anon, authenticated, service_role;
revoke all on function public.get_my_redemptions_v1()
from public, anon, authenticated, service_role;
revoke all on function public.request_redemption_v1(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.cancel_my_redemption_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_my_bincoin_statement_v1()
from public, anon, authenticated, service_role;

grant execute on function public.get_my_binbazar_catalog_v1()
to authenticated;
grant execute on function public.get_my_redemptions_v1()
to authenticated;
grant execute on function public.request_redemption_v1(uuid, uuid)
to authenticated;
grant execute on function public.cancel_my_redemption_v1(uuid)
to authenticated;
grant execute on function public.get_my_bincoin_statement_v1()
to authenticated;

revoke select, insert, update, delete on table public.rewards
from anon, authenticated;
revoke select, insert, update, delete on table public.redemptions
from anon, authenticated;

commit;
