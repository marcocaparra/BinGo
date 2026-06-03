from uuid import UUID

from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from infra.db.models import ClassRoom, Deposit, Machine, School, Student
from shared.errors.exceptions import NotFoundError


def get_context(session: Session, machine: Machine) -> dict:
    school = session.get(School, machine.school_id)
    if school is None:
        raise NotFoundError("Escola da máquina não encontrada.")

    classes = list(
        session.scalars(
            select(ClassRoom)
            .where(ClassRoom.school_id == machine.school_id)
            .order_by(ClassRoom.name.asc())
        )
    )
    students = list(
        session.execute(
            select(Student, ClassRoom.name)
            .join(ClassRoom, ClassRoom.id == Student.class_id)
            .where(Student.school_id == machine.school_id)
            .order_by(Student.name.asc())
        )
    )

    return {
        "school": school,
        "machine": machine,
        "classes": classes,
        "students": students,
    }


def get_student_identity(session: Session, machine: Machine, student_id: UUID):
    student_row = session.execute(
        select(Student, ClassRoom.name)
        .join(ClassRoom, ClassRoom.id == Student.class_id)
        .where(Student.id == student_id, Student.school_id == machine.school_id)
    ).one_or_none()
    if student_row is None:
        raise NotFoundError("Aluno nÃ£o encontrado para a escola da mÃ¡quina.")
    return student_row


def get_student_summary(session: Session, machine: Machine, student_id: UUID) -> dict:
    student_row = session.execute(
        select(Student, ClassRoom.name)
        .join(ClassRoom, ClassRoom.id == Student.class_id)
        .where(Student.id == student_id, Student.school_id == machine.school_id)
    ).one_or_none()
    if student_row is None:
        raise NotFoundError("Aluno não encontrado para a escola da máquina.")

    student, class_name = student_row
    stats_row = session.execute(
        select(
            func.count(case((Deposit.is_valid.is_(True), 1))).label("valid_count"),
            func.count(case((Deposit.is_valid.is_(False), 1))).label("invalid_count"),
            func.coalesce(
                func.sum(case((Deposit.is_valid.is_(True), Deposit.points_awarded_student), else_=0)),
                0,
            ).label("total_bins"),
        ).where(Deposit.student_id == student_id, Deposit.school_id == machine.school_id)
    ).one()
    recent_deposits = list(
        session.scalars(
            select(Deposit)
            .where(Deposit.student_id == student_id, Deposit.school_id == machine.school_id)
            .order_by(Deposit.created_at.desc())
            .limit(5)
        )
    )

    return {
        "student": student,
        "class_name": class_name,
        "valid_deposits_count": stats_row.valid_count,
        "invalid_deposits_count": stats_row.invalid_count,
        "total_bins_generated": stats_row.total_bins,
        "recent_deposits": recent_deposits,
    }


def get_rankings(session: Session, machine: Machine) -> dict:
    students = list(
        session.execute(
            select(Student, ClassRoom.name)
            .join(ClassRoom, ClassRoom.id == Student.class_id)
            .where(Student.school_id == machine.school_id)
            .order_by(Student.points_student_balance.desc(), Student.name.asc())
        )
    )
    classes = list(
        session.scalars(
            select(ClassRoom)
            .where(ClassRoom.school_id == machine.school_id)
            .order_by(ClassRoom.points_class_balance.desc(), ClassRoom.name.asc())
        )
    )

    return {
        "students": students,
        "classes": classes,
    }
