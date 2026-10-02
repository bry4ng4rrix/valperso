"""Paiements : paiement complet, avance, solde d'une dette.

- Un paiement est une somme réellement encaissée (montant > 0) ; l'historique n'est jamais écrasé.
- Le montant payé (`amount_paid`) est toujours recalculé à partir des paiements, jamais reçu du frontend.
- Le reste à payer est `total - amount_paid` ; un paiement ne peut pas le dépasser.
- Un paiement en espèces (CASH) entre dans la caisse ouverte du magasin.

Évolution prévue (MIXED) : plusieurs paiements de modes différents enregistrés avec `record_payment()`.
"""

from decimal import Decimal

from sqlalchemy.orm import Session

from app.core.exceptions import InvalidPayment, NotFoundError, PaymentAlreadyCompleted
from app.models import Payment, Sale, User
from app.models.enums import CashTransactionType, PaymentMethod, PaymentStatus, SaleStatus
from app.repositories import payment_repository, sale_repository
from app.repositories.base import PageResult
from app.schemas.payment import PaymentCreate, PaymentFilters, PaymentRead
from app.services import audit_service, cash_service, store_access


def compute_payment_status(total: Decimal, amount_paid: Decimal) -> PaymentStatus:
    if amount_paid >= total:
        return PaymentStatus.PAID
    if amount_paid > 0:
        return PaymentStatus.PARTIAL
    return PaymentStatus.UNPAID


def record_payment(
    db: Session,
    *,
    sale: Sale,
    method: PaymentMethod,
    amount: Decimal,
    user_id: int,
    reference: str | None = None,
) -> Payment:
    """Enregistre un encaissement. S'il est en espèces, l'argent entre dans la caisse ouverte du magasin."""
    payment = Payment(sale=sale, method=method, amount=amount, reference=reference, created_by=user_id)
    db.add(payment)

    if method == PaymentMethod.CASH:
        register = cash_service.get_open_register_for_update(db, sale.store_id)
        cash_service.add_transaction(
            db,
            register,
            transaction_type=CashTransactionType.SALE,
            amount=amount,
            user_id=user_id,
            reason=f"PAIEMENT {sale.sale_number}",
            reference=sale.sale_number,
        )
    db.flush()
    db.expire(sale, ["amount_paid"])  # le montant payé sera recalculé à la prochaine lecture
    return payment


def refund_cash_payments(db: Session, *, sale: Sale, user_id: int) -> Decimal:
    """Rembourse depuis la caisse les sommes encaissées en espèces (annulation de vente)."""
    cash_total = sum((p.amount for p in sale.payments if p.method == PaymentMethod.CASH), Decimal("0"))
    if cash_total > 0:
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
    return cash_total


def add_payment(db: Session, user: User, data: PaymentCreate, ip_address: str | None = None) -> Payment:
    """Paiement d'une vente qui a un reste à payer (solde d'une avance ou d'une vente à crédit)."""
    sale = sale_repository.get_for_update(db, data.sale_id)  # verrou : deux paiements simultanés s'enchaînent
    if sale is None:
        raise NotFoundError("Vente introuvable")
    store_access.ensure_store_access(user, sale.store_id)
    if sale.status == SaleStatus.CANCELLED:
        raise InvalidPayment("Impossible d'enregistrer un paiement sur une vente annulée")

    already_paid = payment_repository.total_paid(db, sale.id)
    remaining = sale.total - already_paid
    if remaining <= 0:
        raise PaymentAlreadyCompleted()
    if data.amount > remaining:
        raise InvalidPayment(f"Le montant ({data.amount}) dépasse le reste à payer ({remaining})")

    payment = record_payment(
        db, sale=sale, method=data.method, amount=data.amount, user_id=user.id, reference=data.reference
    )
    sale.payment_status = compute_payment_status(sale.total, already_paid + data.amount)
    audit_service.record(
        db,
        user_id=user.id,
        action="payment.create",
        entity_type="sale",
        entity_id=sale.id,
        new_data=audit_service.snapshot(PaymentRead, payment)
        | {"remaining_amount": float(remaining - data.amount), "payment_status": sale.payment_status.value},
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
