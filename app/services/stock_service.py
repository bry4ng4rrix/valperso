"""Stock par magasin : opérations de base, entrées, sorties, ajustements, seuils et consultation.

Règle centrale : toute variation de stock passe par `apply_stock_change()`, qui modifie la ligne
de stock verrouillée et crée le mouvement correspondant. Le stock ne devient jamais négatif.
"""

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import BusinessRuleError, InsufficientStock, NotFoundError
from app.models import Product, Stock, StockMovement, Store, User
from app.models.enums import StockMovementType
from app.repositories import stock_repository
from app.repositories.base import PageResult
from app.schemas.stock import (
    AlertThresholdUpdate,
    StockAdjustmentCreate,
    StockAlertFilters,
    StockEntryCreate,
    StockExitCreate,
    StockFilters,
    StockMovementFilters,
    StockMovementRead,
    StockRead,
)
from app.services import audit_service, store_access
from app.services.product_service import get_product
from app.utils.text import display_text

# --- Opérations de base (utilisées aussi par les ventes et les transferts) -----------------------


def lock_line(db: Session, store: Store, product: Product) -> Stock:
    """Ligne de stock verrouillée jusqu'au COMMIT, créée à 0 si le magasin n'a pas encore le produit."""
    stock_repository.create_missing_lines(db, [store.id], [product.id], settings.DEFAULT_ALERT_THRESHOLD)
    return stock_repository.lock_lines(db, [store.id], [product.id])[(store.id, product.id)]


def insufficient_stock(product: Product, store: Store, available: int, requested: int) -> InsufficientStock:
    return InsufficientStock(
        f"Stock insuffisant pour « {display_text(product.reference)} - {display_text(product.name)} » "
        f"dans le magasin « {display_text(store.name)} » : disponible {available}, demandé {requested}"
    )


def apply_stock_change(
    db: Session,
    *,
    line: Stock,
    delta: int,
    movement_type: StockMovementType,
    user_id: int,
    reason: str | None = None,
    reference: str | None = None,
) -> StockMovement:
    """Ajoute `delta` (positif ou négatif) à une ligne de stock VERROUILLÉE et trace le mouvement."""
    if line.quantity + delta < 0:
        raise insufficient_stock(line.product, line.store, line.quantity, -delta)

    line.quantity += delta
    movement = StockMovement(
        product_id=line.product_id,
        store_id=line.store_id,
        user_id=user_id,
        type=movement_type,
        quantity=delta,
        reason=reason,
        reference=reference,
    )
    db.add(movement)
    return movement


# --- Opérations manuelles ------------------------------------------------------------------------


def _save_movement(
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
    """Entrée de stock (réception de marchandise). La ligne est créée si le magasin n'a pas le produit."""
    store = store_access.resolve_operation_store(db, user, data.store_id)
    line = lock_line(db, store, get_product(db, data.product_id))
    movement = apply_stock_change(
        db,
        line=line,
        delta=data.quantity,
        movement_type=StockMovementType.ENTRY,
        user_id=user.id,
        reason=data.reason,
        reference=data.reference,
    )
    return _save_movement(db, user, movement, "stock.entry", ip_address)


def record_exit(
    db: Session, user: User, data: StockExitCreate, ip_address: str | None = None
) -> StockMovement:
    """Sortie (EXIT) ou perte (LOSS) de stock. Refusée si le stock est insuffisant."""
    store = store_access.resolve_operation_store(db, user, data.store_id)
    line = lock_line(db, store, get_product(db, data.product_id))
    movement = apply_stock_change(
        db,
        line=line,
        delta=-data.quantity,
        movement_type=data.type,
        user_id=user.id,
        reason=data.reason,
        reference=data.reference,
    )
    action = "stock.loss" if data.type == StockMovementType.LOSS else "stock.exit"
    return _save_movement(db, user, movement, action, ip_address)


def adjust_stock(
    db: Session, user: User, data: StockAdjustmentCreate, ip_address: str | None = None
) -> StockMovement:
    """Corrige le stock après inventaire : la quantité devient `new_quantity`."""
    store = store_access.resolve_operation_store(db, user, data.store_id)
    line = lock_line(db, store, get_product(db, data.product_id))
    delta = data.new_quantity - line.quantity
    if delta == 0:
        raise BusinessRuleError(
            "La quantité saisie est identique au stock actuel : aucun ajustement nécessaire"
        )

    movement = apply_stock_change(
        db,
        line=line,
        delta=delta,
        movement_type=StockMovementType.ADJUSTMENT,
        user_id=user.id,
        reason=data.reason,
    )
    return _save_movement(db, user, movement, "stock.adjust", ip_address)


def update_alert_threshold(
    db: Session, user: User, stock_id: int, data: AlertThresholdUpdate, ip_address: str | None = None
) -> Stock:
    line = get_stock(db, user, stock_id)
    old_data = audit_service.snapshot(StockRead, line)
    line.alert_threshold = data.alert_threshold
    db.flush()
    audit_service.record(
        db,
        user_id=user.id,
        action="stock.threshold",
        entity_type="stock",
        entity_id=line.id,
        old_data=old_data,
        new_data=audit_service.snapshot(StockRead, line),
        ip_address=ip_address,
    )
    db.commit()
    return line


# --- Consultation --------------------------------------------------------------------------------


def get_stock(db: Session, user: User, stock_id: int) -> Stock:
    line = db.get(Stock, stock_id)
    if line is None:
        raise NotFoundError("Ligne de stock introuvable")
    store_access.ensure_store_access(user, line.store_id)
    return line


def list_stocks(db: Session, user: User, filters: StockFilters) -> PageResult[Stock]:
    store_id = store_access.visible_store_id(user, filters.store_id)
    return stock_repository.list_stocks(db, filters.model_copy(update={"store_id": store_id}))


def list_store_stocks(db: Session, user: User, store_id: int, filters: StockFilters) -> PageResult[Stock]:
    store_access.ensure_store_access(user, store_id)
    store_access.get_store(db, store_id)
    return stock_repository.list_stocks(db, filters.model_copy(update={"store_id": store_id}))


def list_low_stock(db: Session, user: User, filters: StockAlertFilters) -> PageResult[Stock]:
    store_id = store_access.visible_store_id(user, filters.store_id)
    return stock_repository.list_alerts(
        db, Stock.low_stock, store_id, filters.search, filters.page, filters.page_size
    )


def list_out_of_stock(db: Session, user: User, filters: StockAlertFilters) -> PageResult[Stock]:
    store_id = store_access.visible_store_id(user, filters.store_id)
    return stock_repository.list_alerts(
        db, Stock.out_of_stock, store_id, filters.search, filters.page, filters.page_size
    )


def list_movements(db: Session, user: User, filters: StockMovementFilters) -> PageResult[StockMovement]:
    store_id = store_access.visible_store_id(user, filters.store_id)
    return stock_repository.list_movements(db, filters.model_copy(update={"store_id": store_id}))


def get_movement(db: Session, user: User, movement_id: int) -> StockMovement:
    movement = db.get(StockMovement, movement_id)
    if movement is None:
        raise NotFoundError("Mouvement de stock introuvable")
    store_access.ensure_store_access(user, movement.store_id)
    return movement
