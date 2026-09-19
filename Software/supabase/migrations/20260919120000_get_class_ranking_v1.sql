-- BinGo V1
-- Migration: 20260919120000_get_class_ranking_v1.sql
--
-- Este arquivo deve permanecer funcionalmente equivalente a
-- database/migrations/019_get_class_ranking_v1.sql.
--
-- Leitura autenticada e somente leitura do Ranking V1. A escola e derivada
-- exclusivamente de auth.uid(); o cliente nao fornece school_id.

create function public.get_class_ranking_v1()
returns table (
    class_id uuid,
    class_name text,
    points_class_balance integer
)
language sql
stable
security definer
set search_path = ''
as $$
    with current_student as materialized (
        select
            student.school_id
        from public.students as student
        join public.classes as current_class
          on current_class.id = student.class_id
         and current_class.school_id = student.school_id
        where student.auth_user_id = auth.uid()
    )
    select
        ranked_class.id as class_id,
        ranked_class.name as class_name,
        ranked_class.points_class_balance
    from current_student as student
    join public.classes as ranked_class
      on ranked_class.school_id = student.school_id
    order by
        ranked_class.points_class_balance desc,
        ranked_class.id asc;
$$;

comment on function public.get_class_ranking_v1() is
    'Lista as turmas da escola do aluno autenticado por saldo atual de XP; UUID e desempate tecnico temporario.';

revoke all on function public.get_class_ranking_v1()
from public, anon, authenticated, service_role;

grant execute on function public.get_class_ranking_v1()
to authenticated;
