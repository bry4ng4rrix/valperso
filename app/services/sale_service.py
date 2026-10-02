"""Ventes : création transactionnelle, annulation, historique et factures.

Création d'une vente, en une seule transaction :
    magasin -> client -> produits -> verrouillage des stocks -> vérification des stocks
    -> sous-total -> remise -> total -> Sale + SaleItems -> déduction du stock + mouvements SALE
    -> paiement initial éventuel (+ caisse si espèces) -> audit -> COMMIT
Si une étape échoue, une exception est levée avant le COMMIT : tout est annulé (ROLLBACK).
Il ne peut donc jamais exister de vente sans stock déduit, ni de paiement sans vente.
"""

from dataclasses import dataclass
from datetime import date
from decimal import Decimal

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import InvalidPayment, NotFoundError, SaleAlreadyCancelled
from app.models import Customer, Product, Sale, SaleItem, Stock, Store, User
from app.models.enums import DiscountType, PaymentMethod, SaleStatus, StockMovementType
from app.repositories import sale_repository, stock_repository
from app.repositories.base import PageResult
from app.schemas.sale import SaleCancel, SaleCreate, SaleHistoryFilters, SaleItemCreate, SalePaymentCreate, SaleRead
from app.services import (
    audit_service,
    customer_service,
    discount_service,
    payment_service,
    stock_service,
    store_access,
)
from app.services.product_service import get_active_product


@dataclass
class SaleLine:
    product: Product
    stock: Stock
    quantity: int

    @property
    def unit_price(self) -> Decimal:
        return self.product.selling_price

    @property
    def total(self) -> Decimal:
        return self.unit_price * self.quantity


# --- Étapes de la création d'une vente -----------------------------------------------------------


def _resolve_customer(db: Session, user: User, data: SaleCreate, ip_address: str | None) -> Customer:
    if data.customer_id is not None:
        return customer_service.get_customer(db, data.customer_id)
    assert data.customer is not None  # garanti par la validation de SaleCreate
    return customer_service.find_or_add_for_sale(db, user, data.customer, ip_address)


def _build_lines(db: Session, store: Store, items: list[SaleItemCreate]) -> list[SaleLine]:
    """Vérifie les produits et le stock du magasin. Les lignes de stock restent verrouillées jusqu'au COMMIT."""
    products = [get_active_product(db, item.product_id) for item in items]
    stocks = stock_repository.lock_lines(db, [store.id], [product.id for product in products])

    lines = []
    for product, item in zip(products, items, strict=True):
        stock = stocks.get((store.id, product.id))
        available = stock.quantity if stock else 0
        if stock is None or available < item.quantity:
            raise stock_service.insufficient_stock(product, store, available, item.quantity)
        lines.append(SaleLine(product=product, stock=stock, quantity=item.quantity))
    return lines


def _initial_payment_amount(payment: SalePaymentCreate | None, total: Decimal) -> Decimal:
    """Montant encaissé à la création : tout le total par défaut, une avance, ou rien (CREDIT)."""
    if payment is None or payment.method == PaymentMethod.CREDIT:
        return Decimal("0")
    amount = total if payment.amount is None else payment.amount
    if amount > total:
        raise InvalidPayment(f"Le paiement ({amount}) dépasse le total de la vente ({total})")
    return amount


def _debt_due_date(customer: Customer, remaining: Decimal, due_date: date | None) -> date | None:
    """Une vente avec reste à payer exige le téléphone du client et une date d'échéance."""
    if remaining <= 0:
        return None  # paiement complet : l'échéance est inutile
    if not customer.phone:
        raise InvalidPayment("Le téléphone du client est obligatoire pour une vente avec avance ou à crédit")
    if due_date is None:
        raise InvalidPayment("La date d'échéance (payment_due_date) est obligatoire s'il reste un montant à payer")
    return due_date


def _audit_sale(db: Session, user: User, sale: Sale, ip_address: str | None) -> None:
    sale_data = audit_service.snapshot(SaleRead, sale)
    audit_service.record(
        db,
        user_id=user.id,
        action="sale.create",
        entity_type="sale",
        entity_id=sale.id,
        new_data=sale_data,
        ip_address=ip_address,
    )
    if sale.discount_type != DiscountType.NONE:
        discount_fields = ("discount_type", "discount_value", "discount_amount")
        audit_service.record(
            db,
            user_id=user.id,
            action="sale.discount",
            entity_type="sale",
            entity_id=sale.id,
            new_data={key: sale_data[key] for key in discount_fields},
            ip_address=ip_address,
        )


