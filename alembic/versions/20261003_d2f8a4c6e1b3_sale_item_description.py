"""Description de chaque article vendu (taille, couleur...) : sale_items.description.

Revision ID: d2f8a4c6e1b3
Revises: b7e3c5a1f902
Create Date: 2026-10-03 03:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd2f8a4c6e1b3'
down_revision: Union[str, Sequence[str], None] = 'b7e3c5a1f902'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('sale_items', sa.Column('description', sa.String(length=255), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('sale_items', 'description')
