"""Ventes simultanées : le verrouillage (SELECT ... FOR UPDATE) empêche de vendre plus que le stock.

Ce test utilise de vraies transactions validées (plusieurs connexions en parallèle) :
il nettoie ses données à la fin au lieu de s'appuyer sur le rollback des autres tests.
"""

import threading
from collections.abc import Iterator

import pytest
from sqlalchemy import Engine, func, select, text
from sqlalchemy.orm import Session, sessionmaker

from app.core.exceptions import InsufficientStockError
from app.core.permissions import RoleName
from app.models import Sale, StockMovement, User
from app.schemas.sale import SaleCreate
from app.services import sale_service
from tests.factories import Factory

DATA_TABLES = "stores, users, categories, products, store_stocks, audit_logs"


@pytest.fixture
def session_factory(engine: Engine) -> Iterator[sessionmaker[Session]]:
    with Session(engine) as session:
        default_store_id = Factory(session).default_store().id
    yield sessionmaker(bind=engine)
    with engine.begin() as connection:
        # CASCADE vide aussi les ventes, paiements, mouvements... ; le STOCK LOCAL est recréé tel quel.
        connection.execute(text(f"TRUNCATE {DATA_TABLES} CASCADE"))
        connection.execute(
            text("INSERT INTO stores (id, name, is_default) VALUES (:id, 'STOCK LOCAL', true)"),
            {"id": default_store_id},
        )


def test_concurrent_sales_never_oversell(session_factory):
    with session_factory() as session:
        factory = Factory(session)
        product = factory.product(stock=3)
        seller_ids = [factory.user(RoleName.VENDEUR).id for _ in range(6)]
        product_id = product.id

    barrier = threading.Barrier(len(seller_ids))
    results: list[str] = []

    def sell_one_unit(seller_id: int) -> None:
        with session_factory() as session:
            seller = session.get(User, seller_id)
            data = SaleCreate.model_validate(
                {"items": [{"product_id": product_id, "quantity": 1}], "payment": {"method": "CARD"}}
            )
            barrier.wait()
            try:
                sale_service.create_sale(session, seller, data)
                results.append("ok")
            except InsufficientStockError:
                session.rollback()
                results.append("refused")

    threads = [threading.Thread(target=sell_one_unit, args=(seller_id,)) for seller_id in seller_ids]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert sorted(results) == ["ok"] * 3 + ["refused"] * 3
    with session_factory() as session:
        assert session.scalar(select(func.count()).select_from(Sale)) == 3
        assert session.scalar(select(func.sum(StockMovement.quantity))) == -3
        factory = Factory(session)
        assert factory.store_quantity(factory.default_store(), session.get(type(product), product_id)) == 0
