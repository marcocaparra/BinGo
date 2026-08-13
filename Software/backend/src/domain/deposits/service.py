from decimal import Decimal, ROUND_HALF_UP
from uuid import UUID

from sqlalchemy.orm import Session

from app.api.schemas.deposits import DepositCreateRequest
from domain.audit.service import register_audit
from infra.db.models import Deposit
from infra.repositories.deposit_repository import DepositRepository
from infra.repositories.machine_repository import MachineRepository
from infra.repositories.student_repository import StudentRepository
from infra.repositories.waste_category_repository import WasteCategoryRepository
from shared.constants.enums import ActorType, StudentStatus
from shared.errors.exceptions import AppError, ConflictError, NotFoundError


def _calculate_bonus(base_bincoins: int, bonus_rate: Decimal) -> int:
    return int((Decimal(base_bincoins) * bonus_rate).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _assert_idempotent_replay(
    existing: Deposit,
    payload: DepositCreateRequest,
    *,
    school_id: UUID,
    machine_id: UUID,
) -> None:
    existing_category_code = existing.waste_category.code if existing.waste_category is not None else None
    requested_category_code = payload.waste_category_code.value if payload.waste_category_code is not None else None
    requested_category_source = payload.category_source.value if payload.category_source is not None else None
    existing_category_source = (
        getattr(existing.category_source, "value", existing.category_source)
        if existing.category_source is not None
        else None
    )

    if (
        existing.school_id != school_id
        or existing.machine_id != machine_id
        or existing.class_id != payload.class_id
        or existing.student_id != payload.student_id
        or existing.is_valid != payload.is_valid
        or existing.detected_type != payload.detected_type
        or existing_category_code != requested_category_code
        or existing_category_source != requested_category_source
    ):
        raise ConflictError("event_id reutilizado com dados diferentes.")


def register_deposit(
    session: Session,
    payload: DepositCreateRequest,
    *,
    school_id: UUID,
    machine_id: UUID,
) -> Deposit:
    deposit_repo = DepositRepository(session)
    existing = deposit_repo.get_by_event_id(payload.event_id)
    if existing is not None:
        _assert_idempotent_replay(
            existing,
            payload,
            school_id=school_id,
            machine_id=machine_id,
        )
        return existing

    student_repo = StudentRepository(session)
    machine = MachineRepository(session).get_by_id(machine_id)
    classroom = student_repo.get_classroom(payload.class_id)
    settings = student_repo.get_school_settings(school_id)

    if machine is None or machine.school_id != school_id:
        raise NotFoundError("Máquina inválida para a escola informada.")
    if classroom is None or classroom.school_id != school_id:
        raise NotFoundError("Turma inválida para a escola informada.")
    if settings is None:
        raise AppError("A escola não possui configurações operacionais.")

    student = None
    if payload.student_id is not None:
        student = student_repo.get_by_id(payload.student_id)
        if (
            student is None
            or student.school_id != school_id
            or student.class_id != payload.class_id
            or student.status != StudentStatus.ACTIVE
        ):
            raise NotFoundError("Aluno inválido para o depósito informado.")

    category = None
    bonus_rate = Decimal("0")
    bonus_bincoins = 0
    awarded_student = 0
    awarded_class = 0
    if payload.is_valid:
        category = WasteCategoryRepository(session).get_active_by_code(payload.waste_category_code)
        if category is None:
            raise NotFoundError("Categoria de lixo eletrônico inexistente ou inativa.")
        bonus_rate = category.bonus_rate
        awarded_class = settings.deposit_class_xp_base
        if student is not None:
            bonus_bincoins = _calculate_bonus(settings.deposit_bincoins_base, bonus_rate)
            awarded_student = settings.deposit_bincoins_base + bonus_bincoins

    deposit = Deposit(
        event_id=payload.event_id,
        school_id=school_id,
        machine_id=machine_id,
        class_id=payload.class_id,
        student_id=payload.student_id,
        is_valid=payload.is_valid,
        detected_type=payload.detected_type,
        waste_category=category,
        category_source=payload.category_source,
        bonus_rate_applied=bonus_rate,
        bonus_bincoins_awarded=bonus_bincoins,
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
            school_id=school_id,
            actor_type=ActorType.MACHINE,
            actor_id=machine_id,
            action="DEPOSIT_REGISTERED",
            metadata={
                "event_id": str(payload.event_id),
                "detected_type": payload.detected_type,
                "waste_category_code": category.code if category is not None else None,
                "category_source": payload.category_source.value if payload.category_source is not None else None,
                "bonus_rate_applied": str(bonus_rate),
                "bonus_bincoins_awarded": bonus_bincoins,
                "points_awarded_student": awarded_student,
                "points_awarded_class": awarded_class,
            },
        )
        session.commit()
    except Exception:
        session.rollback()
        raise

    session.refresh(deposit)
    return deposit
