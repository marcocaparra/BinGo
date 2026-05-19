from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import JSON, Boolean, CheckConstraint, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import Uuid

from infra.db.base import Base
from shared.constants.enums import ActorType, AdminRole, DepositSize, MachineStatus, RedemptionStatus, RewardStatus, StudentStatus


class School(Base):
    __tablename__ = "schools"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class SchoolSetting(Base):
    __tablename__ = "school_settings"

    school_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("schools.id", ondelete="RESTRICT"), primary_key=True)
    small_item_daily_limit: Mapped[int] = mapped_column(Integer, nullable=False, default=5)
    points_small_student: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    points_small_class: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    points_medium_student: Mapped[int] = mapped_column(Integer, nullable=False, default=30)
    points_medium_class: Mapped[int] = mapped_column(Integer, nullable=False, default=30)
    points_large_student: Mapped[int] = mapped_column(Integer, nullable=False, default=50)
    points_large_class: Mapped[int] = mapped_column(Integer, nullable=False, default=50)
    redemption_expiration_hours: Mapped[int] = mapped_column(Integer, nullable=False, default=72)
    redemption_daily_limit: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    redemption_max_pending: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class ClassRoom(Base):
    __tablename__ = "classes"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    school_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False)
    segment: Mapped[str] = mapped_column(Text, nullable=False)
    grade: Mapped[str] = mapped_column(Text, nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    points_class_balance: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class Student(Base):
    __tablename__ = "students"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    school_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False)
    class_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("classes.id", ondelete="RESTRICT"), nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    pin_hash: Mapped[str | None] = mapped_column(Text)
    is_activated: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    points_student_balance: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status: Mapped[StudentStatus] = mapped_column(String(16), nullable=False, default=StudentStatus.ACTIVE)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (CheckConstraint("points_student_balance >= 0", name="students_points_student_balance_check"),)


class Admin(Base):
    __tablename__ = "admins"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    school_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    email: Mapped[str] = mapped_column(Text, nullable=False)
    role: Mapped[AdminRole] = mapped_column(String(24), nullable=False)
    password_hash: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (UniqueConstraint("email", name="admins_email_key"),)


class Machine(Base):
    __tablename__ = "machines"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    school_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[MachineStatus] = mapped_column(String(32), nullable=False)
    firmware_version: Mapped[str | None] = mapped_column(Text)
    last_seen: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    bin_full: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    camera_ok: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    net_ok: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    api_key_hash: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class Reward(Base):
    __tablename__ = "rewards"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    school_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    cost_points: Mapped[int] = mapped_column(Integer, nullable=False)
    category: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    status: Mapped[RewardStatus] = mapped_column(String(16), nullable=False, default=RewardStatus.AVAILABLE)
    stock_qty: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class Deposit(Base):
    __tablename__ = "deposits"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    event_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, unique=True)
    school_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False)
    machine_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("machines.id", ondelete="RESTRICT"), nullable=False)
    class_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("classes.id", ondelete="RESTRICT"), nullable=False)
    student_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("students.id", ondelete="RESTRICT"))
    is_valid: Mapped[bool] = mapped_column(Boolean, nullable=False)
    detected_type: Mapped[str | None] = mapped_column(Text)
    size: Mapped[DepositSize] = mapped_column(String(16), nullable=False)
    points_awarded_student: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    points_awarded_class: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (
        CheckConstraint("points_awarded_student >= 0", name="deposits_points_awarded_student_check"),
        CheckConstraint("points_awarded_class >= 0", name="deposits_points_awarded_class_check"),
    )


class Redemption(Base):
    __tablename__ = "redemptions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False)
    student_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("students.id", ondelete="RESTRICT"), nullable=False)
    reward_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("rewards.id", ondelete="RESTRICT"), nullable=False)
    code: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    status: Mapped[RedemptionStatus] = mapped_column(String(16), nullable=False, default=RedemptionStatus.PENDING)
    request_channel: Mapped[str] = mapped_column(String(16), nullable=False, default="TOTEM")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    delivered_by_admin_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("admins.id", ondelete="RESTRICT"))


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False)
    actor_type: Mapped[ActorType] = mapped_column(String(16), nullable=False)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    action: Mapped[str] = mapped_column(Text, nullable=False)
    audit_metadata: Mapped[dict | None] = mapped_column("metadata", JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
