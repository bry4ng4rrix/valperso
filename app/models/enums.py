"""Valeurs énumérées du domaine, partagées par les modèles, les schémas et les services."""

from enum import StrEnum


class StockMovementType(StrEnum):
    ENTRY = "ENTRY"
    EXIT = "EXIT"
    SALE = "SALE"
    RETURN = "RETURN"
    ADJUSTMENT = "ADJUSTMENT"
    LOSS = "LOSS"
    TRANSFER_OUT = "TRANSFER_OUT"
    TRANSFER_IN = "TRANSFER_IN"


class TransferStatus(StrEnum):
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"


class SaleStatus(StrEnum):
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"


class PaymentStatus(StrEnum):
    UNPAID = "UNPAID"
    PARTIAL = "PARTIAL"
    PAID = "PAID"


class DiscountType(StrEnum):
    NONE = "NONE"
    PERCENTAGE = "PERCENTAGE"
    FIXED = "FIXED"


class PaymentMethod(StrEnum):
    """Mode de paiement.

    CREDIT signifie « vente à crédit » : rien n'est encaissé, le montant reste dû. Il n'est donc
    jamais enregistré comme paiement ; seuls les encaissements réels créent une ligne Payment.
    Un futur mode MIXED se traduira par plusieurs paiements (un par mode) sur la même vente.
    """

    CASH = "CASH"
    MOBILE_MONEY = "MOBILE_MONEY"
    CARD = "CARD"
    BANK_TRANSFER = "BANK_TRANSFER"
    CREDIT = "CREDIT"


class ConversationType(StrEnum):
    PRIVATE = "PRIVATE"
    GROUP = "GROUP"
