"""Caisses : ouverture et fermeture automatiques (opened_by facultatif, indicateurs automatiques).

Revision ID: 5c1e7a9d2b40
Revises: 8732f6c28354
Create Date: 2026-10-03 00:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '5c1e7a9d2b40'
down_revision: Union[str, Sequence[str], None] = '8732f6c28354'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column('cash_registers', 'opened_by', existing_type=sa.Integer(), nullable=True)
    op.add_column(
        'cash_registers',
        sa.Column('opened_automatically', sa.Boolean(), server_default=sa.false(), nullable=False),
    )
    op.add_column(
        'cash_registers',
        sa.Column('closed_automatically', sa.Boolean(), server_default=sa.false(), nullable=False),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('cash_registers', 'closed_automatically')
    op.drop_column('cash_registers', 'opened_automatically')
    # Les caisses ouvertes automatiquement n'ont pas d'utilisateur : on les attribue au premier ADMIN.
    op.execute(
        """
        UPDATE cash_registers SET opened_by = (
            SELECT users.id FROM users JOIN roles ON roles.id = users.role_id
            WHERE roles.name = 'ADMIN' ORDER BY users.id LIMIT 1
        )
        WHERE opened_by IS NULL
        """
    )
    op.alter_column('cash_registers', 'opened_by', existing_type=sa.Integer(), nullable=False)
