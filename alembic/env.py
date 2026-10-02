from logging.config import fileConfig

from alembic import context
from sqlalchemy import Connection, create_engine, pool

from app.core.config import settings
from app.models import Base
from app.models.base import UpperCaseString

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def render_item(type_: str, obj: object, autogen_context: object) -> str | bool:
    """Écrit les types personnalisés comme leur type SQL réel dans les migrations générées.

    UpperCaseString est un simple VARCHAR en base : la migration n'a pas à importer le code de l'application.
    """
    if type_ == "type" and isinstance(obj, UpperCaseString):
        return f"sa.String(length={obj.impl.length})"
    return False


def run_migrations_offline() -> None:
    """Génère le SQL sans se connecter (alembic upgrade head --sql)."""
    context.configure(
        url=settings.DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        render_item=render_item,
    )
    with context.begin_transaction():
        context.run_migrations()


def _run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection, target_metadata=target_metadata, compare_type=True, render_item=render_item
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    # Les tests fournissent leur propre connexion (base de test).
    connection = config.attributes.get("connection")
    if connection is not None:
        _run_migrations(connection)
        return

    engine = create_engine(settings.DATABASE_URL, poolclass=pool.NullPool)
    with engine.connect() as connection:
        _run_migrations(connection)


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
