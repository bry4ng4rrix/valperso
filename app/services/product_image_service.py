"""Photos des produits : fichiers dans MEDIA_ROOT/products (servis sous /media), une ligne par photo.

- Seuls JPEG, PNG et WebP sont acceptés, reconnus à leur contenu (pas au nom ni au type annoncé).
- Le nom du fichier est aléatoire : jamais celui envoyé (pas de chemin imposé par le client).
"""

import uuid
from pathlib import Path

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import InvalidImage, NotFoundError
from app.models import Product, ProductImage, User
from app.services import audit_service
from app.services.product_service import get_product

MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_IMAGES_PER_PRODUCT = 10
PRODUCTS_DIR = "products"


def media_root() -> Path:
    return Path(settings.MEDIA_ROOT)


def image_extension(content: bytes) -> str:
    """Extension d'après les premiers octets du fichier (signature du format). Utilisée aussi pour
    le logo de la société."""
    if content.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if content[:4] == b"RIFF" and content[8:12] == b"WEBP":
        return "webp"
    raise InvalidImage("Format non pris en charge : envoyez une photo JPEG, PNG ou WebP")


def add_image(
    db: Session, user: User, product_id: int, content: bytes, ip_address: str | None = None
) -> Product:
    product = get_product(db, product_id)
    if not content:
        raise InvalidImage("Le fichier est vide")
    if len(content) > MAX_IMAGE_BYTES:
        raise InvalidImage(f"Photo trop lourde : {MAX_IMAGE_BYTES // (1024 * 1024)} Mo maximum")
    if len(product.images) >= MAX_IMAGES_PER_PRODUCT:
        raise InvalidImage(f"{MAX_IMAGES_PER_PRODUCT} photos maximum par produit")

    relative = f"{PRODUCTS_DIR}/{uuid.uuid4().hex}.{image_extension(content)}"
    target = media_root() / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)

    position = db.scalar(
        select(func.coalesce(func.max(ProductImage.position), -1)).where(
            ProductImage.product_id == product.id
        )
    )
    image = ProductImage(product_id=product.id, path=relative, position=position + 1)
    db.add(image)
    try:
        db.flush()
        audit_service.record(
            db,
            user_id=user.id,
            action="product.image_add",
            entity_type="product",
            entity_id=product.id,
            new_data={"image_id": image.id, "url": image.url},
            ip_address=ip_address,
        )
        db.commit()
    except Exception:
        target.unlink(missing_ok=True)  # pas de fichier orphelin si l'enregistrement échoue
        raise
    db.refresh(product)
    return product


def delete_image(
    db: Session, user: User, product_id: int, image_id: int, ip_address: str | None = None
) -> Product:
    product = get_product(db, product_id)
    image = db.get(ProductImage, image_id)
    if image is None or image.product_id != product.id:
        raise NotFoundError("Photo introuvable")
    path, url = image.path, image.url
    db.delete(image)
    audit_service.record(
        db,
        user_id=user.id,
        action="product.image_delete",
        entity_type="product",
        entity_id=product.id,
        old_data={"image_id": image_id, "url": url},
        ip_address=ip_address,
    )
    db.commit()
    (media_root() / path).unlink(missing_ok=True)
    db.refresh(product)
    return product
