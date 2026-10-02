"""Transferts de produits entre magasins.

Exemple : le STOCK LOCAL a 10 unités de l'article 1.
- Transfert de 5 : l'article est créé dans le magasin de destination (s'il n'y existait pas)
  avec 5 unités, et le STOCK LOCAL passe à 5.
- Transfert des 10 : tout est déplacé ; l'article reste visible dans le STOCK LOCAL en RUPTURE (0).

Le transfert, les deux lignes de stock et les deux mouvements (TRANSFER_OUT / TRANSFER_IN)
sont enregistrés dans une seule transaction : tout est validé, ou rien.
"""

from dataclasses import dataclass

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, NotFoundError, PermissionDeniedError
from app.models import StockTransfer, StoreStock, User
from app.models.enums import StockMovementType
from app.repositories import stock_repository
from app.repositories.base import PageResult
from app.schemas.stock import StockTransferCreate, StockTransferFilters, StockTransferRead
from app.services import audit_service, stock_service, store_access
from app.utils.text import display_text


@dataclass
class TransferOutcome:
    transfer: StockTransfer
    source_stock: StoreStock
    destination_stock: StoreStock


def transfer_stock(
    db: Session, user: User, data: StockTransferCreate, ip_address: str | None = None
) -> TransferOutcome:
    source = store_access.resolve_operation_store(db, user, data.source_store_id)
    destination = store_access.get_active_store(db, data.destination_store_id)
    if source.id == destination.id:
        raise BusinessRuleError("Le magasin de destination doit être différent du magasin source")

    product = stock_service.lock_product(db, data.product_id)
    if not product.is_active:
        raise BusinessRuleError(f"Le produit « {display_text(product.reference)} » est désactivé")

    transfer = StockTransfer(
        product_id=product.id,
        source_store_id=source.id,
        destination_store_id=destination.id,
        user_id=user.id,
        quantity=data.quantity,
        reason=data.reason,
    )
    db.add(transfer)
    db.flush()  # attribue l'id utilisé dans la référence TRF-xxxxxx

    # Lignes de stock des deux magasins : l'article est créé dans la destination s'il n'y existe pas.
    source_line = stock_service.lock_or_create_line(db, source.id, product.id)
    destination_line = stock_service.lock_or_create_line(db, destination.id, product.id)
    common = {"product": product, "user_id": user.id, "reference": transfer.reference}
    stock_service.apply_stock_change(
        db,
        store=source,
        delta=-data.quantity,
        movement_type=StockMovementType.TRANSFER_OUT,
        reason=f"TRANSFERT VERS {destination.name}",
        **common,
    )
    stock_service.apply_stock_change(
        db,
        store=destination,
        delta=data.quantity,
        movement_type=StockMovementType.TRANSFER_IN,
        reason=f"TRANSFERT DEPUIS {source.name}",
        **common,
    )
    db.flush()

    audit_service.record(
        db,
        user_id=user.id,
        action="stock.transfer",
        entity_type="stock_transfer",
        entity_id=transfer.id,
        new_data=audit_service.snapshot(StockTransferRead, transfer),
        ip_address=ip_address,
    )
    db.commit()
    return TransferOutcome(transfer=transfer, source_stock=source_line, destination_stock=destination_line)


def list_transfers(db: Session, user: User, filters: StockTransferFilters) -> PageResult[StockTransfer]:
    # Un utilisateur rattaché à un magasin voit les transferts envoyés ou reçus par son magasin.
    store_id = store_access.visible_store_id(user, filters.store_id)
    return stock_repository.list_transfers(db, filters.model_copy(update={"store_id": store_id}))


def get_transfer(db: Session, user: User, transfer_id: int) -> StockTransfer:
    transfer = db.get(StockTransfer, transfer_id)
    if transfer is None:
        raise NotFoundError("Transfert introuvable")
    if user.store_id is not None and user.store_id not in (
        transfer.source_store_id,
        transfer.destination_store_id,
    ):
        raise PermissionDeniedError("Vous n'avez pas accès à ce transfert", code="STORE_ACCESS_DENIED")
    return transfer
