"""Add default timestamp to discards, keep nullable

Revision ID: b5aefe9cf4b2
Revises: 2223e61fce0c
Create Date: 2025-09-03 22:19:20.398949

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b5aefe9cf4b2'
down_revision: Union[str, Sequence[str], None] = '2223e61fce0c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column(
        'discards',
        'timestamp',
        existing_type=sa.DateTime(timezone=True),
        server_default=sa.text('CURRENT_TIMESTAMP'), # Adiciona o DEFAULT CURRENT_TIMESTAMP
        existing_nullable=True, # Mantém como era antes, True
        nullable=True # MUITO IMPORTANTE: Mantenha como NULLABLE TRUE por enquanto
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column(
        'discards',
        'timestamp',
        existing_type=sa.DateTime(timezone=True),
        server_default=None, # Remove o DEFAULT
        existing_nullable=True,
        nullable=True # Mantenha como NULLABLE TRUE
    )
