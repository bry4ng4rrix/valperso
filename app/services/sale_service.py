"""Ventes : création transactionnelle, annulation et consultation.

Création d'une vente, en une seule transaction :
    magasin -> produits -> stock -> sous-total -> réduction -> total -> Sale -> SaleItems
    -> déduction du stock + StockMovement (SALE) -> Payment -> caisse -> AuditLog -> COMMIT
Si une étape échoue, une exception est levée avant le COMMIT : la session est annulée
(ROLLBACK) et aucune vente partielle ne reste en base.
"""

from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, NotFoundError
from app.models import Product, Sale, SaleItem, Store, User
from app.models.enums import DiscountType, SaleStatus, StockMovementType
from app.repositories import sale_repository, stock_repository
from app.repositories.base import PageResult
from app.schemas.sale import SaleCancel, SaleCreate, SaleFilters, SaleItemCreate, SaleRead
from app.services import audit_service, discount_service, payment_service, stock_service, store_access
from app.utils.text import display_text


@dataclass
class SaleLine:
    product: Product
    quantity: int

    @property
    def unit_price(self) -> Decimal:
        return self.product.selling_price

    @property
    def total(self) -> Decimal:
        return self.unit_price * self.quantity


def _build_lines(db: Session, store: Store, items: list[SaleItemCreate]) -> list[SaleLine]:
    """Vérifie les produits et le stock du magasin. Les produits restent verrouillés jusqu'au COMMIT."""
    product_ids = [item.product_id for item in items]
    products = stock_service.lock_products(db, product_ids)
    store_lines = stock_repository.lock_lines(db, store.id, product_ids)

    lines = []
    for item in items:
        product = products[item.product_id]
        if not product.is_active:
            raise BusinessRuleError(
                f"Le produit « {display_text(product.reference)} » est désactivé et ne peut pas être vendu",
                code="PRODUCT_INACTIVE",
            )
        available = store_lines[product.id].quantity if product.id in store_lines else 0
        if available < item.quantity:
            raise stock_service.insufficient_stock_error(product, store, available, item.quantity)
        lines.append(SaleLine(product=product, quantity=item.quantity))
    return lines


def create_sale(db: Session, user: User, data: SaleCreate, ip_address: str | None = None) -> Sale:
    store = store_access.resolve_operation_store(db, user, data.store_id)
    discount_service.ensure_discount_allowed(user, data.discount_type)
    lines = _build_lines(db, store, data.items)

    # Les montants sont toujours calculés ici, jamais repris de la requête.
    subtotal = sum((line.total for line in lines), Decimal("0"))
    discount_amount = discount_service.compute_discount(subtotal, data.discount_type, data.discount_value)

    sale = Sale(
        sale_number=sale_repository.next_sale_number(db),
        store_id=store.id,
        user_id=user.id,
        customer_name=data.customer_name,
        subtotal=subtotal,
        discount_type=data.discount_type,
        discount_value=data.discount_value,
        discount_amount=discount_amount,
        total=subtotal - discount_amount,
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
            product=line.product,
            store=store,
            delta=-line.quantity,
            movement_type=StockMovementType.SALE,
            user_id=user.id,
            reason=f"VENTE {sale.sale_number}",
            reference=sale.sale_number,
        )

    payment_service.record_payment(
        db,
        sale=sale,
        method=data.payment.method,
        amount=sale.total,
        user_id=user.id,
        reference=data.payment.reference,
    )

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
        discount_data = {
            key: sale_data[key] for key in ("discount_type", "discount_value", "discount_amount")
        }
        audit_service.record(
            db,
            user_id=user.id,
            action="sale.discount",
            entity_type="sale",
            entity_id=sale.id,
            new_data=discount_data,
            ip_address=ip_address,
        )

    db.commit()
    return sale


def cancel_sale(
    db: Session, user: User, sale_id: int, data: SaleCancel, ip_address: str | None = None
) -> Sale:
    """Annule une vente : le stock est remis dans le magasin et les espèces sont remboursées."""
    sale = sale_repository.get_for_update(db, sale_id)
    if sale is None:
        raise NotFoundError("Vente introuvable")
    store_access.ensure_store_access(user, sale.store_id)
    if sale.status == SaleStatus.CANCELLED:
        raise BusinessRuleError("Cette vente est déjà annulée", code="SALE_ALREADY_CANCELLED")

    old_data = audit_service.snapshot(SaleRead, sale)
    store = store_access.get_store_or_404(db, sale.store_id)
    products = stock_service.lock_products(db, [item.product_id for item in sale.items])
    for item in sale.items:
        stock_service.apply_stock_change(
            db,
            product=products[item.product_id],
            store=store,
            delta=item.quantity,
            movement_type=StockMovementType.RETURN,
            user_id=user.id,
            reason=f"ANNULATION VENTE {sale.sale_number}",
            reference=sale.sale_number,
        )
    payment_service.refund_cash_payments(db, sale=sale, user_id=user.id)

    sale.status = SaleStatus.CANCELLED
    db.flush()
    audit_service.record(
        db,
        user_id=user.id,
        action="sale.cancel",
        entity_type="sale",
        entity_id=sale.id,
        old_data=old_data,
        new_data=audit_service.snapshot(SaleRead, sale) | {"cancel_reason": data.reason},
        ip_address=ip_address,
    )
    db.commit()
    return sale


def list_sales(db: Session, user: User, filters: SaleFilters) -> PageResult[Sale]:
    store_id = store_access.visible_store_id(user, filters.store_id)
    return sale_repository.list_sales(db, filters.model_copy(update={"store_id": store_id}))


def get_sale(db: Session, user: User, sale_id: int) -> Sale:
    sale = db.get(Sale, sale_id)
    if sale is None:
        raise NotFoundError("Vente introuvable")
    store_access.ensure_store_access(user, sale.store_id)
    return sale
