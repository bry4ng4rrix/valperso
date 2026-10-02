from datetime import date, timedelta
from typing import Any

from app.models import Customer, Product

CUSTOMER = {"first_name": "Jean", "last_name": "Rakoto", "phone": "0341234567"}
FULL_CARD_PAYMENT = {"method": "CARD"}
_DEFAULT = object()


def due_date(days: int = 15) -> str:
    return (date.today() + timedelta(days=days)).isoformat()


def sale_payload(
    *lines: tuple[Product, int],
    customer: Customer | dict | None = None,
    payment: Any = _DEFAULT,
    **fields: Any,
) -> dict[str, Any]:
    """Corps d'une requête POST /sales.

    Par défaut : client Jean Rakoto et paiement complet par carte. `payment=None` : aucun paiement
    (vente à crédit).
    """
    body: dict[str, Any] = {
        "items": [{"product_id": product.id, "quantity": quantity} for product, quantity in lines],
        **fields,
    }
    if payment is _DEFAULT:
        body["payment"] = FULL_CARD_PAYMENT
    elif payment is not None:
        body["payment"] = payment
    if isinstance(customer, Customer):
        body["customer_id"] = customer.id
    else:
        body["customer"] = customer or CUSTOMER
    return body
