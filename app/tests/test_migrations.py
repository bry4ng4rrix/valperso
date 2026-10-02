from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import Engine, inspect

from app.models import Base


def test_models_match_migrations(engine: Engine):
    """La base créée par les migrations correspond exactement aux modèles SQLAlchemy."""
    with engine.connect() as connection:
        context = MigrationContext.configure(connection, opts={"compare_type": True})
        differences = compare_metadata(context, Base.metadata)
    assert differences == []


def test_product_reference_and_name_are_not_unique(engine: Engine):
    inspector = inspect(engine)
    unique_columns = [
        constraint["column_names"] for constraint in inspector.get_unique_constraints("products")
    ]
    unique_indexes = [index["column_names"] for index in inspector.get_indexes("products") if index["unique"]]
    assert unique_columns == [] and unique_indexes == []


def test_one_stock_line_per_product_and_store(engine: Engine):
    constraints = [c["column_names"] for c in inspect(engine).get_unique_constraints("stocks")]
    assert constraints == [["product_id", "store_id"]]
