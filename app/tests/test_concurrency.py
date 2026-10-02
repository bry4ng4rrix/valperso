"""Opérations simultanées réelles (plusieurs connexions PostgreSQL en parallèle).

Le verrouillage SELECT ... FOR UPDATE garantit qu'on ne retire jamais plus que le stock disponible.
Ces tests valident de vraies transactions : ils nettoient leurs données à la fin.
"""

import threading
from collections.abc import Callable, Iterator

import pytest
from sqlalchemy import Engine, func, select, text
from sqlalchemy.orm import Session, sessionmaker

from app.core.exceptions import InsufficientStock
from app.models import Sale, Stock, StockTransfer, User
from app.schemas.sale import SaleCreate
from app.schemas.stock_transfer import StockTransferCreate
from app.services import sale_service, stock_transfer_service
from app.tests.factories import Factory


@pytest.fixture
def session_factory(engine: Engine) -> Iterator[sessionmaker[Session]]:
    with Session(engine) as session:
        central_id = Factory(session).central_store().id
    yield sessionmaker(bind=engine)
    with engine.begin() as connection:
        # CASCADE vide aussi stocks, ventes, paiements, mouvements, transferts... Le Stock Local est recréé.
        connection.execute(text("TRUNCATE stores, users, categories, products, customers, audit_logs CASCADE"))
        connection.execute(
            text("INSERT INTO stores (id, name, is_central) VALUES (:id, 'STOCK LOCAL', true)"), {"id": central_id}
        )


def run_in_parallel(session_factory, user_ids: list[int], operation: Callable[[Session, User], None]) -> list[str]:
    """Lance `operation` en même temps dans plusieurs threads (une session chacun)."""
    barrier = threading.Barrier(len(user_ids))
    results: list[str] = []

    def worker(user_id: int) -> None:
        with session_factory() as session:
            user = session.get(User, user_id)
            barrier.wait()
            try:
                operation(session, user)
                results.append("ok")
            except InsufficientStock:
                session.rollback()
                results.append("refused")

    threads = [threading.Thread(target=worker, args=(user_id,)) for user_id in user_ids]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return sorted(results)


def test_two_simultaneous_transfers_of_4_with_stock_5(session_factory):
    with session_factory() as session:
        factory = Factory(session)
        destination = factory.store()
        product = factory.product(stock=5)
        admin_ids = [factory.admin().id, factory.admin().id]
        data = StockTransferCreate(
            destination_store_id=destination.id, items=[{"product_id": product.id, "quantity": 4}]
        )

    results = run_in_parallel(
        session_factory, admin_ids, lambda session, user: stock_transfer_service.create_transfer(session, user, data)
    )

    assert results == ["ok", "refused"]
    with session_factory() as session:
        quantities = dict(
            session.execute(select(Stock.store_id, Stock.quantity).where(Stock.product_id == product.id)).all()
        )
        assert quantities[destination.id] == 4 and sum(quantities.values()) == 5  # jamais négatif, total inchangé
        assert session.scalar(select(func.count()).select_from(StockTransfer)) == 1


def test_simultaneous_sales_never_oversell(session_factory):
    with session_factory() as session:
        factory = Factory(session)
        product = factory.product(stock=3)
        admin_ids = [factory.admin().id for _ in range(6)]
        data = SaleCreate.model_validate(
            {
                "items": [{"product_id": product.id, "quantity": 1}],
                "customer": {"first_name": "Jean", "last_name": "Rakoto"},
                "payment": {"method": "CARD"},
            }
        )

    results = run_in_parallel(
        session_factory, admin_ids, lambda session, user: sale_service.create_sale(session, user, data)
    )

    assert results == ["ok"] * 3 + ["refused"] * 3
    with session_factory() as session:
        assert session.scalar(select(func.count()).select_from(Sale)) == 3
        assert session.scalar(select(func.sum(Stock.quantity)).where(Stock.product_id == product.id)) == 0
