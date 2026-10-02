"""Transferts de stock entre magasins (ex. du Stock Local vers un magasin).

Un transfert DÉPLACE le stock : la source diminue, la destination augmente, le stock global ne
change pas. Ce n'est ni une vente, ni une perte. Exemple avec 10 unités au Stock Local :
- transfert de 5  -> source 5, destination 5 (ligne créée si le magasin n'avait pas le produit) ;
- transfert de 10 -> source 0 (stock déplacé), destination 10 ;
- transfert de 11 -> refusé (InsufficientStock), rien n'est modifié.

Toutes les écritures (lignes de stock, mouvements TRANSFER_OUT / TRANSFER_IN, transfert, audit)
sont faites dans une seule transaction : tout est validé, ou rien.
"""

from dataclasses import dataclass

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import InvalidStoreAccess, InvalidTransfer, NotFoundError
from app.core.permissions import is_admin
from app.models import Product, Stock, StockTransfer, StockTransferItem, Store, User
from app.models.enums import StockMovementType, TransferStatus
from app.repositories import stock_repository, stock_transfer_repository
from app.repositories.base import PageResult
from app.schemas.product import ProductSummary
from app.schemas.stock_transfer import (
    StockTransferCreate,
    StockTransferFilters,
    StockTransferRead,
    TransferStockLevel,
)
from app.services import audit_service, stock_service, store_access
from app.services.product_service import get_active_product


@dataclass
class TransferOutcome:
    """Transfert créé + stock de chaque produit dans les deux magasins après l'opération."""

    transfer: StockTransfer
    stock_levels: list[TransferStockLevel]


def _move(
    db: Session,
    *,
    lines: dict[tuple[int, int], Stock],
    product: Product,
    quantity: int,
    from_store: Store,
    to_store: Store,
    user: User,
    reference: str,
    label: str,
) -> None:
    """Retire `quantity` du magasin `from_store` et l'ajoute au magasin `to_store`."""
    source_line = lines.get((from_store.id, product.id))
    available = source_line.quantity if source_line else 0
    if source_line is None or available < quantity:
        raise stock_service.insufficient_stock(product, from_store, available, quantity)

    common = {"user_id": user.id, "reference": reference}
    stock_service.apply_stock_change(
        db,
        line=source_line,
        delta=-quantity,
        movement_type=StockMovementType.TRANSFER_OUT,
        reason=f"{label} VERS {to_store.name}",
        **common,
    )
    stock_service.apply_stock_change(
        db,
        line=lines[(to_store.id, product.id)],
        delta=quantity,
        movement_type=StockMovementType.TRANSFER_IN,
        reason=f"{label} DEPUIS {from_store.name}",
        **common,
    )


def _lock_lines(db: Session, source: Store, destination: Store, product_ids: list[int]) -> dict:
    """Crée les lignes manquantes (la destination peut ne pas avoir le produit) puis verrouille
    toutes les lignes concernées, par id croissant (pas d'interblocage entre transferts croisés)."""
    store_ids = [source.id, destination.id]
    stock_repository.create_missing_lines(db, store_ids, product_ids, settings.DEFAULT_ALERT_THRESHOLD)
    return stock_repository.lock_lines(db, store_ids, product_ids)


def _stock_levels(
    lines: dict, source: Store, destination: Store, products: list[Product]
) -> list[TransferStockLevel]:
    return [
        TransferStockLevel(
            product=ProductSummary.model_validate(product),
            source_quantity=lines[(source.id, product.id)].quantity,
            destination_quantity=lines[(destination.id, product.id)].quantity,
        )
        for product in products
    ]


def _audit(db: Session, user: User, transfer: StockTransfer, action: str, ip_address: str | None) -> None:
    db.flush()
    audit_service.record(
        db,
        user_id=user.id,
        action=action,
        entity_type="stock_transfer",
        entity_id=transfer.id,
        new_data=audit_service.snapshot(StockTransferRead, transfer),
        ip_address=ip_address,
    )


def create_transfer(
    db: Session, user: User, data: StockTransferCreate, ip_address: str | None = None
) -> TransferOutcome:
    source = store_access.resolve_operation_store(db, user, data.source_store_id)
    destination = store_access.get_active_store(db, data.destination_store_id)
    if source.id == destination.id:
        raise InvalidTransfer("Le magasin de destination doit être différent du magasin source")

    products = [get_active_product(db, item.product_id) for item in data.items]
    lines = _lock_lines(db, source, destination, [product.id for product in products])

    reference = stock_transfer_repository.next_reference(db)
    for product, item in zip(products, data.items, strict=True):
        _move(
            db,
            lines=lines,
            product=product,
            quantity=item.quantity,
            from_store=source,
            to_store=destination,
            user=user,
            reference=reference,
            label="TRANSFERT",
        )

    transfer = StockTransfer(
        reference=reference,
        source_store=source,
        destination_store=destination,
        created_by=user.id,
        status=TransferStatus.COMPLETED,
        completed_at=func.now(),
        items=[StockTransferItem(product_id=item.product_id, quantity=item.quantity) for item in data.items],
    )
    db.add(transfer)
    _audit(db, user, transfer, "stock_transfer.create", ip_address)
    db.commit()
    return TransferOutcome(transfer, _stock_levels(lines, source, destination, products))


def cancel_transfer(db: Session, user: User, transfer_id: int, ip_address: str | None = None) -> TransferOutcome:
    """Annule un transfert : les quantités repartent de la destination vers la source.
    Impossible si la destination n'a plus assez de stock (déjà vendu ou transféré ailleurs)."""
    transfer = stock_transfer_repository.get_for_update(db, transfer_id)
    if transfer is None:
        raise NotFoundError("Transfert introuvable")
    store_access.ensure_store_access(user, transfer.source_store_id)
    if transfer.status == TransferStatus.CANCELLED:
        raise InvalidTransfer("Ce transfert est déjà annulé")

    source, destination = transfer.source_store, transfer.destination_store
    products = [item.product for item in transfer.items]
    lines = _lock_lines(db, source, destination, [product.id for product in products])
    for item in transfer.items:
        _move(
            db,
            lines=lines,
            product=item.product,
            quantity=item.quantity,
            from_store=destination,
            to_store=source,
            user=user,
            reference=transfer.reference,
            label="ANNULATION TRANSFERT",
        )

    transfer.status = TransferStatus.CANCELLED
    _audit(db, user, transfer, "stock_transfer.cancel", ip_address)
    db.commit()
    return TransferOutcome(transfer, _stock_levels(lines, source, destination, products))


def list_transfers(db: Session, user: User, filters: StockTransferFilters) -> PageResult[StockTransfer]:
    # Un vendeur voit les transferts envoyés ou reçus par son magasin.
    store_id = store_access.visible_store_id(user, filters.store_id)
    return stock_transfer_repository.list_transfers(db, filters.model_copy(update={"store_id": store_id}))


def get_transfer(db: Session, user: User, transfer_id: int) -> StockTransfer:
    transfer = db.get(StockTransfer, transfer_id)
    if transfer is None:
        raise NotFoundError("Transfert introuvable")
    if not is_admin(user) and store_access.own_store_id(user) not in (
        transfer.source_store_id,
        transfer.destination_store_id,
    ):
        raise InvalidStoreAccess(f"Le transfert {transfer.reference} ne concerne pas votre magasin")
    return transfer
