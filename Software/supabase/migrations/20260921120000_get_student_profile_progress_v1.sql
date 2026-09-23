-- BinGo V1
-- Migration: 20260921120000_get_student_profile_progress_v1.sql
-- Executavelmente equivalente a
-- database/migrations/020_get_student_profile_progress_v1.sql.

create function public.get_student_profile_progress_v1()
returns table (
    student_id uuid,
    valid_deposit_count bigint,
    level_number integer,
    level_code text,
    remaining_to_next_level bigint,
    progress_to_next_level numeric
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
    ),
    progress as (
        select
            student.id as student_id,
            count(deposit.id)::bigint as valid_deposit_count
        from current_student as student
        left join public.deposits as deposit
          on deposit.student_id = student.id
         and deposit.is_valid = true
        group by student.id
    )
    select
        progress.student_id,
        progress.valid_deposit_count,
        case
            when progress.valid_deposit_count >= 50 then 5
            when progress.valid_deposit_count >= 20 then 4
            when progress.valid_deposit_count >= 10 then 3
            when progress.valid_deposit_count >= 5 then 2
            when progress.valid_deposit_count >= 1 then 1
            else 0
        end as level_number,
        case
            when progress.valid_deposit_count >= 50 then 'HERO'
            when progress.valid_deposit_count >= 20 then 'GUARDIAN'
            when progress.valid_deposit_count >= 10 then 'RESTORER'
            when progress.valid_deposit_count >= 5 then 'EXPLORER'
            when progress.valid_deposit_count >= 1 then 'APPRENTICE'
            else 'NONE'
        end as level_code,
        case
            when progress.valid_deposit_count >= 50 then 0
            when progress.valid_deposit_count >= 20 then 50 - progress.valid_deposit_count
            when progress.valid_deposit_count >= 10 then 20 - progress.valid_deposit_count
            when progress.valid_deposit_count >= 5 then 10 - progress.valid_deposit_count
            when progress.valid_deposit_count >= 1 then 5 - progress.valid_deposit_count
            else 1
        end::bigint as remaining_to_next_level,
        case
            when progress.valid_deposit_count >= 50 then 1::numeric
            when progress.valid_deposit_count >= 20 then
                least(1::numeric, progress.valid_deposit_count::numeric / 50)
            when progress.valid_deposit_count >= 10 then
                least(1::numeric, progress.valid_deposit_count::numeric / 20)
            when progress.valid_deposit_count >= 5 then
                least(1::numeric, progress.valid_deposit_count::numeric / 10)
            when progress.valid_deposit_count >= 1 then
                least(1::numeric, progress.valid_deposit_count::numeric / 5)
            else 0::numeric
        end as progress_to_next_level
    from progress;
$$;

comment on function public.get_student_profile_progress_v1() is
    'Deriva a Trilha do Restaurador dos descartes validos do aluno autenticado; nao persiste progresso.';

revoke all on function public.get_student_profile_progress_v1()
from public, anon, authenticated, service_role;

grant execute on function public.get_student_profile_progress_v1()
to authenticated;
