"""Suppression de la caisse : tables cash_registers et cash_transactions, permissions cash.*.

Revision ID: 9d4b2f61a8c3
Revises: 5c1e7a9d2b40
Create Date: 2026-10-03 02:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '9d4b2f61a8c3'
down_revision: Union[str, Sequence[str], None] = '5c1e7a9d2b40'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # role_permissions suit la suppression (ON DELETE CASCADE).
    op.execute("DELETE FROM permissions WHERE name LIKE 'cash.%'")
    op.drop_index(op.f('ix_cash_transactions_cash_register_id'), table_name='cash_transactions')
    op.drop_table('cash_transactions')
    op.drop_index('uq_cash_registers_one_open_per_store', table_name='cash_registers', postgresql_where=sa.text("status = 'OPEN'"))
    op.drop_index(op.f('ix_cash_registers_store_id'), table_name='cash_registers')
    op.drop_index(op.f('ix_cash_registers_status'), table_name='cash_registers')
    op.drop_table('cash_registers')


def downgrade() -> None:
    """Downgrade schema.

    Recrée les tables vides (état après 5c1e7a9d2b40). Les permissions cash.* sont recréées
    par `python -m app.seed` de la version précédente du code.
    """
    op.create_table('cash_registers',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('store_id', sa.Integer(), nullable=False),
    sa.Column('opened_by', sa.Integer(), nullable=True),
    sa.Column('closed_by', sa.Integer(), nullable=True),
    sa.Column('opening_amount', sa.Numeric(precision=14, scale=2), nullable=False),
    sa.Column('closing_amount', sa.Numeric(precision=14, scale=2), nullable=True),
    sa.Column('expected_amount', sa.Numeric(precision=14, scale=2), nullable=False),
    sa.Column('difference', sa.Numeric(precision=14, scale=2), nullable=True),
    sa.Column('status', sa.Enum('OPEN', 'CLOSED', name='cashregisterstatus', native_enum=False, length=30), nullable=False),
    sa.Column('opened_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('closed_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('opened_automatically', sa.Boolean(), server_default=sa.false(), nullable=False),
    sa.Column('closed_automatically', sa.Boolean(), server_default=sa.false(), nullable=False),
    sa.CheckConstraint('opening_amount >= 0', name=op.f('ck_cash_registers_opening_amount_not_negative')),
    sa.ForeignKeyConstraint(['closed_by'], ['users.id'], name=op.f('fk_cash_registers_closed_by_users')),
    sa.ForeignKeyConstraint(['opened_by'], ['users.id'], name=op.f('fk_cash_registers_opened_by_users')),
    sa.ForeignKeyConstraint(['store_id'], ['stores.id'], name=op.f('fk_cash_registers_store_id_stores')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_cash_registers'))
    )
    op.create_index(op.f('ix_cash_registers_status'), 'cash_registers', ['status'], unique=False)
    op.create_index(op.f('ix_cash_registers_store_id'), 'cash_registers', ['store_id'], unique=False)
    op.create_index('uq_cash_registers_one_open_per_store', 'cash_registers', ['store_id'], unique=True, postgresql_where=sa.text("status = 'OPEN'"))
    op.create_table('cash_transactions',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('cash_register_id', sa.Integer(), nullable=False),
    sa.Column('type', sa.Enum('SALE', 'EXPENSE', 'WITHDRAWAL', 'DEPOSIT', 'REFUND', 'ADJUSTMENT', name='cashtransactiontype', native_enum=False, length=30), nullable=False),
    sa.Column('amount', sa.Numeric(precision=14, scale=2), nullable=False),
    sa.Column('reason', sa.String(length=255), nullable=True),
    sa.Column('reference', sa.String(length=100), nullable=True),
    sa.Column('created_by', sa.Integer(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint('amount <> 0', name=op.f('ck_cash_transactions_amount_not_zero')),
    sa.ForeignKeyConstraint(['cash_register_id'], ['cash_registers.id'], name=op.f('fk_cash_transactions_cash_register_id_cash_registers')),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], name=op.f('fk_cash_transactions_created_by_users')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_cash_transactions'))
    )
    op.create_index(op.f('ix_cash_transactions_cash_register_id'), 'cash_transactions', ['cash_register_id'], unique=False)
