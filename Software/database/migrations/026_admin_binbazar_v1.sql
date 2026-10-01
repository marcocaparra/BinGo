-- Admin BinBazar: operacao escolar B/C; preco/criacao bloqueados sem teto global.
begin;

create function public.get_admin_binbazar_products_v1()
returns table(reward_id uuid,name text,description text,category text,cost_points integer,is_active boolean,stock_qty integer)
language plpgsql stable security definer set search_path = '' as $$
declare a record;
begin
 select * into a from public.require_school_admin_v1(false);
 return query select r.id,r.name,r.description,r.category,r.cost_points,r.is_active,r.stock_qty
 from public.rewards r where r.school_id=a.school_id order by r.name,r.id;
end; $$;

create function public.update_admin_binbazar_product_v1(p_reward_id uuid,p_name text,p_description text,p_stock_qty integer,p_is_active boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare a record; old public.rewards%rowtype;
begin
 select * into a from public.require_school_admin_v1(false);
 p_name := regexp_replace(p_name,'^[[:space:]]+|[[:space:]]+$','','g');
 if p_name is null or p_name='' or p_is_active is null or p_stock_qty<0 then
  raise exception using errcode='22023',message='ADMIN_PRODUCT_INVALID_INPUT';
 end if;
 select r.* into old from public.rewards r where r.id=p_reward_id and r.school_id=a.school_id for update;
 if not found then raise exception using errcode='42501',message='ADMIN_PRODUCT_ACCESS_DENIED'; end if;
 update public.rewards set name=p_name,description=p_description,stock_qty=p_stock_qty,is_active=p_is_active,updated_at=now() where id=old.id;
 insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
 values(a.school_id,'ADMIN',a.admin_id,'ADMIN_PRODUCT_UPDATED_V1',jsonb_build_object('reward_id',old.id,
 'old',jsonb_build_object('name',old.name,'description',old.description,'stock_qty',old.stock_qty,'is_active',old.is_active),
 'new',jsonb_build_object('name',p_name,'description',p_description,'stock_qty',p_stock_qty,'is_active',p_is_active)));
 return old.id;
end; $$;

create function public.get_admin_redemptions_v1()
returns table(redemption_id uuid,code text,status text,student_id uuid,student_name text,registration text,
 class_id uuid,class_name text,reward_id uuid,reward_name_snapshot text,cost_points_snapshot integer,
 created_at timestamptz,delivered_at timestamptz,canceled_at timestamptz,delivered_by_admin_id uuid,delivered_by_admin_name text)
language plpgsql stable security definer set search_path = '' as $$
declare a record;
begin
 select * into a from public.require_school_admin_v1(false);
 return query select r.id,r.code,r.status,s.id,s.name,s.registration,c.id,c.name,r.reward_id,
 r.reward_name_snapshot,r.cost_points_snapshot,r.created_at,r.delivered_at,r.canceled_at,d.id,d.name
 from public.redemptions r join public.students s on s.id=r.student_id and s.school_id=r.school_id
 join public.classes c on c.id=s.class_id and c.school_id=r.school_id
 left join public.admins d on d.id=r.delivered_by_admin_id
 where r.school_id=a.school_id order by r.created_at desc,r.id;
end; $$;

-- Nucleo interno compartilhado com cancel_my_redemption_v1 (022).
-- O chamador valida identidade/escopo; este helper NAO e executavel pelo browser.
-- Lock de redemption primeiro, aluno depois, produto por ultimo, como na 022.
create function public.refund_pending_redemption_v1(p_id uuid,p_actor_type text,p_actor_id uuid,p_audit_school_id uuid)
returns public.redemptions language plpgsql security definer set search_path = '' as $$
declare r public.redemptions%rowtype; restored integer := 0;
begin
 select x.* into r from public.redemptions x where x.id=p_id for update;
 if not found then raise exception using errcode='P0002',message='Resgate nao encontrado.'; end if;
 if r.status <> 'PENDING' then raise exception using errcode='55000',message='Somente resgate pendente pode ser cancelado.'; end if;
 if r.cost_points_snapshot is null or r.reward_name_snapshot is null or r.stock_was_finite is null then
  raise exception using errcode='P0001',message='Resgate legado sem snapshot nao pode ser cancelado por este caminho.';
 end if;
 update public.students s set points_student_balance=s.points_student_balance+r.cost_points_snapshot,updated_at=now() where id=r.student_id;
 if r.stock_was_finite then
  update public.rewards w set stock_qty=w.stock_qty+1,updated_at=now() where id=r.reward_id and stock_qty is not null;
  get diagnostics restored = row_count;
 end if;
 update public.redemptions set status='CANCELED',canceled_at=now() where id=r.id returning * into r;
 insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
 values(p_audit_school_id,p_actor_type,p_actor_id,
 case when p_actor_type='STUDENT' then 'REDEMPTION_CANCELED_V1' else 'ADMIN_REDEMPTION_CANCELED_V1' end,
 jsonb_build_object('redemption_id',r.id,'reward_id',r.reward_id,'reward_name_snapshot',r.reward_name_snapshot,
 'cost_points_refunded',r.cost_points_snapshot,'finite_stock_reserved',r.stock_was_finite,'finite_stock_restored',restored=1) || case when p_actor_type='ADMIN' then
 jsonb_build_object('student_id',r.student_id,'old_status','PENDING','new_status','CANCELED') else '{}'::jsonb end);
 return r;
end; $$;

-- Mesmo contrato, autorizacao, replay e resultado do Mobile; economia compartilhada.
create or replace function public.cancel_my_redemption_v1(p_redemption_id uuid)
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

    v_redemption := public.refund_pending_redemption_v1(v_redemption.id, 'STUDENT', v_student_id, v_school_id);

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


create function public.deliver_admin_redemption_v1(p_redemption_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare a record; r public.redemptions%rowtype;
begin
 select * into a from public.require_school_admin_v1(false);
 select x.* into r from public.redemptions x where x.id=p_redemption_id for update;
 if not found or r.school_id<>a.school_id
 or not exists(select 1 from public.students s where s.id=r.student_id and s.school_id=a.school_id)
 or not exists(select 1 from public.rewards w where w.id=r.reward_id and w.school_id=a.school_id) then
  raise exception using errcode='42501',message='ADMIN_REDEMPTION_ACCESS_DENIED';
 end if;
 if r.status='DELIVERED' then return r.id; end if;
 if r.status<>'PENDING' then raise exception using errcode='55000',message='ADMIN_REDEMPTION_CONFLICT'; end if;
 update public.redemptions set status='DELIVERED',delivered_at=now(),delivered_by_admin_id=a.admin_id where id=r.id;
 insert into public.audit_logs(school_id,actor_type,actor_id,action,metadata)
 values(a.school_id,'ADMIN',a.admin_id,'ADMIN_REDEMPTION_DELIVERED_V1',
 jsonb_build_object('redemption_id',r.id,'student_id',r.student_id,'reward_id',r.reward_id,'old_status','PENDING','new_status','DELIVERED'));
 return r.id;
end; $$;

create function public.cancel_admin_redemption_v1(p_redemption_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare a record; r public.redemptions%rowtype;
begin
 select * into a from public.require_school_admin_v1(false);
 select x.* into r from public.redemptions x where x.id=p_redemption_id for update;
 if not found or r.school_id<>a.school_id
 or not exists(select 1 from public.students s where s.id=r.student_id and s.school_id=a.school_id)
 or not exists(select 1 from public.rewards w where w.id=r.reward_id and w.school_id=a.school_id) then
  raise exception using errcode='42501',message='ADMIN_REDEMPTION_ACCESS_DENIED';
 end if;
 if r.status='CANCELED' then return r.id; end if;
 if r.status<>'PENDING' then raise exception using errcode='55000',message='ADMIN_REDEMPTION_CONFLICT'; end if;
 perform public.refund_pending_redemption_v1(r.id,'ADMIN',a.admin_id,a.school_id);
 return r.id;
end; $$;

comment on function public.update_admin_binbazar_product_v1(uuid,text,text,integer,boolean) is
 'B/C ACTIVE da propria escola. Sem preco, escola, criacao ou exclusao: teto global ainda nao persistido. is_active e autoridade; status legado nao e alterado.';
revoke all on function public.get_admin_binbazar_products_v1() from public,anon,authenticated,service_role;
grant execute on function public.get_admin_binbazar_products_v1() to authenticated;
revoke all on function public.update_admin_binbazar_product_v1(uuid,text,text,integer,boolean) from public,anon,authenticated,service_role;
grant execute on function public.update_admin_binbazar_product_v1(uuid,text,text,integer,boolean) to authenticated;
revoke all on function public.get_admin_redemptions_v1() from public,anon,authenticated,service_role;
grant execute on function public.get_admin_redemptions_v1() to authenticated;
revoke all on function public.deliver_admin_redemption_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.deliver_admin_redemption_v1(uuid) to authenticated;
revoke all on function public.cancel_admin_redemption_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.cancel_admin_redemption_v1(uuid) to authenticated;
revoke all on function public.refund_pending_redemption_v1(uuid,text,uuid,uuid) from public,anon,authenticated,service_role;
revoke select,insert,update,delete on public.rewards,public.redemptions from anon,authenticated;
commit;
