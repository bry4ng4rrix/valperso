LIKE_ESCAPE_CHAR = "\\"


def contains_pattern(term: str) -> str:
    """Motif LIKE « contient » ; les caractères spéciaux % et _ saisis par l'utilisateur sont échappés."""
    escaped = (
        term.replace(LIKE_ESCAPE_CHAR, LIKE_ESCAPE_CHAR * 2)
        .replace("%", f"{LIKE_ESCAPE_CHAR}%")
        .replace("_", f"{LIKE_ESCAPE_CHAR}_")
    )
    return f"%{escaped}%"


def display_text(value: str) -> str:
    """Texte tel qu'affiché à l'utilisateur : stocké en MAJUSCULES, affiché en minuscules."""
    return value.lower()
