from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.dependencies import get_session, require_edge_headers
from app.api.schemas.totem import (
    TotemClassRankingItem,
    TotemClassResponse,
    TotemContextResponse,
    TotemDepositResponse,
    TotemMachineResponse,
    TotemRankingsResponse,
    TotemSchoolResponse,
    TotemStudentRankingItem,
    TotemStudentLoginRequest,
    TotemStudentLoginResponse,
    TotemStudentResponse,
    TotemStudentStatsResponse,
    TotemStudentSummaryResponse,
)
from domain.auth.service import login_student
from domain.machines.service import authenticate_machine
from domain.totem.service import get_context, get_rankings, get_student_identity, get_student_summary

router = APIRouter()


def _authenticate_totem_machine(session: Session, edge_headers: tuple):
    machine_id, api_key = edge_headers
    return authenticate_machine(session, machine_id, api_key)


def _student_response(student, class_name: str) -> TotemStudentResponse:
    return TotemStudentResponse(
        id=student.id,
        name=student.name,
        class_id=student.class_id,
        class_name=class_name,
        points_student_balance=student.points_student_balance,
        status=student.status,
    )


@router.get("/context", response_model=TotemContextResponse)
def read_totem_context(
    edge_headers: tuple = Depends(require_edge_headers),
    session: Session = Depends(get_session),
) -> TotemContextResponse:
    machine = _authenticate_totem_machine(session, edge_headers)
    context = get_context(session, machine)
    return TotemContextResponse(
        school=TotemSchoolResponse(id=context["school"].id, name=context["school"].name),
        machine=TotemMachineResponse(id=machine.id, name=machine.name, status=machine.status),
        classes=[
            TotemClassResponse(
                id=item.id,
                name=item.name,
                segment=item.segment,
                grade=item.grade,
                points_class_balance=item.points_class_balance,
            )
            for item in context["classes"]
        ],
        students=[_student_response(student, class_name) for student, class_name in context["students"]],
    )


@router.post("/students/login", response_model=TotemStudentLoginResponse)
def login_totem_student(
    payload: TotemStudentLoginRequest,
    edge_headers: tuple = Depends(require_edge_headers),
    session: Session = Depends(get_session),
) -> TotemStudentLoginResponse:
    machine = _authenticate_totem_machine(session, edge_headers)
    token = login_student(session, machine.school_id, payload.class_id, payload.student_id, payload.pin)
    student, class_name = get_student_identity(session, machine, payload.student_id)
    return TotemStudentLoginResponse(
        access_token=token,
        student=_student_response(student, class_name),
    )


@router.get("/students/{student_id}/summary", response_model=TotemStudentSummaryResponse)
def read_student_summary(
    student_id: UUID,
    edge_headers: tuple = Depends(require_edge_headers),
    session: Session = Depends(get_session),
) -> TotemStudentSummaryResponse:
    machine = _authenticate_totem_machine(session, edge_headers)
    summary = get_student_summary(session, machine, student_id)
    return TotemStudentSummaryResponse(
        student=_student_response(summary["student"], summary["class_name"]),
        stats=TotemStudentStatsResponse(
            valid_deposits_count=summary["valid_deposits_count"],
            invalid_deposits_count=summary["invalid_deposits_count"],
            total_bins_generated=summary["total_bins_generated"],
        ),
        recent_deposits=[
            TotemDepositResponse(
                id=item.id,
                event_id=item.event_id,
                detected_type=item.detected_type,
                waste_category_code=item.waste_category.code if item.waste_category is not None else None,
                category_source=item.category_source,
                bonus_rate_applied=item.bonus_rate_applied,
                bonus_bincoins_awarded=item.bonus_bincoins_awarded,
                is_valid=item.is_valid,
                points_awarded_student=item.points_awarded_student,
                points_awarded_class=item.points_awarded_class,
                created_at=item.created_at,
            )
            for item in summary["recent_deposits"]
        ],
    )


@router.get("/rankings", response_model=TotemRankingsResponse)
def read_rankings(
    edge_headers: tuple = Depends(require_edge_headers),
    session: Session = Depends(get_session),
) -> TotemRankingsResponse:
    machine = _authenticate_totem_machine(session, edge_headers)
    rankings = get_rankings(session, machine)
    return TotemRankingsResponse(
        students=[
            TotemStudentRankingItem(
                id=student.id,
                name=student.name,
                class_name=class_name,
                points_student_balance=student.points_student_balance,
            )
            for student, class_name in rankings["students"]
        ],
        classes=[
            TotemClassRankingItem(
                id=item.id,
                name=item.name,
                points_class_balance=item.points_class_balance,
            )
            for item in rankings["classes"]
        ],
    )
