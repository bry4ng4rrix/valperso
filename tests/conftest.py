"""Configuration des tests.

- Une base PostgreSQL dédiée (`<base>_test`, ou TEST_DATABASE_URL) est recréée au début de la
  session avec les migrations Alembic : les tests vérifient donc aussi les migrations.
- Chaque test s'exécute dans une transaction annulée à la fin : les tests sont indépendants.
  Les `db.commit()` des services deviennent des SAVEPOINT grâce à join_transaction_mode.
"""

import os
from collections.abc import Iterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import Engine, create_engine, text
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.main import app
from app.seed import seed_default_store, seed_permissions, seed_roles
from tests.factories import Factory

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _test_database_url() -> URL:
    if os.environ.get("TEST_DATABASE_URL"):
        return make_url(os.environ["TEST_DATABASE_URL"])
    url = make_url(settings.DATABASE_URL)
    return url.set(database=f"{url.database}_test")


def _create_database_if_missing(url: URL) -> None:
    maintenance = create_engine(url.set(database="postgres"), isolation_level="AUTOCOMMIT")
    with maintenance.connect() as connection:
        exists = connection.scalar(
            text("SELECT 1 FROM pg_database WHERE datname = :name"), {"name": url.database}
        )
        if not exists:
            connection.execute(text(f'CREATE DATABASE "{url.database}"'))
    maintenance.dispose()


def _run_migrations(engine: Engine) -> None:
    alembic_config = Config()
    alembic_config.set_main_option("script_location", str(PROJECT_ROOT / "alembic"))
    with engine.begin() as connection:
        connection.execute(text("DROP SCHEMA public CASCADE"))
        connection.execute(text("CREATE SCHEMA public"))
        alembic_config.attributes["connection"] = connection
        command.upgrade(alembic_config, "head")


@pytest.fixture(scope="session")
def engine() -> Iterator[Engine]:
    url = _test_database_url()
    _create_database_if_missing(url)
    engine = create_engine(url)
    _run_migrations(engine)
    with Session(engine) as session:
        seed_roles(session, seed_permissions(session))
        seed_default_store(session)
        session.commit()
    yield engine
    engine.dispose()


@pytest.fixture
def db(engine: Engine) -> Iterator[Session]:
    connection = engine.connect()
    transaction = connection.begin()
    session = Session(bind=connection, join_transaction_mode="create_savepoint")
    yield session
    session.close()
    transaction.rollback()
    connection.close()


@pytest.fixture
def client(db: Session) -> Iterator[TestClient]:
    def override_get_db() -> Iterator[Session]:
        try:
            yield db
        except Exception:
            db.rollback()
            raise

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def factory(db: Session) -> Factory:
    return Factory(db)
