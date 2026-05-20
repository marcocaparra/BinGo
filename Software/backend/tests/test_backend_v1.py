import uuid

from fastapi.testclient import TestClient

from app.main import app
from infra.db.models import AuditLog, Redemption, Reward, Student
from shared.constants.enums import RedemptionStatus, RewardStatus, StudentStatus


def student_login(client, ids, pin="1234"):
    return client.post(
        "/v1/auth/students/login",
        json={
            "school_id": ids["school_id"],
            "class_id": ids["class_id"],
            "student_id": ids["student_id"],
            "pin": pin,
        },
    )


def activate_student(client, ids, pin="1234"):
    return client.post(
        "/v1/auth/students/activate",
        json={
            "school_id": ids["school_id"],
            "class_id": ids["class_id"],
            "student_id": ids["student_id"],
            "pin": pin,
        },
    )


def admin_login(client):
    return client.post("/v1/auth/admins/login", json={"email": "admin@bingo.local", "password": "admin-123"})


def edge_headers(ids):
    return {"X-Machine-Id": ids["machine_id"], "X-Api-Key": "edge-secret"}


def test_cors_preflight_allows_totem_simulator_origin():
    client = TestClient(app)
    response = client.options(
        "/v1/totem/context",
        headers={
            "Origin": "http://localhost:8001",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "X-Machine-Id,X-Api-Key",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:8001"


def test_cors_headers_are_present_on_unexpected_errors():
    client = TestClient(app, raise_server_exceptions=False)
    response = client.get(
        "/v1/totem/context",
        headers={
            "Origin": "http://localhost:8001",
            "X-Machine-Id": "40000000-0000-4000-8000-000000000001",
            "X-Api-Key": "edge-demo-key",
        },
    )
    assert response.status_code == 500
    assert response.headers["access-control-allow-origin"] == "http://localhost:8001"


def test_activate_student_success(client, seeded_ids, session_factory):
    response = activate_student(client, seeded_ids)
    assert response.status_code == 201
    session = session_factory()
    student = session.get(Student, uuid.UUID(seeded_ids["student_id"]))
    assert student.is_activated is True
    assert student.pin_hash is not None
    assert session.query(AuditLog).count() == 1
    session.close()


def test_activate_student_inactive_fails(client, seeded_ids, session_factory):
    session = session_factory()
    student = session.get(Student, uuid.UUID(seeded_ids["student_id"]))
    student.status = StudentStatus.INACTIVE
    session.commit()
    session.close()
    response = activate_student(client, seeded_ids)
    assert response.status_code == 403


def test_login_student_success_and_wrong_pin(client, seeded_ids):
    activate_student(client, seeded_ids)
    success = student_login(client, seeded_ids)
    assert success.status_code == 200
    failure = student_login(client, seeded_ids, pin="9999")
    assert failure.status_code == 401


def test_valid_deposit_logged_in(client, seeded_ids, session_factory):
    response = client.post(
        "/v1/deposits",
        headers=edge_headers(seeded_ids),
        json={
            "event_id": str(uuid.uuid4()),
            "school_id": seeded_ids["school_id"],
            "machine_id": seeded_ids["machine_id"],
            "class_id": seeded_ids["class_id"],
            "student_id": seeded_ids["student_id"],
            "is_valid": True,
            "detected_type": "mouse",
            "size": "MEDIUM",
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["points_awarded_student"] == 30
    assert body["points_awarded_class"] == 30
    session = session_factory()
    student = session.get(Student, uuid.UUID(seeded_ids["student_id"]))
    assert student.points_student_balance == 150
    session.close()


def test_valid_deposit_without_login_and_invalid_deposit(client, seeded_ids, session_factory):
    no_login = client.post(
        "/v1/deposits",
        headers=edge_headers(seeded_ids),
        json={
            "event_id": str(uuid.uuid4()),
            "school_id": seeded_ids["school_id"],
            "machine_id": seeded_ids["machine_id"],
            "class_id": seeded_ids["class_id"],
            "student_id": None,
            "is_valid": True,
            "detected_type": "mouse",
            "size": "LARGE",
        },
    )
    invalid = client.post(
        "/v1/deposits",
        headers=edge_headers(seeded_ids),
        json={
            "event_id": str(uuid.uuid4()),
            "school_id": seeded_ids["school_id"],
            "machine_id": seeded_ids["machine_id"],
            "class_id": seeded_ids["class_id"],
            "student_id": seeded_ids["student_id"],
            "is_valid": False,
            "detected_type": "lixo",
            "size": "SMALL",
        },
    )
    assert no_login.json()["points_awarded_student"] == 0
    assert no_login.json()["points_awarded_class"] == 50
    assert invalid.json()["points_awarded_student"] == 0
    assert invalid.json()["points_awarded_class"] == 0


def test_duplicate_event_id_does_not_duplicate_points(client, seeded_ids, session_factory):
    event_id = str(uuid.uuid4())
    payload = {
        "event_id": event_id,
        "school_id": seeded_ids["school_id"],
        "machine_id": seeded_ids["machine_id"],
        "class_id": seeded_ids["class_id"],
        "student_id": seeded_ids["student_id"],
        "is_valid": True,
        "detected_type": "mouse",
        "size": "MEDIUM",
    }
    first = client.post("/v1/deposits/sync", headers=edge_headers(seeded_ids), json=payload)
    second = client.post("/v1/deposits/sync", headers=edge_headers(seeded_ids), json=payload)
    assert first.json()["id"] == second.json()["id"]
    session = session_factory()
    student = session.get(Student, uuid.UUID(seeded_ids["student_id"]))
    assert student.points_student_balance == 150
    session.close()


def test_deposit_without_school_or_machine_in_body_is_idempotent(client, seeded_ids, session_factory):
    event_id = str(uuid.uuid4())
    payload = {
        "event_id": event_id,
        "class_id": seeded_ids["class_id"],
        "student_id": seeded_ids["student_id"],
        "is_valid": True,
        "detected_type": "mouse",
        "size": "MEDIUM",
    }
    first = client.post("/v1/deposits", headers=edge_headers(seeded_ids), json=payload)
    second = client.post("/v1/deposits", headers=edge_headers(seeded_ids), json=payload)
    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
    session = session_factory()
    student = session.get(Student, uuid.UUID(seeded_ids["student_id"]))
    assert student.points_student_balance == 150
    session.close()


def test_small_antifarm_keeps_class_points(client, seeded_ids):
    first = client.post(
        "/v1/deposits",
        headers=edge_headers(seeded_ids),
        json={
            "event_id": str(uuid.uuid4()),
            "school_id": seeded_ids["school_id"],
            "machine_id": seeded_ids["machine_id"],
            "class_id": seeded_ids["class_id"],
            "student_id": seeded_ids["student_id"],
            "is_valid": True,
            "detected_type": "pilha",
            "size": "SMALL",
        },
    )
    second = client.post(
        "/v1/deposits",
        headers=edge_headers(seeded_ids),
        json={
            "event_id": str(uuid.uuid4()),
            "school_id": seeded_ids["school_id"],
            "machine_id": seeded_ids["machine_id"],
            "class_id": seeded_ids["class_id"],
            "student_id": seeded_ids["student_id"],
            "is_valid": True,
            "detected_type": "pilha",
            "size": "SMALL",
        },
    )
    assert first.json()["points_awarded_student"] == 10
    assert second.json()["points_awarded_student"] == 0
    assert second.json()["points_awarded_class"] == 10


def test_redemption_success_and_failures(client, seeded_ids, session_factory):
    activate_student(client, seeded_ids)
    token = student_login(client, seeded_ids).json()["access_token"]
    success = client.post("/v1/redemptions", headers={"Authorization": f"Bearer {token}"}, json={"reward_id": seeded_ids["reward_id"]})
    assert success.status_code == 200

    session = session_factory()
    reward = session.get(Reward, uuid.UUID(seeded_ids["reward_id"]))
    reward.status = RewardStatus.DISABLED
    session.commit()
    session.close()
    inactive = client.post("/v1/redemptions", headers={"Authorization": f"Bearer {token}"}, json={"reward_id": seeded_ids["reward_id"]})
    assert inactive.status_code == 403


def test_redemption_fails_for_insufficient_balance_and_pending_limit(client, seeded_ids, session_factory):
    activate_student(client, seeded_ids)
    token = student_login(client, seeded_ids).json()["access_token"]

    session = session_factory()
    student = session.get(Student, uuid.UUID(seeded_ids["student_id"]))
    student.points_student_balance = 20
    session.commit()
    session.close()
    low_balance = client.post("/v1/redemptions", headers={"Authorization": f"Bearer {token}"}, json={"reward_id": seeded_ids["reward_id"]})
    assert low_balance.status_code == 403

    session = session_factory()
    student = session.get(Student, uuid.UUID(seeded_ids["student_id"]))
    student.points_student_balance = 120
    session.commit()
    session.close()
    first = client.post("/v1/redemptions", headers={"Authorization": f"Bearer {token}"}, json={"reward_id": seeded_ids["reward_id"]})
    assert first.status_code == 200
    second = client.post("/v1/redemptions", headers={"Authorization": f"Bearer {token}"}, json={"reward_id": seeded_ids["reward_id"]})
    assert second.status_code == 403


def test_admin_can_deliver_and_expired_or_duplicate_delivery_fails(client, seeded_ids, session_factory):
    activate_student(client, seeded_ids)
    student_token = student_login(client, seeded_ids).json()["access_token"]
    admin_token = admin_login(client).json()["access_token"]
    created = client.post("/v1/redemptions", headers={"Authorization": f"Bearer {student_token}"}, json={"reward_id": seeded_ids["reward_id"]})
    redemption_id = created.json()["id"]

    delivered = client.post(f"/v1/redemptions/{redemption_id}/deliver", headers={"Authorization": f"Bearer {admin_token}"})
    assert delivered.status_code == 200
    again = client.post(f"/v1/redemptions/{redemption_id}/deliver", headers={"Authorization": f"Bearer {admin_token}"})
    assert again.status_code == 403

    session = session_factory()
    expired = Redemption(
        school_id=uuid.UUID(seeded_ids["school_id"]),
        student_id=uuid.UUID(seeded_ids["student_id"]),
        reward_id=uuid.UUID(seeded_ids["reward_id"]),
        code="EXPIRED1",
        status=RedemptionStatus.PENDING,
        expires_at=__import__("datetime").datetime(2000, 1, 1),
    )
    session.add(expired)
    session.commit()
    expired_id = expired.id
    session.close()
    expired_response = client.post(f"/v1/redemptions/{expired_id}/deliver", headers={"Authorization": f"Bearer {admin_token}"})
    assert expired_response.status_code == 403


def test_sensitive_actions_generate_audit_logs(client, seeded_ids, session_factory):
    activate_student(client, seeded_ids)
    student_token = student_login(client, seeded_ids).json()["access_token"]
    admin_token = admin_login(client).json()["access_token"]
    created = client.post("/v1/redemptions", headers={"Authorization": f"Bearer {student_token}"}, json={"reward_id": seeded_ids["reward_id"]})
    client.post(f"/v1/redemptions/{created.json()['id']}/deliver", headers={"Authorization": f"Bearer {admin_token}"})
    session = session_factory()
    assert session.query(AuditLog).count() >= 3
    session.close()


def test_totem_context_with_valid_machine_auth(client, seeded_ids):
    response = client.get("/v1/totem/context", headers=edge_headers(seeded_ids))
    assert response.status_code == 200
    body = response.json()
    assert body["school"]["id"] == seeded_ids["school_id"]
    assert body["machine"]["id"] == seeded_ids["machine_id"]
    assert body["classes"][0]["id"] == seeded_ids["class_id"]
    assert body["students"][0]["id"] == seeded_ids["student_id"]
    assert "pin_hash" not in str(body)
    assert "password_hash" not in str(body)
    assert "api_key_hash" not in str(body)


def test_totem_context_with_invalid_machine_auth_fails(client, seeded_ids):
    headers = edge_headers(seeded_ids)
    headers["X-Api-Key"] = "wrong-key"
    response = client.get("/v1/totem/context", headers=headers)
    assert response.status_code == 401


def test_totem_context_without_machine_headers_fails_with_unauthorized(client):
    response = client.get("/v1/totem/context")
    assert response.status_code == 401
    assert response.json()["detail"] == "Credenciais técnicas ausentes."


def test_totem_rankings(client, seeded_ids):
    response = client.get("/v1/totem/rankings", headers=edge_headers(seeded_ids))
    assert response.status_code == 200
    body = response.json()
    assert body["students"][0]["name"] == "Joao Teste"
    assert body["classes"][0]["name"] == "7A"


def test_totem_student_summary(client, seeded_ids):
    valid_payload = {
        "event_id": str(uuid.uuid4()),
        "class_id": seeded_ids["class_id"],
        "student_id": seeded_ids["student_id"],
        "is_valid": True,
        "detected_type": "mouse",
        "size": "MEDIUM",
    }
    invalid_payload = {
        "event_id": str(uuid.uuid4()),
        "class_id": seeded_ids["class_id"],
        "student_id": seeded_ids["student_id"],
        "is_valid": False,
        "detected_type": "objeto inválido",
        "size": "SMALL",
    }
    client.post("/v1/deposits", headers=edge_headers(seeded_ids), json=valid_payload)
    client.post("/v1/deposits", headers=edge_headers(seeded_ids), json=invalid_payload)

    response = client.get(f"/v1/totem/students/{seeded_ids['student_id']}/summary", headers=edge_headers(seeded_ids))
    assert response.status_code == 200
    body = response.json()
    assert body["student"]["id"] == seeded_ids["student_id"]
    assert body["student"]["class_name"] == "7A"
    assert body["stats"]["valid_deposits_count"] == 1
    assert body["stats"]["invalid_deposits_count"] == 1
    assert body["stats"]["total_bins_generated"] == 30
    assert len(body["recent_deposits"]) == 2
