from datetime import date, datetime
from zoneinfo import ZoneInfo

from app.core.config import settings


def local_today() -> date:
    """Date du jour dans le fuseau de l'application (TIMEZONE), pas celui du serveur."""
    return datetime.now(ZoneInfo(settings.TIMEZONE)).date()
