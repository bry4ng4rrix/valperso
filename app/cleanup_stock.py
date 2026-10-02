"""Retire d'un magasin les lignes à 0 des produits qui ont été déplacés ailleurs.

Usage :
    python -m app.cleanup_stock            # simulation : affiche le nombre de lignes concernées
    python -m app.cleanup_stock --apply    # supprime ces lignes (Stock Local par défaut)
    python -m app.cleanup_stock --store-id 3 --apply

Une ligne n'est retirée que si le produit a du stock dans au moins un autre magasin : un produit
épuisé partout reste visible comme rupture. Les transferts appliquent désormais cette règle
automatiquement (un produit transféré en totalité quitte le magasin d'origine).
"""

import argparse
import logging

from sqlalchemy import and_, delete, exists, select
from sqlalchemy.orm import Session, aliased

from app.core.database import SessionLocal
from app.models import Stock
from app.services import audit_service, store_access

logger = logging.getLogger("cleanup_stock")


def moved_out_lines(db: Session, store_id: int) -> list[Stock]:
    other = aliased(Stock)
    stocked_elsewhere = exists().where(
        and_(other.product_id == Stock.product_id, other.store_id != store_id, other.quantity > 0)
    )
    stmt = select(Stock).where(Stock.store_id == store_id, Stock.quantity == 0, stocked_elsewhere)
    return list(db.scalars(stmt.order_by(Stock.id)))


def remove_moved_out_lines(db: Session, store_id: int) -> int:
    lines = moved_out_lines(db, store_id)
    if not lines:
        return 0
    product_ids = [line.product_id for line in lines]
    db.execute(delete(Stock).where(Stock.id.in_([line.id for line in lines])))
    audit_service.record(
        db,
        user_id=None,
        action="stock.cleanup_moved",
        entity_type="store",
        entity_id=store_id,
        old_data={"product_ids": product_ids},
        new_data={"removed_lines": len(lines)},
    )
    db.commit()
    return len(lines)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--store-id", type=int, help="Magasin (Stock Local par défaut)")
    parser.add_argument("--apply", action="store_true", help="Supprimer (sinon : simulation)")
    args = parser.parse_args()
    with SessionLocal() as db:
        store_id = args.store_id or store_access.get_central_store(db).id
        if args.apply:
            logger.info("%d ligne(s) à 0 retirée(s) du magasin %s", remove_moved_out_lines(db, store_id), store_id)
        else:
            count = len(moved_out_lines(db, store_id))
            logger.info("Simulation : %d ligne(s) à 0 seraient retirées du magasin %s", count, store_id)


if __name__ == "__main__":
    main()
