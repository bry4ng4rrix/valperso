"""Retire d'un magasin les lignes à 0 des produits qui ont été déplacés ailleurs.

Usage :
    python -m app.cleanup_stock                 # simulation : nombre de lignes concernées
    python -m app.cleanup_stock --apply         # produits déplacés : lignes à 0 du Stock Local
    python -m app.cleanup_stock --store-id 3 --apply
    python -m app.cleanup_stock --all --apply   # toutes les lignes à 0 de tous les magasins

Sans --all, une ligne n'est retirée que si le produit a du stock dans un autre magasin (produit
déplacé). Avec --all, toutes les lignes à 0 sont retirées (produits épuisés) : c'est la règle
appliquée automatiquement aux ventes, sorties et transferts (stock_service.apply_stock_change).
Les produits restent dans la base et dans les historiques.
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


def sold_out_lines(db: Session, store_id: int | None = None) -> list[Stock]:
    stmt = select(Stock).where(Stock.quantity == 0)
    if store_id is not None:
        stmt = stmt.where(Stock.store_id == store_id)
    return list(db.scalars(stmt.order_by(Stock.id)))


def remove_moved_out_lines(db: Session, store_id: int) -> int:
    return remove_lines(db, moved_out_lines(db, store_id), store_id)


def remove_lines(db: Session, lines: list[Stock], store_id: int | None) -> int:
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
        old_data={
            "lines": [f"{line.store_id}:{line.product_id}" for line in lines],
            "product_ids": product_ids,
        },
        new_data={"removed_lines": len(lines)},
    )
    db.commit()
    return len(lines)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--store-id", type=int, help="Magasin (Stock Local par défaut, tous avec --all)")
    parser.add_argument("--all", action="store_true", help="Toutes les lignes à 0 (produits épuisés)")
    parser.add_argument("--apply", action="store_true", help="Supprimer (sinon : simulation)")
    args = parser.parse_args()
    with SessionLocal() as db:
        if args.all:
            store_id = args.store_id
            lines = sold_out_lines(db, store_id)
        else:
            store_id = args.store_id or store_access.get_central_store(db).id
            lines = moved_out_lines(db, store_id)
        where = f"du magasin {store_id}" if store_id else "de tous les magasins"
        if args.apply:
            logger.info("%d ligne(s) à 0 retirée(s) %s", remove_lines(db, lines, store_id), where)
        else:
            logger.info("Simulation : %d ligne(s) à 0 seraient retirées %s", len(lines), where)


if __name__ == "__main__":
    main()
