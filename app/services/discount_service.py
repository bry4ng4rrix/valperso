"""Calcul et contrôle des remises appliquées à une vente."""

from decimal import Decimal

from app.core.exceptions import InvalidDiscount, PermissionDenied
from app.core.permissions import PermissionCode, has_permission
from app.models import User
from app.models.enums import DiscountType
from app.utils.money import round_money


def ensure_discount_allowed(user: User, discount_type: DiscountType) -> None:
    if discount_type != DiscountType.NONE and not has_permission(user, PermissionCode.SALE_DISCOUNT):
        raise PermissionDenied(
            "Vous n'avez pas la permission d'appliquer une remise (sale.discount)",
            code="DISCOUNT_NOT_ALLOWED",
        )


def compute_discount(subtotal: Decimal, discount_type: DiscountType, discount_value: Decimal) -> Decimal:
    """Montant de la remise pour un sous-total donné.

    PERCENTAGE : 10 sur 100 000 -> 10 000. FIXED : 15 000 sur 100 000 -> 15 000.
    """
    if discount_value < 0:
        raise InvalidDiscount("La remise ne peut pas être négative")

    if discount_type == DiscountType.NONE:
        return Decimal("0.00")

    if discount_type == DiscountType.PERCENTAGE:
        if discount_value > 100:
            raise InvalidDiscount("Une remise en pourcentage ne peut pas dépasser 100")
        return round_money(subtotal * discount_value / 100)

    if discount_value > subtotal:
        raise InvalidDiscount(f"La remise ({discount_value}) ne peut pas dépasser le sous-total ({subtotal})")
    return round_money(discount_value)
