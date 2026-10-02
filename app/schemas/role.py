from pydantic import Field

from app.schemas.common import DisplayStr, InputModel, OptionalUpperStr, ORMModel


class PermissionRead(ORMModel):
    id: int
    name: str = Field(description="Code technique de la permission, ex. 'sale.create'")
    description: DisplayStr | None


class RoleSummary(ORMModel):
    id: int
    name: str = Field(description="ADMIN ou VENDEUR")


class RoleRead(ORMModel):
    id: int
    name: str
    description: DisplayStr | None
    permissions: list[PermissionRead]


class RoleUpdate(InputModel):
    description: OptionalUpperStr = Field(None, max_length=255)


class RolePermissionsUpdate(InputModel):
    permission_ids: list[int] = Field(description="Liste complète des permissions du rôle (remplace l'existante)")
