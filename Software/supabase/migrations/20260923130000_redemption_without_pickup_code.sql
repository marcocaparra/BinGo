-- Supabase migration: remove pickup codes from new Mobile redemptions.
begin;

alter table public.redemptions
    alter column code drop not null;

comment on column public.redemptions.code is
    'Legacy pickup code. Preserved for historical rows; new Mobile redemptions persist NULL.';

create or replace function public.request_redemption_v1(
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
        null,
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
    'Atomically requests a Mobile redemption without a pickup code, charging the immutable snapshot and reserving finite stock.';

revoke all on function public.request_redemption_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.request_redemption_v1(uuid, uuid)
to authenticated;

commit;
