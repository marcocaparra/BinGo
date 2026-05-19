from uuid import UUID

from sqlalchemy.orm import Session

from domain.audit.service import register_audit
from infra.crypto.security import verify_secret
from infra.repositories.machine_repository import MachineRepository
from shared.constants.enums import ActorType, MachineStatus
from shared.errors.exceptions import ForbiddenError, NotFoundError, UnauthorizedError
from shared.utils.time import utcnow


def authenticate_machine(session: Session, machine_id: UUID, api_key: str):
    machine = MachineRepository(session).get_by_id(machine_id)
    if machine is None:
        raise NotFoundError("Máquina não encontrada.")
    if not machine.api_key_hash or not verify_secret(api_key, machine.api_key_hash):
        raise UnauthorizedError("Credencial técnica inválida.")
    return machine


def heartbeat(session: Session, machine_id: UUID, *, firmware_version: str | None, bin_full: bool, camera_ok: bool, net_ok: bool):
    machine = MachineRepository(session).get_by_id(machine_id)
    if machine is None:
        raise NotFoundError("Máquina não encontrada.")
    try:
        machine.last_seen = utcnow()
        machine.firmware_version = firmware_version or machine.firmware_version
        machine.bin_full = bin_full
        machine.camera_ok = camera_ok
        machine.net_ok = net_ok
        if not camera_ok or not net_ok:
            machine.status = MachineStatus.MAINTENANCE
        register_audit(
            session,
            school_id=machine.school_id,
            actor_type=ActorType.MACHINE,
            actor_id=machine.id,
            action="MACHINE_HEARTBEAT",
        )
        session.commit()
    except Exception:
        session.rollback()
        raise
    return machine


def update_machine_status(session: Session, machine_id: UUID, *, status, bin_full, camera_ok, net_ok):
    machine = MachineRepository(session).get_by_id(machine_id)
    if machine is None:
        raise NotFoundError("Máquina não encontrada.")
    try:
        machine.status = status
        if bin_full is not None:
            machine.bin_full = bin_full
        if camera_ok is not None:
            machine.camera_ok = camera_ok
        if net_ok is not None:
            machine.net_ok = net_ok
        machine.last_seen = utcnow()
        session.commit()
    except Exception:
        session.rollback()
        raise
    return machine
