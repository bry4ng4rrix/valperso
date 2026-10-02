from pydantic import BaseModel, Field

from app.schemas.common import InputModel


class LoginRequest(InputModel):
    username: str = Field(
        min_length=1, max_length=255, description="Nom d'utilisateur ou email", examples=["admin"]
    )
    password: str = Field(min_length=1, max_length=128, examples=["MotDePasse123"])


class RefreshRequest(InputModel):
    refresh_token: str = Field(min_length=1)


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = Field(description="Durée de validité de l'access token, en secondes")
