"""Échéancier des ventes avec dette : table sale_installments.

Les ventes non soldées existantes reçoivent une échéance unique (leur date d'échéance, le reste à payer).

Revision ID: b7e3c5a1f902
Revises: 9d4b2f61a8c3
Create Date: 2026-10-03 03:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b7e3c5a1f902'
down_revision: Union[str, Sequence[str], None] = '9d4b2f61a8c3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('sale_installments',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('sale_id', sa.Integer(), nullable=False),
    sa.Column('due_date', sa.Date(), nullable=False),
    sa.Column('amount', sa.Numeric(precision=14, scale=2), nullable=False),
    sa.CheckConstraint('amount > 0', name=op.f('ck_sale_installments_amount_positive')),
    sa.ForeignKeyConstraint(['sale_id'], ['sales.id'], name=op.f('fk_sale_installments_sale_id_sales'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_sale_installments')),
    sa.UniqueConstraint('sale_id', 'due_date', name=op.f('uq_sale_installments_sale_id_due_date'))
    )
    op.create_index(op.f('ix_sale_installments_sale_id'), 'sale_installments', ['sale_id'], unique=False)
    op.execute(
        """
        INSERT INTO sale_installments (sale_id, due_date, amount)
        SELECT sales.id, sales.payment_due_date, sales.total - COALESCE(SUM(payments.amount), 0)
        FROM sales LEFT JOIN payments ON payments.sale_id = sales.id
        WHERE sales.status = 'COMPLETED' AND sales.payment_due_date IS NOT NULL
        GROUP BY sales.id
        HAVING sales.total - COALESCE(SUM(payments.amount), 0) > 0
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_sale_installments_sale_id'), table_name='sale_installments')
    op.drop_table('sale_installments')
