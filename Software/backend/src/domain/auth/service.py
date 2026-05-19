from uuid import UUID

from sqlalchemy.orm import Session

from domain.audit.service import register_audit
from infra.auth.jwt_service import create_access_token
from infra.crypto.security import hash_secret, verify_secret
from infra.repositories.admin_repository import AdminRepository
from infra.repositories.student_repository import StudentRepository
from shared.constants.enums import ActorType, PrincipalType, StudentStatus
from shared.errors.exceptions import ForbiddenError, NotFoundError, UnauthorizedError


def activate_student(session: Session, school_id: UUID, class_id: UUID, student_id: UUID, pin: str) -> str:
    repo = StudentRepository(session)
    student = repo.get_by_id(student_id)
    if student is None or student.school_id != school_id or student.class_id != class_id:
        raise NotFoundError("Aluno não encontrado no contexto informado.")
    if student.status != StudentStatus.ACTIVE:
        raise ForbiddenError("Aluno inativo.")
    if student.is_activated:
        raise ForbiddenError("Aluno já ativado.")

    try:
        student.pin_hash = hash_secret(pin, digits_only=True)
        student.is_activated = True
        register_audit(
            session,
            school_id=school_id,
            actor_type=ActorType.STUDENT,
            actor_id=student.id,
            action="STUDENT_PIN_ACTIVATED",
        )
        session.commit()
    except Exception:
        session.rollback()
        raise

    return create_access_token(str(student.id), PrincipalType.STUDENT.value, str(student.school_id), {"class_id": str(student.class_id)})


def login_student(session: Session, school_id: UUID, class_id: UUID, student_id: UUID, pin: str) -> str:
    repo = StudentRepository(session)
    student = repo.get_by_id(student_id)
    if student is None or student.school_id != school_id or student.class_id != class_id:
        raise NotFoundError("Aluno não encontrado no contexto informado.")
    if student.status != StudentStatus.ACTIVE:
        raise ForbiddenError("Aluno inativo.")
    if not student.pin_hash or not verify_secret(pin, student.pin_hash, digits_only=True):
        raise UnauthorizedError("PIN inválido.")

    return create_access_token(str(student.id), PrincipalType.STUDENT.value, str(student.school_id), {"class_id": str(student.class_id)})


def login_admin(session: Session, email: str, password: str) -> str:
    repo = AdminRepository(session)
    admin = repo.get_by_email(email)
    if admin is None or not admin.password_hash or not verify_secret(password, admin.password_hash):
        raise UnauthorizedError("Credenciais administrativas inválidas.")

    role = admin.role.value if hasattr(admin.role, "value") else str(admin.role)

    return create_access_token(
        str(admin.id),
        PrincipalType.BINGO_ADMIN.value if role == "BINGO_ADMIN" else PrincipalType.ADMIN_SCHOOL.value,
        str(admin.school_id),
        {"role": role},
    )


def reset_student_pin(session: Session, admin_id: UUID, student_id: UUID, new_pin: str) -> None:
    admin_repo = AdminRepository(session)
    student_repo = StudentRepository(session)
    admin = admin_repo.get_by_id(admin_id)
    student = student_repo.get_by_id(student_id)
    if admin is None:
        raise UnauthorizedError("Admin inválido.")
    if student is None or student.school_id != admin.school_id:
        raise NotFoundError("Aluno não encontrado para este admin.")

    try:
        student.pin_hash = hash_secret(new_pin, digits_only=True)
        student.is_activated = True
        register_audit(
            session,
            school_id=student.school_id,
            actor_type=ActorType.ADMIN,
            actor_id=admin.id,
            action="STUDENT_PIN_RESET",
            metadata={"student_id": str(student.id)},
        )
        session.commit()
    except Exception:
        session.rollback()
        raise
