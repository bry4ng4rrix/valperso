"""Informations de la société (une seule configuration), utilisées en en-tête des factures."""

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError
from app.models import COMPANY_ID, CompanyInformation, InvoiceCompanySnapshot, Store, User
from app.schemas.company import CompanyRead, CompanyUpdate
from app.services import audit_service


def get_company(db: Session) -> CompanyInformation:
    company = db.get(CompanyInformation, COMPANY_ID)
    if company is None:
        raise BusinessRuleError(
            "Les informations de la société ne sont pas configurées : lancez le seed (python -m app.seed)"
        )
    return company


def update_company(
    db: Session, user: User, data: CompanyUpdate, ip_address: str | None = None
) -> CompanyInformation:
    """Modifie les informations de la société. Les factures déjà émises gardent leur propre copie."""
    company = get_company(db)
    old_data = audit_service.snapshot(CompanyRead, company)
    for field, value in data.model_dump().items():
        setattr(company, field, value)
    db.flush()
    audit_service.record(
        db,
        user_id=user.id,
        action="company.update",
        entity_type="company",
        entity_id=company.id,
        old_data=old_data,
        new_data=audit_service.snapshot(CompanyRead, company),
        ip_address=ip_address,
    )
    db.commit()
    return company


def snapshot_for_invoice(db: Session, store: Store) -> InvoiceCompanySnapshot:
    """Copie des informations actuelles de la société et du magasin, figée dans la facture d'une vente."""
    company = get_company(db)
    return InvoiceCompanySnapshot(
        company_name=company.name,
        logo_url=company.logo_url,
        phone=company.phone,
        email=company.email,
        address=company.address,
        city=company.city,
        store_name=store.name,
        store_address=store.address,
        store_phone=store.phone,
    )
