"""Photos des produits : envoi, service du fichier sous /media, suppression, contrôles."""

import pytest

from app.core.config import settings
from app.main import app
from app.services import product_image_service

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


@pytest.fixture(autouse=True)
def media_dir(tmp_path, monkeypatch):
    """Les fichiers des tests vont dans un dossier temporaire, servi aussi sous /media."""
    monkeypatch.setattr(settings, "MEDIA_ROOT", str(tmp_path))
    mount = next(route.app for route in app.routes if getattr(route, "path", None) == "/media")
    monkeypatch.setattr(mount, "all_directories", [tmp_path])
    return tmp_path


def upload(client, headers, product_id, content, name="photo.png"):
    return client.post(
        f"/api/v1/products/{product_id}/images",
        headers=headers,
        files={"file": (name, content, "image/png")},
    )


def test_add_photos_then_serve_them(client, factory, admin_headers, media_dir):
    product = factory.product(name="Abaya")

    first = upload(client, admin_headers, product.id, PNG)
    second = upload(client, admin_headers, product.id, JPEG, name="photo.jpg")

    assert first.status_code == second.status_code == 201
    body = second.json()
    urls = [image["url"] for image in body["images"]]
    assert len(urls) == 2 and urls[0].endswith(".png") and urls[1].endswith(".jpg")
    assert body["image_url"] == urls[0], "la première photo est la principale"
    assert all(url.startswith("/media/products/") for url in urls)
    assert len(list((media_dir / "products").iterdir())) == 2

    served = client.get(urls[0])
    assert served.status_code == 200 and served.content == PNG

    listed = client.get("/api/v1/products", headers=admin_headers).json()["items"]
    assert next(p for p in listed if p["id"] == product.id)["image_url"] == urls[0]
    stock = client.get("/api/v1/stock", headers=admin_headers, params={"product_id": product.id}).json()
    assert stock["items"][0]["product"]["image_url"] == urls[0], "visible dans le catalogue de vente"


def test_file_name_from_the_client_is_never_used(client, factory, admin_headers, media_dir):
    product = factory.product()
    body = upload(client, admin_headers, product.id, PNG, name="../../etc/passwd.png").json()
    assert "passwd" not in body["images"][0]["url"]
    assert [path.parent for path in media_dir.rglob("*") if path.is_file()] == [media_dir / "products"]


@pytest.mark.parametrize(
    ("content", "message"),
    [
        (b"GIF89a" + b"\x00" * 10, "JPEG, PNG ou WebP"),
        (b"%PDF-1.7", "JPEG, PNG ou WebP"),
        (b"", "vide"),
        (PNG + b"\x00" * product_image_service.MAX_IMAGE_BYTES, "5 Mo"),
    ],
)
def test_invalid_files_are_refused(client, factory, admin_headers, media_dir, content, message):
    product = factory.product()
    response = upload(client, admin_headers, product.id, content)
    assert response.status_code == 400 and response.json()["code"] == "INVALID_IMAGE"
    assert message in response.json()["detail"]
    assert not (media_dir / "products").exists() or not any((media_dir / "products").iterdir())


def test_at_most_ten_photos(client, factory, admin_headers, monkeypatch):
    monkeypatch.setattr(product_image_service, "MAX_IMAGES_PER_PRODUCT", 2)
    product = factory.product()
    upload(client, admin_headers, product.id, PNG)
    upload(client, admin_headers, product.id, PNG)
    response = upload(client, admin_headers, product.id, PNG)
    assert response.status_code == 400 and "2 photos maximum" in response.json()["detail"]


def test_vendeur_cannot_add_photos_by_default(client, factory):
    shop = factory.store()
    product = factory.product(stock=1, store=shop)
    response = upload(client, factory.headers(factory.vendeur(shop)), product.id, PNG)
    assert response.status_code == 403


def test_delete_photo_removes_the_file(client, factory, admin_headers, media_dir):
    product = factory.product()
    body = upload(client, admin_headers, product.id, PNG).json()
    image = body["images"][0]

    response = client.delete(f"/api/v1/products/{product.id}/images/{image['id']}", headers=admin_headers)
    again = client.delete(f"/api/v1/products/{product.id}/images/{image['id']}", headers=admin_headers)

    assert response.status_code == 200 and response.json()["images"] == []
    assert response.json()["image_url"] is None
    assert again.status_code == 404
    assert not any((media_dir / "products").iterdir())
    assert client.get(image["url"]).status_code == 404
