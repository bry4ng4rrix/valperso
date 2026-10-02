from datetime import date

from pydantic import Field

from app.models.enums import PaymentStatus
from app.schemas.common import Money, ORMModel


class SaleInstallmentRead(ORMModel):
    """Échéance et son état, calculé à partir des paiements reçus (dans l'ordre des dates)."""

    due_date: date
    amount: Money
    paid_amount: Money
    remaining_amount: Money
    status: PaymentStatus
    is_overdue: bool = Field(description="Date passée et montant pas encore soldé")
