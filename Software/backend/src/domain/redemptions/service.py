import secrets
from datetime import timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from domain.audit.service import register_audit
from infra.db.models import Redemption
from infra.repositories.admin_repository import AdminRepository
from infra.repositories.reward_repository import RewardRepository
from infra.repositories.student_repository import StudentRepository
from shared.constants.enums import ActorType, RedemptionStatus, RewardStatus
from shared.errors.exceptions import AppError, ForbiddenError, NotFoundError
from shared.utils.time import ensure_utc, utcnow


def _generate_code() -> str:
    return secrets.token_hex(4).upper()


def create_redemption(session: Session, school_id: UUID, student_id: UUID, reward_id: UUID) -> Redemption:
    student_repo = StudentRepository(session)
    student = student_repo.get_by_id(student_id)
    settings = student_repo.get_school_settings(school_id)
    reward = RewardRepository(session).get_by_id(reward_id)

    if student is None or student.school_id != school_id:
        raise NotFoundError("Aluno inválido.")
    if settings is None:
        raise AppError("A escola não possui configurações operacionais.")
    if reward is None or reward.school_id != school_id:
        raise NotFoundError("Recompensa inválida.")
    if not reward.is_active or reward.status != RewardStatus.AVAILABLE:
        raise ForbiddenError("Recompensa indisponível.")
    if reward.stock_qty is not None and reward.stock_qty <= 0:
        raise ForbiddenError("Recompensa sem estoque.")
    if student.points_student_balance < reward.cost_points:
        raise ForbiddenError("Saldo insuficiente para resgate.")

    today_count = session.scalar(
        select(func.count(Redemption.id)).where(
            Redemption.student_id == student.id,
            func.date(Redemption.created_at) == utcnow().date(),
        )
    ) or 0
    pending_count = session.scalar(
        select(func.count(Redemption.id)).where(
            Redemption.student_id == student.id,
            Redemption.status == RedemptionStatus.PENDING,
        )
    ) or 0

    if today_count >= settings.redemption_daily_limit:
        raise ForbiddenError("Limite diário de resgates atingido.")
    if pending_count >= settings.redemption_max_pending:
        raise ForbiddenError("Quantidade máxima de resgates pendentes atingida.")

    redemption = Redemption(
        school_id=school_id,
        student_id=student_id,
        reward_id=reward_id,
        code=_generate_code(),
        status=RedemptionStatus.PENDING,
        request_channel="TOTEM",
        expires_at=utcnow() + timedelta(hours=settings.redemption_expiration_hours),
    )

    try:
        student.points_student_balance -= reward.cost_points
        if reward.stock_qty is not None:
            reward.stock_qty -= 1
        session.add(redemption)
        register_audit(
            session,
            school_id=school_id,
            actor_type=ActorType.STUDENT,
            actor_id=student_id,
            action="REDEMPTION_CREATED",
            metadata={"reward_id": str(reward_id), "code": redemption.code},
        )
        session.commit()
    except Exception:
        session.rollback()
        raise

    session.refresh(redemption)
    return redemption


def get_redemption_by_code(session: Session, code: str) -> Redemption:
    redemption = session.scalar(select(Redemption).where(Redemption.code == code))
    if redemption is None:
        raise NotFoundError("Código de resgate não encontrado.")
    expires_at = ensure_utc(redemption.expires_at)
    if redemption.status == RedemptionStatus.PENDING and expires_at and expires_at < utcnow():
        redemption.status = RedemptionStatus.EXPIRED
        session.commit()
    return redemption


def deliver_redemption(session: Session, redemption_id: UUID, admin_id: UUID) -> Redemption:
    redemption = session.get(Redemption, redemption_id)
    admin = AdminRepository(session).get_by_id(admin_id)
    if redemption is None:
        raise NotFoundError("Resgate não encontrado.")
    if admin is None or admin.school_id != redemption.school_id:
        raise ForbiddenError("Admin sem autorização para este resgate.")
    if redemption.status != RedemptionStatus.PENDING:
        raise ForbiddenError("Somente resgates pendentes podem ser entregues.")
    expires_at = ensure_utc(redemption.expires_at)
    if expires_at and expires_at < utcnow():
        redemption.status = RedemptionStatus.EXPIRED
        session.commit()
        raise ForbiddenError("Resgate expirado.")

    try:
        redemption.status = RedemptionStatus.DELIVERED
        redemption.delivered_at = utcnow()
        redemption.delivered_by_admin_id = admin_id
        register_audit(
            session,
            school_id=redemption.school_id,
            actor_type=ActorType.ADMIN,
            actor_id=admin_id,
            action="REDEMPTION_DELIVERED",
            metadata={"redemption_id": str(redemption.id)},
        )
        session.commit()
    except Exception:
        session.rollback()
        raise
    session.refresh(redemption)
    return redemption


def list_today_redemptions(session: Session, school_id: UUID) -> list[Redemption]:
    return list(
        session.scalars(
            select(Redemption).where(
                Redemption.school_id == school_id,
                func.date(Redemption.created_at) == utcnow().date(),
            ).order_by(Redemption.created_at.desc())
        )
    )
