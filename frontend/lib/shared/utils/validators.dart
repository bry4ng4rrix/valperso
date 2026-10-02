import '../../core/utils/formatters.dart';

/// Règles de saisie identiques à celles de l'API, pour afficher l'erreur avant l'envoi.
abstract final class Validators {
  static final _phone = RegExp(r'^\+?[0-9 ().-]{6,30}$');
  static final _reference = RegExp(r'^[A-Za-z0-9._/-]+$');
  static final _username = RegExp(r'^[A-Za-z0-9._-]+$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _logo = RegExp(r'^(https?://|/)\S+$');

  static bool _empty(String? value) => value == null || value.trim().isEmpty;

  static String? required(String? value) => _empty(value) ? 'Champ obligatoire.' : null;

  static String? Function(String?) text({required bool required, int min = 1, int? max}) => (value) {
    if (_empty(value)) return required ? 'Champ obligatoire.' : null;
    final length = value!.trim().length;
    if (length < min) return '$min caractères minimum.';
    if (max != null && length > max) return '$max caractères maximum.';
    return null;
  };

  static String? phone(String? value, {bool required = false}) {
    if (_empty(value)) return required ? 'Le téléphone est obligatoire.' : null;
    return _phone.hasMatch(value!.trim()) ? null : 'Numéro de téléphone invalide (ex. 034 12 345 67).';
  }

  static String? email(String? value) {
    if (_empty(value)) return null;
    return _email.hasMatch(value!.trim()) ? null : 'Adresse email invalide.';
  }

  static String? reference(String? value) {
    if (_empty(value)) return 'La référence est obligatoire.';
    if (value!.trim().length > 50) return '50 caractères maximum.';
    return _reference.hasMatch(value.trim()) ? null : 'Lettres, chiffres et . _ / - uniquement (sans espace).';
  }

  static String? username(String? value) {
    if (_empty(value)) return 'Le nom d\'utilisateur est obligatoire.';
    final text = value!.trim();
    if (text.length < 3) return '3 caractères minimum.';
    if (text.length > 50) return '50 caractères maximum.';
    return _username.hasMatch(text) ? null : 'Lettres, chiffres et . _ - uniquement (sans espace).';
  }

  static String? password(String? value, {bool required = true}) {
    if (value == null || value.isEmpty) return required ? 'Le mot de passe est obligatoire.' : null;
    if (value.length < 8) return '8 caractères minimum.';
    if (value.length > 72) return '72 caractères maximum.';
    return null;
  }

  static String? logoUrl(String? value) {
    if (_empty(value)) return null;
    return _logo.hasMatch(value!.trim()) ? null : 'Adresse web (https://...) ou chemin commençant par /.';
  }

  /// Montant strictement positif.
  static String? positiveAmount(String? value) {
    final amount = parseAmount(value);
    if (amount == null) return 'Saisissez un montant.';
    return amount <= 0 ? 'Le montant doit être supérieur à 0.' : null;
  }
}

/// Texte saisi, sans espaces superflus, ou null s'il est vide.
String? trimOrNull(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