def create_sale(db: Session, user: User, data: SaleCreate, ip_address: str | None = None) -> Sale:
    store = store_access.resolve_operation_store(db, user, data.store_id)
    discount_service.ensure_discount_allowed(user, data.discount_type)
    customer = _resolve_customer(db, user, data, ip_address)
    lines = _build_lines(db, store, data.items)

    # Tous les montants sont calculés ici, jamais repris de la requête.
    subtotal = sum((line.total for line in lines), Decimal("0"))
    discount_amount = discount_service.compute_discount(subtotal, data.discount_type, data.discount_value)
    total = subtotal - discount_amount
    paid_now = _initial_payment_amount(data.payment, total)
    due_date = _debt_due_date(customer, total - paid_now, data.payment_due_date)

    sale = Sale(
        sale_number=sale_repository.next_invoice_number(db),
        customer=customer,
        store=store,
        user_id=user.id,  # toujours l'utilisateur connecté (lu dans le JWT)
        subtotal=subtotal,
        discount_type=data.discount_type,
        discount_value=data.discount_value,
        discount_amount=discount_amount,
        total=total,
        payment_status=payment_service.compute_payment_status(total, paid_now),
        payment_due_date=due_date,
        status=SaleStatus.COMPLETED,
        items=[
            SaleItem(
                product_id=line.product.id,
                product_reference=line.product.reference,
                product_name=line.product.name,
                quantity=line.quantity,
                unit_price=line.unit_price,
                total=line.total,
            )
            for line in lines
        ],
    )
    db.add(sale)
    db.flush()

    for line in lines:
        stock_service.apply_stock_change(
            db,
            line=line.stock,
            delta=-line.quantity,
            movement_type=StockMovementType.SALE,
            user_id=user.id,
            reason=f"VENTE {sale.sale_number}",
            reference=sale.sale_number,
        )

    if paid_now > 0:
        assert data.payment is not None
        payment_service.record_payment(
            db,
            sale=sale,
            method=data.payment.method,
            amount=paid_now,
            user_id=user.id,
            reference=data.payment.reference,
        )

    _audit_sale(db, user, sale, ip_address)
    db.commit()
    return sale


# --- Annulation ----------------------------------------------------------------------------------


def cancel_sale(
    db: Session, user: User, sale_id: int, data: SaleCancel, ip_address: str | None = None
) -> Sale:
    """Annule une vente : le stock revient dans le magasin (mouvements RETURN) et les espèces
    encaissées sont remboursées depuis la caisse. Les paiements restent visibles dans l'historique."""
    sale = sale_repository.get_for_update(db, sale_id)
    if sale is None:
        raise NotFoundError("Vente introuvable")
    store_access.ensure_store_access(user, sale.store_id)
    if sale.status == SaleStatus.CANCELLED:
        raise SaleAlreadyCancelled()

    old_data = audit_service.snapshot(SaleRead, sale)
    product_ids = [item.product_id for item in sale.items]
    stock_repository.create_missing_lines(db, [sale.store_id], product_ids, settings.DEFAULT_ALERT_THRESHOLD)
    stocks = stock_repository.lock_lines(db, [sale.store_id], product_ids)
    for item in sale.items:
        stock_service.apply_stock_change(
            db,
            line=stocks[(sale.store_id, item.product_id)],
            delta=item.quantity,
            movement_type=StockMovementType.RETURN,
            user_id=user.id,
            reason=f"ANNULATION VENTE {sale.sale_number}",
            reference=sale.sale_number,
        )
    refunded_cash = payment_service.refund_cash_payments(db, sale=sale, user_id=user.id)

    sale.status = SaleStatus.CANCELLED
    db.flush()
    audit_service.record(
        db,
        user_id=user.id,
        action="sale.cancel",
        entity_type="sale",
        entity_id=sale.id,
        old_data=old_data,
        new_data=audit_service.snapshot(SaleRead, sale)
        | {"cancel_reason": data.reason, "refunded_cash": float(refunded_cash)},
        ip_address=ip_address,
    )
    db.commit()
    return sale


# --- Consultation --------------------------------------------------------------------------------


def list_history(db: Session, user: User, filters: SaleHistoryFilters) -> PageResult[Sale]:
    """Historique des ventes. Un vendeur ne voit que les ventes de son magasin."""
    store_id = store_access.visible_store_id(user, filters.store_id)
    return sale_repository.list_history(db, filters.model_copy(update={"store_id": store_id}))


def get_sale(db: Session, user: User, sale_id: int) -> Sale:
    sale = db.get(Sale, sale_id)
    if sale is None:
        raise NotFoundError("Vente introuvable")
    store_access.ensure_store_access(user, sale.store_id)
    return sale
