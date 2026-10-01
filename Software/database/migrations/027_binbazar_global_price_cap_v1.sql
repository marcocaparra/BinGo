-- 027: teto global BinBazar e produtos escolares completos, sem retroatividade.
begin;

alter table public.audit_logs alter column school_id drop not null;
comment on column public.audit_logs.school_id is
    'NULL representa escopo global; UUID preserva escopo escolar e FK RESTRICT. Atores sempre derivados server-side.';

create table public.global_economic_settings (
    id boolean primary key default true check (id),
    binbazar_max_price integer check (binbazar_max_price > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
insert into public.global_economic_settings(id,binbazar_max_price) values(true,null);
alter table public.global_economic_settings enable row level security;
revoke all on public.global_economic_settings from public,anon,authenticated,service_role;
comment on table public.global_economic_settings is
    'Singleton global. Teto NULL = ainda nao configurado; sem valor inicial inventado. Nenhuma outra regra economica e globalizada.';

-- Recibo imutavel da intencao de criacao: comparar o produto mutavel quebraria
-- replay apos edicao/consumo de estoque. Legados permanecem NULL, sem backfill.
alter table public.rewards
    add column created_by_admin_id uuid references public.admins(id) on delete restrict,
    add column admin_creation_payload jsonb,
    add constraint rewards_admin_creation_pair_check check (
        (created_by_admin_id is null and admin_creation_payload is null)
        or (created_by_admin_id is not null and admin_creation_payload is not null)
    );
comment on column public.rewards.admin_creation_payload is
    'Recibo original normalizado de criacao administrativa por UUID; nunca atualizado por edicao ou operacoes economicas, nem exposto ao browser.';

create function public.get_binbazar_price_cap_v1()
returns table(binbazar_max_price integer)
language plpgsql stable security definer set search_path = '' as $$
begin
    if not exists(select 1 from public.admins a where a.auth_user_id=auth.uid()
        and a.status='ACTIVE' and a.role in ('ADMIN_A','ADMIN_B','ADMIN_C')) then
        raise exception using errcode='42501',message='BINBAZAR_SETTINGS_ACCESS_DENIED';
    end if;
    return query select s.binbazar_max_price from public.global_economic_settings s where s.id;
end; $$;

create function public.update_binbazar_price_cap_v1(p_max_price integer)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_old integer;
begin
    select a.id into v_actor from public.admins a where a.auth_user_id=auth.uid()
        and a.status='ACTIVE' and a.role='ADMIN_A';
    if not found then raise exception using errcode='42501',message='BINBAZAR_SETTINGS_ACCESS_DENIED'; end if;
    if p_max_price is null or p_max_price<=0 then
        raise exception using errcode='22023',message='BINBAZAR_PRICE_CAP_INVALID';
    end if;
    select s.binbazar_max_price into v_old from public.global_economic_settings s where s.id for update;
    if not found then raise exception using errcode='55000',message='BINBAZAR_PRICE_CAP_UNAVAILABLE'; end if;
    if v_old is not distinct from p_max_price then return p_max_price; end if;
    update public.global_economic_settings set binbazar_max_price=p_max_price,updated_at=now() where id;
    insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
        values(null,'ADMIN',v_actor,'BINBAZAR_PRICE_CAP_UPDATED_V1',
            jsonb_build_object('old_max_price',v_old,'new_max_price',p_max_price));
    -- Nunca escreve produtos, snapshots, saldo ou estoque ao reduzir o teto.
    return p_max_price;
end; $$;

create function public.create_admin_binbazar_product_v1(p_reward_id uuid,p_name text,
    p_description text,p_category text,p_cost_points integer,p_stock_qty integer,p_is_active boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare a record; v_cap integer; v_payload jsonb; v_old public.rewards%rowtype;
begin
    select * into a from public.require_school_admin_v1(false);
    p_name := regexp_replace(p_name,'^[[:space:]]+|[[:space:]]+$','','g');
    p_category := nullif(btrim(p_category),'');
    if p_reward_id is null or p_name is null or p_name='' or p_cost_points is null
        or p_cost_points<=0 or p_stock_qty<0 or p_is_active is null then
        raise exception using errcode='22023',message='ADMIN_PRODUCT_INVALID_INPUT';
    end if;
    v_payload := jsonb_build_object('name',p_name,'description',p_description,'category',p_category,
        'cost_points',p_cost_points,'stock_qty',p_stock_qty,'is_active',p_is_active);
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_reward_id::text,27));
    -- Ordem universal das escritas de produto: configuracao SHARE, produto UPDATE.
    -- SHARE permanece ate commit e conflita com UPDATE da configuracao por A.
    select s.binbazar_max_price into v_cap from public.global_economic_settings s where s.id for share;
    if not found then raise exception using errcode='55000',message='BINBAZAR_PRICE_CAP_UNAVAILABLE'; end if;
    select r.* into v_old from public.rewards r where r.id=p_reward_id for update;
    if found then
        if v_old.school_id<>a.school_id or v_old.created_by_admin_id is distinct from a.admin_id
            or v_old.admin_creation_payload is distinct from v_payload then
            raise exception using errcode='23505',message='ADMIN_PRODUCT_ID_CONFLICT';
        end if;
        return v_old.id; -- Replay nao revalida intencao historica contra teto posterior.
    end if;
    if v_cap is null then raise exception using errcode='55000',message='BINBAZAR_PRICE_CAP_UNCONFIGURED'; end if;
    if p_cost_points>v_cap then raise exception using errcode='22023',message='BINBAZAR_PRICE_CAP_EXCEEDED'; end if;
    insert into public.rewards(id,school_id,name,description,category,cost_points,stock_qty,is_active,
        created_by_admin_id,admin_creation_payload)
        values(p_reward_id,a.school_id,p_name,p_description,p_category,p_cost_points,p_stock_qty,p_is_active,
            a.admin_id,v_payload);
    insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
        values(a.school_id,'ADMIN',a.admin_id,'ADMIN_PRODUCT_CREATED_V1',
            jsonb_build_object('reward_id',p_reward_id,'product',v_payload));
    return p_reward_id;
end; $$;

-- Implementacao privada compartilhada por assinatura completa e compatibilidade 026.
create function public.update_admin_binbazar_product_fields_v1(p_reward_id uuid,p_name text,
    p_description text,p_stock_qty integer,p_is_active boolean,p_cost_points integer,
    p_category text,p_with_price boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare a record; old public.rewards%rowtype; v_cap integer; v_price integer; v_category text;
begin
    select * into a from public.require_school_admin_v1(false);
    p_name := regexp_replace(p_name,'^[[:space:]]+|[[:space:]]+$','','g');
    if p_name is null or p_name='' or p_is_active is null or p_stock_qty<0
        or (p_with_price and (p_cost_points is null or p_cost_points<=0)) then
        raise exception using errcode='22023',message='ADMIN_PRODUCT_INVALID_INPUT';
    end if;
    select s.binbazar_max_price into v_cap from public.global_economic_settings s where s.id for share;
    if not found then raise exception using errcode='55000',message='BINBAZAR_PRICE_CAP_UNAVAILABLE'; end if;
    select r.* into old from public.rewards r where r.id=p_reward_id and r.school_id=a.school_id for update;
    if not found then raise exception using errcode='42501',message='ADMIN_PRODUCT_ACCESS_DENIED'; end if;
    v_price := case when p_with_price then p_cost_points else old.cost_points end;
    v_category := case when p_with_price then nullif(btrim(p_category),'') else old.category end;
    if v_price<>old.cost_points then
        if v_cap is null then raise exception using errcode='55000',message='BINBAZAR_PRICE_CAP_UNCONFIGURED'; end if;
        if v_price>v_cap then raise exception using errcode='22023',message='BINBAZAR_PRICE_CAP_EXCEEDED'; end if;
    end if;
    if row(old.name,old.description,old.category,old.cost_points,old.stock_qty,old.is_active)
        is not distinct from row(p_name,p_description,v_category,v_price,p_stock_qty,p_is_active) then
        return old.id;
    end if;
    update public.rewards set name=p_name,description=p_description,category=v_category,
        cost_points=v_price,stock_qty=p_stock_qty,is_active=p_is_active,updated_at=now() where id=old.id;
    insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
        values(a.school_id,'ADMIN',a.admin_id,'ADMIN_PRODUCT_UPDATED_V1',jsonb_build_object('reward_id',old.id,
        'old',jsonb_build_object('name',old.name,'description',old.description,'category',old.category,
            'cost_points',old.cost_points,'stock_qty',old.stock_qty,'is_active',old.is_active),
        'new',jsonb_build_object('name',p_name,'description',p_description,'category',v_category,
            'cost_points',v_price,'stock_qty',p_stock_qty,'is_active',p_is_active)));
    return old.id;
end; $$;

create function public.update_admin_binbazar_product_v1(p_reward_id uuid,p_name text,
    p_description text,p_stock_qty integer,p_is_active boolean,p_cost_points integer,p_category text)
returns uuid language sql security definer set search_path = '' as $$
    select public.update_admin_binbazar_product_fields_v1(p_reward_id,p_name,p_description,
        p_stock_qty,p_is_active,p_cost_points,p_category,true);
$$;

create or replace function public.update_admin_binbazar_product_v1(p_reward_id uuid,p_name text,
    p_description text,p_stock_qty integer,p_is_active boolean)
returns uuid language sql security definer set search_path = '' as $$
    select public.update_admin_binbazar_product_fields_v1(p_reward_id,p_name,p_description,
        p_stock_qty,p_is_active,null,null,false);
$$;
comment on function public.update_admin_binbazar_product_v1(uuid,text,text,integer,boolean) is
    'Compatibilidade 026: somente campos nao-preco, mesmo com teto NULL ou preco historico acima dele. No-op nao duplica auditoria.';
revoke all on function public.get_binbazar_price_cap_v1() from public,anon,authenticated,service_role;
grant execute on function public.get_binbazar_price_cap_v1() to authenticated;
revoke all on function public.update_binbazar_price_cap_v1(integer) from public,anon,authenticated,service_role;
grant execute on function public.update_binbazar_price_cap_v1(integer) to authenticated;
revoke all on function public.create_admin_binbazar_product_v1(uuid,text,text,text,integer,integer,boolean) from public,anon,authenticated,service_role;
grant execute on function public.create_admin_binbazar_product_v1(uuid,text,text,text,integer,integer,boolean) to authenticated;
revoke all on function public.update_admin_binbazar_product_v1(uuid,text,text,integer,boolean,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.update_admin_binbazar_product_v1(uuid,text,text,integer,boolean,integer,text) to authenticated;
revoke all on function public.update_admin_binbazar_product_v1(uuid,text,text,integer,boolean) from public,anon,authenticated,service_role;
grant execute on function public.update_admin_binbazar_product_v1(uuid,text,text,integer,boolean) to authenticated;
revoke all on function public.update_admin_binbazar_product_fields_v1(uuid,text,text,integer,boolean,integer,text,boolean) from public,anon,authenticated,service_role;
commit;
