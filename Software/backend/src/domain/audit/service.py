from uuid import UUID

from sqlalchemy.orm import Session

from infra.db.models import AuditLog
from shared.constants.enums import ActorType


def register_audit(
    session: Session,
    *,
    school_id: UUID,
    actor_type: ActorType,
    actor_id: UUID | None,
    action: str,
    metadata: dict | None = None,
) -> None:
    session.add(
        AuditLog(
            school_id=school_id,
            actor_type=actor_type,
            actor_id=actor_id,
            action=action,
            audit_metadata=metadata,
        )
    )

