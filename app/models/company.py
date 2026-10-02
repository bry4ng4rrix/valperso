from typing import TYPE_CHECKING

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, CreatedAtMixin, TimestampMixin, UpperCaseString

if TYPE_CHECKING:
    from app.models.sale import Sale

COMPANY_ID = 1


class CompanyInformation(TimestampMixin, Base):
    """Informations de la société affichées sur les factures.

    Une seule ligne (id = 1), modifiable par l'ADMIN.

    Évolutions possibles sans casser l'existant : website, tax_number, registration_number.
    """

    __tablename__ = "company_information"
    __table_args__ = (sa.CheckConstraint(f"id = {COMPANY_ID}", name="single_row"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(UpperCaseString(150))
    # URL ou chemin du logo : l'image elle-même n'est pas stockée dans PostgreSQL.
    logo_url: Mapped[str | None] = mapped_column(sa.String(500))
    phone: Mapped[str | None] = mapped_column(sa.String(30))
    email: Mapped[str | None] = mapped_column(sa.String(255))
    address: Mapped[str | None] = mapped_column(UpperCaseString(255))
    city: Mapped[str | None] = mapped_column(UpperCaseString(100))


class InvoiceCompanySnapshot(CreatedAtMixin, Base):
    """Copie des informations de la société et du magasin au moment de la vente.

    Une facture ancienne affiche toujours ces valeurs, même si l'ADMIN modifie ensuite
    le nom, le logo ou l'adresse de la société, ou renomme le magasin.
    """

    __tablename__ = "invoice_company_snapshots"

    id: Mapped[int] = mapped_column(primary_key=True)
    sale_id: Mapped[int] = mapped_column(sa.ForeignKey("sales.id", ondelete="CASCADE"), unique=True)
    company_name: Mapped[str] = mapped_column(UpperCaseString(150))
    logo_url: Mapped[str | None] = mapped_column(sa.String(500))
    phone: Mapped[str | None] = mapped_column(sa.String(30))
    email: Mapped[str | None] = mapped_column(sa.String(255))
    address: Mapped[str | None] = mapped_column(UpperCaseString(255))
    city: Mapped[str | None] = mapped_column(UpperCaseString(100))
    store_name: Mapped[str] = mapped_column(UpperCaseString(150))
    store_address: Mapped[str | None] = mapped_column(UpperCaseString(255))
    store_phone: Mapped[str | None] = mapped_column(sa.String(30))

    sale: Mapped["Sale"] = relationship(back_populates="company_snapshot")
