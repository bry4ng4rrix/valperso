"""Caisses : ouverture, opérations, clôture.

Seuls les paiements en espèces (CASH) passent par la caisse. `expected_amount` (montant
théorique) est mis à jour à chaque opération ; la caisse ne peut jamais devenir négative.
"""

from decimal import Decimal

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, CashRegisterClosed, NotFoundError
from app.models import CashRegister, CashTransaction, User
from app.models.enums import CashRegisterStatus, CashTransactionType
from app.repositories import cash_repository
from app.repositories.base import PageResult
from app.schemas.cash import (
    CashRegisterClose,
    CashRegisterFilters,
    CashRegisterOpen,
    CashRegisterRead,
    CashTransactionCreate,
    CashTransactionRead,
)
from app.schemas.common import Pagination
from app.services import audit_service, store_access

# Types d'opération qui retirent de l'argent de la caisse (le montant saisi est positif).
OUTGOING_TYPES = {CashTransactionType.EXPENSE, CashTransactionType.WITHDRAWAL}


# --- Opérations de base (utilisées aussi par les ventes et les paiements) -----------------------


def get_open_register_for_update(db: Session, store_id: int) -> CashRegister:
    register = cash_repository.get_open_register(db, store_id, for_update=True)
    if register is None:
        raise CashRegisterClosed(
            "Aucune caisse ouverte pour ce magasin : ouvrez une caisse avant d'encaisser en espèces"
        )
    return register


def add_transaction(
    db: Session,
    register: CashRegister,
    *,
    transaction_type: CashTransactionType,
    amount: Decimal,
    user_id: int,
    reason: str | None = None,
    reference: str | None = None,
) -> CashTransaction:
    """Enregistre une opération signée (positive = entrée, négative = sortie) dans une caisse ouverte.

    La caisse doit avoir été verrouillée au préalable (get_open_register_for_update / get_for_update).
    """
    if register.status != CashRegisterStatus.OPEN:
        raise CashRegisterClosed("Cette caisse est clôturée")
    if register.expected_amount + amount < 0:
        raise BusinessRuleError(
            f"Fonds insuffisants en caisse (disponible : {register.expected_amount})",
            code="INSUFFICIENT_CASH",
        )

    register.expected_amount += amount
    transaction = CashTransaction(
        cash_register_id=register.id,
        type=transaction_type,
        amount=amount,
        reason=reason,
        reference=reference,
        created_by=user_id,
    )
    db.add(transaction)
    return transaction


# --- Cycle de vie d'une caisse -------------------------------------------------------------------


def open_register(
    db: Session, user: User, data: CashRegisterOpen, ip_address: str | None = None
) -> CashRegister:
    store = store_access.resolve_operation_store(db, user, data.store_id)
    if cash_repository.get_open_register(db, store.id) is not None:
        raise BusinessRuleError(
            "Une caisse est déjà ouverte pour ce magasin", code="CASH_REGISTER_ALREADY_OPEN"
        )

    register = CashRegister(
        store_id=store.id,
        opened_by=user.id,
        opening_amount=data.opening_amount,
        expected_amount=data.opening_amount,
        status=CashRegisterStatus.OPEN,
    )
    db.add(register)
    db.flush()
    audit_service.record(
        db,
        user_id=user.id,
        action="cash.open",
        entity_type="cash_register",
        entity_id=register.id,
        new_data=audit_service.snapshot(CashRegisterRead, register),
        ip_address=ip_address,
    )
    db.commit()
    return register


def close_register(
    db: Session, user: User, register_id: int, data: CashRegisterClose, ip_address: str | None = None
) -> CashRegister:
    register = cash_repository.get_for_update(db, register_id)
    if register is None:
        raise NotFoundError("Caisse introuvable")
    store_access.ensure_store_access(user, register.store_id)
    if register.status == CashRegisterStatus.CLOSED:
        raise CashRegisterClosed("Cette caisse est déjà clôturée")

    old_data = audit_service.snapshot(CashRegisterRead, register)
    register.closing_amount = data.closing_amount
    register.difference = data.closing_amount - register.expected_amount
    register.status = CashRegisterStatus.CLOSED
    register.closed_by = user.id
    register.closed_at = func.now()
    db.flush()
    audit_service.record(
        db,
        user_id=user.id,
        action="cash.close",
        entity_type="cash_register",
        entity_id=register.id,
        old_data=old_data,
        new_data=audit_service.snapshot(CashRegisterRead, register),
        ip_address=ip_address,
    )
    db.commit()
    return register


def add_manual_transaction(
    db: Session, user: User, register_id: int, data: CashTransactionCreate, ip_address: str | None = None
) -> CashTransaction:
    """Dépense, retrait, dépôt ou ajustement saisi par un utilisateur."""
    register = cash_repository.get_for_update(db, register_id)
    if register is None:
        raise NotFoundError("Caisse introuvable")
    store_access.ensure_store_access(user, register.store_id)

    signed_amount = -data.amount if data.type in OUTGOING_TYPES else data.amount
    transaction = add_transaction(
        db,
        register,
        transaction_type=data.type,
        amount=signed_amount,
        user_id=user.id,
        reason=data.reason,
        reference=data.reference,
    )
    db.flush()
    audit_service.record(
        db,
        user_id=user.id,
        action="cash.transaction",
        entity_type="cash_register",
        entity_id=register.id,
        new_data=audit_service.snapshot(CashTransactionRead, transaction),
        ip_address=ip_address,
    )
    db.commit()
    return transaction


# --- Consultation --------------------------------------------------------------------------------


def list_registers(db: Session, user: User, filters: CashRegisterFilters) -> PageResult[CashRegister]:
    store_id = store_access.visible_store_id(user, filters.store_id)
    return cash_repository.list_registers(db, filters.model_copy(update={"store_id": store_id}))


def get_register(db: Session, user: User, register_id: int) -> CashRegister:
    register = db.get(CashRegister, register_id)
    if register is None:
        raise NotFoundError("Caisse introuvable")
    store_access.ensure_store_access(user, register.store_id)
    return register


def get_current_register(db: Session, user: User, store_id: int | None) -> CashRegister:
    store = store_access.resolve_operation_store(db, user, store_id)
    register = cash_repository.get_open_register(db, store.id)
    if register is None:
        raise NotFoundError("Aucune caisse ouverte pour ce magasin")
    return register


def list_transactions(
    db: Session, user: User, register_id: int, pagination: Pagination
) -> PageResult[CashTransaction]:
    register = get_register(db, user, register_id)
    return cash_repository.list_transactions(db, register.id, pagination.page, pagination.page_size)
