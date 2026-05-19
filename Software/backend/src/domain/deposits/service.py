from sqlalchemy.orm import Session

from app.api.schemas.deposits import DepositCreateRequest
from domain.audit.service import register_audit
from infra.db.models import Deposit
from infra.repositories.deposit_repository import DepositRepository
from infra.repositories.machine_repository import MachineRepository
from infra.repositories.student_repository import StudentRepository
from shared.constants.enums import ActorType, DepositSize
from shared.errors.exceptions import AppError, NotFoundError
from shared.utils.time import utcnow


def _calculate_points(settings, size: DepositSize) -> tuple[int, int]:
    if size == DepositSize.SMALL:
        return settings.points_small_student, settings.points_small_class
    if size == DepositSize.MEDIUM:
        return settings.points_medium_student, settings.points_medium_class
    return settings.points_large_student, settings.points_large_class


def register_deposit(session: Session, payload: DepositCreateRequest) -> Deposit:
    deposit_repo = DepositRepository(session)
    existing = deposit_repo.get_by_event_id(payload.event_id)
    if existing is not None:
        return existing

    student_repo = StudentRepository(session)
    machine = MachineRepository(session).get_by_id(payload.machine_id)
    classroom = student_repo.get_classroom(payload.class_id)
    settings = student_repo.get_school_settings(payload.school_id)

    if machine is None or machine.school_id != payload.school_id:
        raise NotFoundError("Máquina inválida para a escola informada.")
    if classroom is None or classroom.school_id != payload.school_id:
        raise NotFoundError("Turma inválida para a escola informada.")
    if settings is None:
        raise AppError("A escola não possui configurações operacionais.")

    student = None
    if payload.student_id is not None:
        student = student_repo.get_by_id(payload.student_id)
        if student is None or student.school_id != payload.school_id or student.class_id != payload.class_id:
            raise NotFoundError("Aluno inválido para o depósito informado.")

    awarded_student = 0
    awarded_class = 0
    if payload.is_valid:
        base_student, base_class = _calculate_points(settings, payload.size)
        awarded_class = base_class
        if student is not None:
            awarded_student = base_student
            if payload.size == DepositSize.SMALL:
                small_items_today = deposit_repo.count_student_small_items_on_day(student.id, utcnow())
                if small_items_today >= settings.small_item_daily_limit:
                    awarded_student = 0

    deposit = Deposit(
        event_id=payload.event_id,
        school_id=payload.school_id,
        machine_id=payload.machine_id,
        class_id=payload.class_id,
        student_id=payload.student_id,
        is_valid=payload.is_valid,
        detected_type=payload.detected_type,
        size=payload.size,
        points_awarded_student=awarded_student,
        points_awarded_class=awarded_class,
    )

    try:
        session.add(deposit)
        classroom.points_class_balance += awarded_class
        if student is not None:
            student.points_student_balance += awarded_student
        register_audit(
            session,
            school_id=payload.school_id,
            actor_type=ActorType.MACHINE,
            actor_id=payload.machine_id,
            action="DEPOSIT_SYNCED",
            metadata={"event_id": str(payload.event_id), "awarded_student": awarded_student, "awarded_class": awarded_class},
        )
        session.commit()
    except Exception:
        session.rollback()
        raise

    session.refresh(deposit)
    return deposit
