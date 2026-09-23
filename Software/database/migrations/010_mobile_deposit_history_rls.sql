-- BinGo V1
-- Migration: 010_mobile_deposit_history_rls.sql
--
-- Autoriza a primeira leitura Mobile do historico proprio de descartes.
-- A identidade acompanha o registro do aluno, sem depender de sua escola atual.

create policy deposits_select_own_history_v1
on public.deposits
for select
to authenticated
using (
    student_id is not null
    and exists (
        select 1
        from public.students as current_student
        where current_student.auth_user_id = (select auth.uid())
          and current_student.id = deposits.student_id
    )
);

grant select (
    id,
    student_id,
    created_at,
    is_valid,
    detected_type,
    waste_category_id,
    category_source,
    bonus_bincoins_awarded,
    points_awarded_student,
    points_awarded_class
)
on public.deposits
to authenticated;
