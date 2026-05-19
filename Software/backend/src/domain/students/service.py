from uuid import UUID

from sqlalchemy.orm import Session

from app.api.schemas.students import MeProfileResponse, StudentDepositItem, StudentRedemptionItem
from infra.repositories.deposit_repository import DepositRepository
from infra.repositories.student_repository import StudentRepository
from shared.errors.exceptions import NotFoundError


def get_profile(session: Session, student_id: UUID) -> MeProfileResponse:
    repo = StudentRepository(session)
    student = repo.get_by_id(student_id)
    if student is None:
        raise NotFoundError("Aluno não encontrado.")
    classroom = repo.get_classroom(student.class_id)
    if classroom is None:
        raise NotFoundError("Turma do aluno não encontrada.")
    return MeProfileResponse(
        id=student.id,
        name=student.name,
        school_id=student.school_id,
        class_id=student.class_id,
        points_student_balance=student.points_student_balance,
        points_class_balance=classroom.points_class_balance,
    )


def list_my_deposits(session: Session, student_id: UUID) -> list[StudentDepositItem]:
    deposits = DepositRepository(session).list_for_student(student_id)
    return [
        StudentDepositItem(
            event_id=item.event_id,
            is_valid=item.is_valid,
            detected_type=item.detected_type,
            points_awarded_student=item.points_awarded_student,
            points_awarded_class=item.points_awarded_class,
            created_at=item.created_at,
        )
        for item in deposits
    ]


def list_my_redemptions(session: Session, student_id: UUID) -> list[StudentRedemptionItem]:
    redemptions = StudentRepository(session).list_redemptions(student_id)
    return [
        StudentRedemptionItem(
            id=item.id,
            code=item.code,
            status=item.status.value,
            created_at=item.created_at,
        )
        for item in redemptions
    ]
