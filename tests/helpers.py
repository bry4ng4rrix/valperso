from typing import Any

from app.models import Product


def sale_payload(*lines: tuple[Product, int], method: str = "MOBILE_MONEY", **fields: Any) -> dict[str, Any]:
    """Corps d'une requête POST /sales. Par défaut payé en MOBILE_MONEY (pas besoin de caisse)."""
    return {
        "items": [{"product_id": product.id, "quantity": quantity} for product, quantity in lines],
        "payment": {"method": method},
        **fields,
    }
