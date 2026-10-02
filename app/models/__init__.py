"""Import de tous les modèles : Alembic et les relations SQLAlchemy ont besoin qu'ils soient chargés."""

from app.models.audit import AuditLog
from app.models.base import Base
from app.models.cash import CashRegister, CashTransaction
from app.models.category import Category
from app.models.chat import Conversation, ConversationMember, Message
from app.models.customer import Customer
from app.models.payment import Payment
from app.models.permission import Permission
from app.models.product import Product
from app.models.role import Role, role_permissions
from app.models.sale import Sale, SaleItem, invoice_number_sequence
from app.models.stock import Stock
from app.models.stock_movement import StockMovement
from app.models.stock_transfer import StockTransfer, StockTransferItem, transfer_number_sequence
from app.models.store import Store
from app.models.user import User

__all__ = [
    "AuditLog",
    "Base",
    "CashRegister",
    "CashTransaction",
    "Category",
    "Conversation",
    "ConversationMember",
    "Customer",
    "Message",
    "Payment",
    "Permission",
    "Product",
    "Role",
    "Sale",
    "SaleItem",
    "Stock",
    "StockMovement",
    "StockTransfer",
    "StockTransferItem",
    "Store",
    "User",
    "invoice_number_sequence",
    "role_permissions",
    "transfer_number_sequence",
]
