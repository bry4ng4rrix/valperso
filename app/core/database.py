"""Connexion à PostgreSQL et gestion des sessions SQLAlchemy."""

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

engine = create_engine(settings.DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine)


def get_db() -> Iterator[Session]:
    """Dépendance FastAPI : fournit une session par requête HTTP.

    Les services valident explicitement leur travail avec `db.commit()` en fin d'opération.
    Si une exception survient avant ce commit, tout ce qui a été fait pendant la requête
    est annulé (ROLLBACK) : aucune donnée partielle ne reste en base.
    """
    db = SessionLocal()
    try:
        yield db
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
