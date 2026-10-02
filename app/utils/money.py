from decimal import ROUND_HALF_UP, Decimal

CENT = Decimal("0.01")


def round_money(value: Decimal) -> Decimal:
    """Arrondit un montant au centime (arrondi commercial : 0,005 -> 0,01)."""
    return value.quantize(CENT, rounding=ROUND_HALF_UP)
