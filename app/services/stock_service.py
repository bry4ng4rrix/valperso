"""Stock par magasin : opérations de base, entrées, sorties, ajustements et consultation.

Règle centrale : toute variation de stock passe par `apply_stock_change()`, qui met à jour
à la fois la ligne du magasin (store_stocks), le stock total du produit et crée le
mouvement de stock correspondant. Ces trois écritures sont donc toujours cohérentes.
"""

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import BusinessRuleError, InsufficientStockError, NotFoundError
from app.models import Product, StockMovement, Store, StoreStock, User
from app.models.enums import StockMovementType
from app.repositories import product_repository, stock_repository
from app.repositories.base import PageResult
from app.schemas.stock import (
    StockAdjustmentCreate,
    StockEntryCreate,
    StockExitCreate,
    StockMovementFilters,
    StockMovementRead,
    StoreStockFilters,
)
from app.services import audit_service, store_access
from app.utils.text import display_text

# --- Opérations de base (utilisées aussi par les ventes et les transferts) -----------------------


def lock_products(db: Session, product_ids: list[int]) -> dict[int, Product]:
    """Verrouille les produits (FOR UPDATE) ; erreur 404 si l'un d'eux n'existe pas."""
    products = product_repository.lock_by_ids(db, product_ids)
    missing = sorted(set(product_ids) - products.keys())
    if missing:
        raise NotFoundError(f"Produit(s) introuvable(s) : {', '.join(map(str, missing))}")
    return products


def lock_product(db: Session, product_id: int) -> Product:
    return lock_products(db, [product_id])[product_id]


def lock_or_create_line(db: Session, store_id: int, product_id: int) -> StoreStock:
    """Ligne de stock du produit dans le magasin, créée à 0 si le magasin n'a pas encore l'article."""
    line = stock_repository.lock_lines(db, store_id, [product_id]).get(product_id)
    if line is None:
        line = StoreStock(store_id=store_id, product_id=product_id, quantity=0)
        db.add(line)
        db.flush()
    return line


def insufficient_stock_error(
    product: Product, store: Store, available: int, requested: int
) -> InsufficientStockError:
    return InsufficientStockError(
        f"Stock insuffisant pour « {display_text(product.reference)} - {display_text(product.name)} » "
        f"dans le magasin « {display_text(store.name)} » : disponible {available}, demandé {requested}"
    )


def apply_stock_change(
    db: Session,
    *,
    product: Product,
    store: Store,
    delta: int,
    movement_type: StockMovementType,
    user_id: int,
    reason: str | None = None,
    reference: str | None = None,
) -> StockMovement:
    """Ajoute `delta` (positif ou négatif) au stock du produit dans le magasin et trace le mouvement.

    Le produit doit avoir été verrouillé au préalable avec `lock_products()`.
    """
    line = lock_or_create_line(db, store.id, product.id)
    if line.quantity + delta < 0:
        raise insufficient_stock_error(product, store, line.quantity, -delta)

    line.quantity += delta
    product.stock += delta
    movement = StockMovement(
        product_id=product.id,
        store_id=store.id,
        user_id=user_id,
        type=movement_type,
        quantity=delta,
        reason=reason,
        reference=reference,
    )
    db.add(movement)
    return movement


# --- Opérations manuelles ------------------------------------------------------------------------


def _save_manual_movement(
    db: Session, user: User, movement: StockMovement, action: str, ip_address: str | None
) -> StockMovement:
    db.flush()
    audit_service.record(
        db,
        user_id=user.id,
        action=action,
        entity_type="stock_movement",
        entity_id=movement.id,
        new_data=audit_service.snapshot(StockMovementRead, movement),
        ip_address=ip_address,
    )
    db.commit()
    return movement


def record_entry(
    db: Session, user: User, data: StockEntryCreate, ip_address: str | None = None
) -> StockMovement:
    """Entrée de stock (réception de marchandise) dans un magasin."""
    store = store_access.resolve_operation_store(db, user, data.store_id)
    product = lock_product(db, data.product_id)
    movement = apply_stock_change(
        db,
        product=product,
        store=store,
        delta=data.quantity,
        movement_type=StockMovementType.ENTRY,
        user_id=user.id,
        reason=data.reason,
        reference=data.reference,
    )
    return _save_manual_movement(db, user, movement, "stock.entry", ip_address)


def record_exit(
    db: Session, user: User, data: StockExitCreate, ip_address: str | None = None
) -> StockMovement:
    """Sortie (EXIT) ou perte (LOSS) de stock dans un magasin."""
    store = store_access.resolve_operation_store(db, user, data.store_id)
    product = lock_product(db, data.product_id)
    movement = apply_stock_change(
        db,
        product=product,
        store=store,
        delta=-data.quantity,
        movement_type=data.type,
        user_id=user.id,
        reason=data.reason,
        reference=data.reference,
    )
    action = "stock.loss" if data.type == StockMovementType.LOSS else "stock.exit"
    return _save_manual_movement(db, user, movement, action, ip_address)


def adjust_stock(
    db: Session, user: User, data: StockAdjustmentCreate, ip_address: str | None = None
) -> StockMovement:
    """Corrige le stock d'un magasin après inventaire : la quantité devient `new_quantity`."""
    store = store_access.resolve_operation_store(db, user, data.store_id)
    product = lock_product(db, data.product_id)
    current_quantity = lock_or_create_line(db, store.id, product.id).quantity
    delta = data.new_quantity - current_quantity
    if delta == 0:
        raise BusinessRuleError(
            "La quantité saisie est identique au stock actuel : aucun ajustement nécessaire"
        )

    movement = apply_stock_change(
        db,
        product=product,
        store=store,
        delta=delta,
        movement_type=StockMovementType.ADJUSTMENT,
        user_id=user.id,
        reason=data.reason,
    )
    return _save_manual_movement(db, user, movement, "stock.adjust", ip_address)


# --- Consultation --------------------------------------------------------------------------------


def list_store_stock(
    db: Session, user: User, store_id: int, filters: StoreStockFilters
) -> PageResult[StoreStock]:
    """Articles d'un magasin avec leur quantité et leur statut (en stock, stock faible, rupture)."""
    store_access.ensure_store_access(user, store_id)
    store = store_access.get_store_or_404(db, store_id)
    return stock_repository.list_store_stock(db, store.id, filters, settings.LOW_STOCK_THRESHOLD)


def list_movements(db: Session, user: User, filters: StockMovementFilters) -> PageResult[StockMovement]:
    store_id = store_access.visible_store_id(user, filters.store_id)
    return stock_repository.list_movements(db, filters.model_copy(update={"store_id": store_id}))


def get_movement(db: Session, user: User, movement_id: int) -> StockMovement:
    movement = db.get(StockMovement, movement_id)
    if movement is None:
        raise NotFoundError("Mouvement de stock introuvable")
    store_access.ensure_store_access(user, movement.store_id)
    return movement
