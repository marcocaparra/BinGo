from sqlalchemy import select
from sqlalchemy.orm import Session

from infra.db.models import WasteCategory
from shared.constants.enums import WasteCategoryCode


class WasteCategoryRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def get_active_by_code(self, code: WasteCategoryCode) -> WasteCategory | None:
        return self.session.scalar(
            select(WasteCategory).where(
                WasteCategory.code == code.value,
                WasteCategory.is_active.is_(True),
            )
        )
