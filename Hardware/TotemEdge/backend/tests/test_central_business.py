import json
from uuid import uuid4

import httpx2 as httpx
import pytest

from app.central_contracts import DepositPayload
from app.clients.supabase import CentralError, SupabaseEdgeClient
from test_sessions import CLASS, STUDENT, context_body, pin_body, receipt


@pytest.mark.anyio
async def test_business_headers_and_exact_seven_fields(configured_environment):
    payload = DepositPayload(
        event_id=uuid4(),
        class_id=CLASS,
        student_id=None,
        is_valid=True,
        detected_type="unidentified",
        waste_category_code="UNKNOWN",
        category_source="UNIDENTIFIED",
    )
    requests = []

    def upstream(request):
        requests.append(request)
        assert (
            request.headers["X-Machine-Id"]
            == configured_environment["BINGO_MACHINE_ID"]
        )
        assert (
            request.headers["X-Api-Key"]
            == configured_environment["BINGO_MACHINE_API_KEY"]
        )
        assert (
            "Authorization" not in request.headers and "apikey" not in request.headers
        )
        assert not request.url.query
        assert set(request.extensions["timeout"].values()) == {2.5}
        if request.url.path.endswith("totem-context-v1"):
            assert request.method == "GET"
            return httpx.Response(200, json=context_body())
        if request.url.path.endswith("totem-student-pin-v1"):
            assert json.loads(request.content) == {
                "class_id": str(CLASS),
                "student_id": str(STUDENT),
                "pin": "0012",
            }
            return httpx.Response(200, json=pin_body())
        assert json.loads(request.content) == payload.model_dump(mode="json")
        return httpx.Response(201, json=receipt(payload.model_dump(mode="json")))

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        central = SupabaseEdgeClient(http)
        assert "never-forward" not in (await central.context()).model_dump_json()
        assert (
            "never-forward"
            not in (await central.verify_pin(CLASS, STUDENT, "0012")).model_dump_json()
        )
        assert (await central.register(payload)).event_id == payload.event_id
    assert len(requests) == 3


@pytest.mark.anyio
@pytest.mark.parametrize(
    "case",
    [
        "timeout",
        "connection",
        "html",
        "invalid_json",
        "redirect",
        "401",
        "404",
        "409",
        "422",
        "500",
        "wrong_event",
        "negative_points",
        "boolean_points",
    ],
)
async def test_deposit_failures_never_confirm(configured_environment, case):
    payload = DepositPayload(
        event_id=uuid4(),
        class_id=CLASS,
        student_id=None,
        is_valid=True,
        detected_type="cable",
        waste_category_code="CABLE_WIRE",
        category_source="AI_CONFIRMED",
    )

    def upstream(request):
        if case == "timeout":
            raise httpx.ReadTimeout("private-test-fixture", request=request)
        if case == "connection":
            raise httpx.ConnectError("private-test-fixture", request=request)
        if case == "html":
            return httpx.Response(200, text="private-test-fixture")
        if case == "invalid_json":
            return httpx.Response(
                201, text="{bad", headers={"Content-Type": "application/json"}
            )
        if case == "redirect":
            return httpx.Response(
                307, json={}, headers={"Location": "https://foreign.invalid"}
            )
        if case.isdigit():
            return httpx.Response(
                int(case), json={"error": {"message": "private-test-fixture"}}
            )
        data = receipt(payload.model_dump(mode="json"))
        if case == "wrong_event":
            data["event_id"] = str(uuid4())
        if case == "negative_points":
            data["points_awarded_class"] = -1
        if case == "boolean_points":
            data["points_awarded_class"] = True
        return httpx.Response(201, json=data)

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(upstream), follow_redirects=False
    ) as http:
        with pytest.raises(CentralError) as error:
            await SupabaseEdgeClient(http).register(payload)
        assert "private-test-fixture" not in str(error.value)


@pytest.mark.anyio
@pytest.mark.parametrize(
    "mutation",
    ["machine", "pin_student", "pin_class", "pin_boolean", "context_duplicate"],
)
async def test_wrong_identity_or_context_is_not_accepted(
    configured_environment, mutation
):
    data = (
        context_body() if mutation in {"machine", "context_duplicate"} else pin_body()
    )
    if mutation == "machine":
        data["machine"]["id"] = str(uuid4())
    if mutation == "context_duplicate":
        data["classes"] *= 2
    if mutation == "pin_student":
        data["student"]["id"] = str(uuid4())
    if mutation == "pin_class":
        data["student"]["class_id"] = str(uuid4())
    if mutation == "pin_boolean":
        data["confirmed"] = 1
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: httpx.Response(200, json=data))
    ) as http:
        central = SupabaseEdgeClient(http)
        with pytest.raises(CentralError):
            if mutation in {"machine", "context_duplicate"}:
                await central.context()
            else:
                await central.verify_pin(CLASS, STUDENT, "0012")
