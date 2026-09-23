import uuid
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.dependencies import get_session
from app.main import app
from infra.crypto.security import hash_secret
from infra.db.base import Base
from infra.db.models import Admin, ClassRoom, Machine, Reward, School, SchoolSetting, Student, WasteCategory
from shared.constants.enums import AdminRole, MachineStatus, RewardStatus, StudentStatus


@pytest.fixture()
def session_factory():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        future=True,
    )
    TestingSessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False)
    Base.metadata.create_all(bind=engine)
    try:
        yield TestingSessionLocal
    finally:
        Base.metadata.drop_all(bind=engine)
        engine.dispose()


@pytest.fixture()
def client(session_factory):
    def override_get_session():
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_session] = override_get_session
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture()
def seeded_ids(session_factory):
    school_id = uuid.UUID("11111111-1111-1111-1111-111111111111")
    class_id = uuid.UUID("22222222-2222-2222-2222-222222222221")
    student_id = uuid.UUID("33333333-3333-3333-3333-333333333331")
    admin_id = uuid.UUID("44444444-4444-4444-4444-444444444441")
    machine_id = uuid.UUID("55555555-5555-5555-5555-555555555551")
    reward_id = uuid.UUID("66666666-6666-6666-6666-666666666661")
    category_ids = {
        "BATTERY": uuid.UUID("77777777-7777-7777-7777-777777777771"),
        "MOBILE_DEVICE": uuid.UUID("77777777-7777-7777-7777-777777777772"),
        "CABLE_WIRE": uuid.UUID("77777777-7777-7777-7777-777777777773"),
        "PERIPHERAL": uuid.UUID("77777777-7777-7777-7777-777777777774"),
        "OTHER_EWASTE": uuid.UUID("77777777-7777-7777-7777-777777777775"),
        "UNKNOWN": uuid.UUID("77777777-7777-7777-7777-777777777776"),
    }

    session: Session = session_factory()
    session.add(School(id=school_id, name="Escola Piloto"))
    session.add(
        SchoolSetting(
            school_id=school_id,
            deposit_bincoins_base=800,
            deposit_class_xp_base=1900,
            class_weekly_xp_goal=10000,
            redemption_expiration_hours=72,
            redemption_daily_limit=2,
            redemption_max_pending=1,
        )
    )
    session.add_all(
        [
            WasteCategory(id=category_ids["BATTERY"], code="BATTERY", display_name="Pilha ou bateria", bonus_rate=Decimal("1.0000")),
            WasteCategory(id=category_ids["MOBILE_DEVICE"], code="MOBILE_DEVICE", display_name="Celular ou tablet", bonus_rate=Decimal("0.5000")),
            WasteCategory(id=category_ids["CABLE_WIRE"], code="CABLE_WIRE", display_name="Cabo ou fio", bonus_rate=Decimal("0.2500")),
            WasteCategory(id=category_ids["PERIPHERAL"], code="PERIPHERAL", display_name="Periférico", bonus_rate=Decimal("0")),
            WasteCategory(id=category_ids["OTHER_EWASTE"], code="OTHER_EWASTE", display_name="Outro lixo eletrônico", bonus_rate=Decimal("0")),
            WasteCategory(id=category_ids["UNKNOWN"], code="UNKNOWN", display_name="Lixo eletrônico não identificado", bonus_rate=Decimal("0")),
        ]
    )
    session.add(ClassRoom(id=class_id, school_id=school_id, segment="FUNDAMENTAL_2", grade="7", name="7A", points_class_balance=0))
    session.add(
        Student(
            id=student_id,
            school_id=school_id,
            class_id=class_id,
            name="Joao Teste",
            status=StudentStatus.ACTIVE,
            points_student_balance=12000,
            is_activated=False,
        )
    )
    session.add(
        Admin(
            id=admin_id,
            school_id=school_id,
            name="Admin",
            email="admin@bingo.local",
            role=AdminRole.ADMIN,
            password_hash=hash_secret("admin-123"),
        )
    )
    session.add(
        Machine(
            id=machine_id,
            school_id=school_id,
            name="Totem",
            status=MachineStatus.ONLINE,
            firmware_version="v1",
            api_key_hash=hash_secret("edge-secret"),
        )
    )
    session.add(
        Reward(
            id=reward_id,
            school_id=school_id,
            name="Agua",
            description="Recompensa",
            cost_points=3000,
            category="CANTINA",
            is_active=True,
            status=RewardStatus.AVAILABLE,
            stock_qty=10,
        )
    )
    session.commit()
    session.close()
    return {
        "school_id": str(school_id),
        "class_id": str(class_id),
        "student_id": str(student_id),
        "admin_id": str(admin_id),
        "machine_id": str(machine_id),
        "reward_id": str(reward_id),
        "category_ids": {code: str(category_id) for code, category_id in category_ids.items()},
    }
