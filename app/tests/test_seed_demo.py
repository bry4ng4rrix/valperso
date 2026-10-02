from sqlalchemy import func, select

from app.core.config import settings
from app.models import Product, Store, User
from app.seed_demo import run_demo_seed


def count(db, model) -> int:
    return db.scalar(select(func.count()).select_from(model))


def test_demo_seed_creates_accounts_stores_and_products_once(client, db, monkeypatch):
    monkeypatch.setattr(settings, "DEMO_PASSWORD", "testest")

    run_demo_seed(db)
    counts = (count(db, User), count(db, Store), count(db, Product))
    run_demo_seed(db)  # idempotent

    assert (count(db, User), count(db, Store), count(db, Product)) == counts
    for login in ("valenciaraza@local.mg", "antsa@local.mg", "vendeur1@local.mg", "vendeur2", "VENDEUR3"):
        response = client.post("/api/v1/auth/login", json={"username": login, "password": "testest"})
        assert response.status_code == 200, login

    token = client.post("/api/v1/auth/login", json={"username": "vendeur1", "password": "testest"}).json()
    me = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token['access_token']}"}).json()
    assert me["role"]["name"] == "VENDEUR" and me["store"]["name"] == "h109"
    local_stock = db.scalars(select(Product).where(Product.reference == "ACC-001")).one().stocks
    assert [(line.store.is_central, line.quantity) for line in local_stock] == [(True, 30)]
