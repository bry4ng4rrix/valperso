"""Paiements des ventes.

Une vente a un ou plusieurs paiements. Le mode CREDIT signifie « payé plus tard » : le montant
reste dû et peut être réglé ensuite avec `add_payment()`.

Évolution prévue (MIXED) : la vente accepterait une liste de paiements de modes différents
dont la somme vaut le total ; chacun serait enregistré avec `record_payment()`, sans
changement de base de données (un paiement = une ligne, les modes sont stockés en texte).
"""

from decimal import Decimal

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, NotFoundError
from app.models import Payment, Sale, User
from app.models.enums import CashTransactionType, PaymentMethod, SaleStatus
from app.repositories import payment_repository, sale_repository
from app.repositories.base import PageResult
from app.schemas.payment import PaymentCreate, PaymentFilters, PaymentRead
from app.services import audit_service, cash_service, store_access


def amount_paid(sale: Sale) -> Decimal:
    """Montant réellement encaissé pour la vente (les paiements CREDIT ne sont pas comptés)."""
    return sum((payment.amount for payment in sale.payments if payment.method.is_collected), Decimal("0"))


def record_payment(
    db: Session,
    *,
    sale: Sale,
    method: PaymentMethod,
    amount: Decimal,
    user_id: int,
    reference: str | None = None,
) -> Payment:
    """Enregistre un paiement ; s'il est en espèces, l'argent entre dans la caisse ouverte du magasin."""
    payment = Payment(sale=sale, method=method, amount=amount, reference=reference, created_by=user_id)
    db.add(payment)

    if method == PaymentMethod.CASH and amount > 0:
        register = cash_service.get_open_register_for_update(db, sale.store_id)
        cash_service.add_transaction(
            db,
            register,
            transaction_type=CashTransactionType.SALE,
            amount=amount,
            user_id=user_id,
            reason=f"VENTE {sale.sale_number}",
            reference=sale.sale_number,
        )
    db.flush()
    return payment


def refund_cash_payments(db: Session, *, sale: Sale, user_id: int) -> None:
    """Rembourse depuis la caisse les sommes encaissées en espèces (annulation de vente)."""
    cash_total = sum((p.amount for p in sale.payments if p.method == PaymentMethod.CASH), Decimal("0"))
    if cash_total <= 0:
        return
    register = cash_service.get_open_register_for_update(db, sale.store_id)
    cash_service.add_transaction(
        db,
        register,
        transaction_type=CashTransactionType.REFUND,
        amount=-cash_total,
        user_id=user_id,
        reason=f"ANNULATION VENTE {sale.sale_number}",
        reference=sale.sale_number,
    )


def add_payment(db: Session, user: User, data: PaymentCreate, ip_address: str | None = None) -> Payment:
    """Règlement complémentaire d'une vente qui a encore un reste à payer (vente à crédit)."""
    sale = sale_repository.get_for_update(db, data.sale_id)
    if sale is None:
        raise NotFoundError("Vente introuvable")
    store_access.ensure_store_access(user, sale.store_id)
    if sale.status == SaleStatus.CANCELLED:
        raise BusinessRuleError("Impossible d'enregistrer un paiement sur une vente annulée")

    amount_due = sale.total - amount_paid(sale)
    if amount_due <= 0:
        raise BusinessRuleError("Cette vente est déjà entièrement payée", code="SALE_ALREADY_PAID")
    if data.amount > amount_due:
        raise BusinessRuleError(
            f"Le montant ({data.amount}) dépasse le reste à payer ({amount_due})", code="PAYMENT_EXCEEDS_DUE"
        )

    payment = record_payment(
        db, sale=sale, method=data.method, amount=data.amount, user_id=user.id, reference=data.reference
    )
    audit_service.record(
        db,
        user_id=user.id,
        action="payment.create",
        entity_type="sale",
        entity_id=sale.id,
        new_data=audit_service.snapshot(PaymentRead, payment),
        ip_address=ip_address,
    )
    db.commit()
    return payment


def list_payments(db: Session, user: User, filters: PaymentFilters) -> PageResult[Payment]:
    store_id = store_access.visible_store_id(user, filters.store_id)
    return payment_repository.list_payments(db, filters.model_copy(update={"store_id": store_id}))


def get_payment(db: Session, user: User, payment_id: int) -> Payment:
    payment = db.get(Payment, payment_id)
    if payment is None:
        raise NotFoundError("Paiement introuvable")
    store_access.ensure_store_access(user, payment.sale.store_id)
    return payment
