/// Messages compréhensibles pour les erreurs renvoyées par l'API.
///
/// Les erreurs métier du backend (stock insuffisant, remise invalide...) ont déjà un message
/// précis en français : il est conservé. Les erreurs techniques reçoivent un message générique.
abstract final class ErrorMessages {
  static const network = "Impossible de joindre le serveur. Vérifiez votre connexion et l'adresse de l'API.";
  static const timeout = 'Le serveur met trop de temps à répondre. Réessayez.';
  static const server = 'Le serveur a rencontré une erreur. Réessayez plus tard.';
  static const unknown = 'Une erreur inattendue est survenue.';
  static const loadFailed = 'Impossible de charger les données.';

  /// Message par défaut quand le backend n'en fournit pas d'exploitable.
  static const byCode = <String, String>{
    'INSUFFICIENT_STOCK': 'Stock insuffisant pour ce produit.',
    'INVALID_SELLING_PRICE': 'Le prix de vente doit être supérieur ou égal au prix de stock.',
    'PERMISSION_DENIED': "Vous n'avez pas l'autorisation d'effectuer cette action.",
    'INVALID_STORE_ACCESS': "Vous n'avez pas accès à ce magasin.",
    'INVALID_PAYMENT': 'Le montant du paiement est invalide.',
    'PAYMENT_ALREADY_COMPLETED': 'Cette vente est déjà entièrement payée.',
    'INVALID_DISCOUNT': 'La remise est invalide.',
    'DISCOUNT_NOT_ALLOWED': "Vous n'avez pas l'autorisation d'appliquer une remise.",
    'CASH_REGISTER_CLOSED': 'Aucune caisse ouverte pour ce magasin.',
    'SALE_ALREADY_CANCELLED': 'Cette vente est déjà annulée.',
    'INACTIVE_PRODUCT': 'Ce produit est désactivé.',
    'INACTIVE_STORE': 'Ce magasin est désactivé.',
    'INVALID_TRANSFER': 'Transfert invalide.',
    'NOT_AUTHENTICATED': 'Votre session a expiré. Reconnectez-vous.',
    'TOKEN_EXPIRED': 'Votre session a expiré. Reconnectez-vous.',
    'TOKEN_REVOKED': 'Votre session a expiré. Reconnectez-vous.',
    'INVALID_CREDENTIALS': "Nom d'utilisateur ou mot de passe incorrect.",
    'ACCOUNT_DISABLED': 'Ce compte est désactivé.',
    'VALIDATION_ERROR': 'Certaines informations sont invalides.',
    'CONFLICT': 'Cette donnée existe déjà.',
    'INTEGRITY_ERROR': 'Opération refusée : conflit avec des données existantes.',
    'HTTP_404': 'Élément introuvable.',
    'NOT_FOUND': 'Élément introuvable.',
  };

  /// Traduit les messages de validation (anglais) produits par le backend pour un champ.
  static String field(String message) {
    final rules = <RegExp, String Function(Match)>{
      RegExp(r'^Value error, (.*)$'): (m) => m[1]!,
      RegExp(r'^Field required$'): (_) => 'Champ obligatoire.',
      RegExp(r'^String should have at least (\d+) characters?$'): (m) => '${m[1]} caractères minimum.',
      RegExp(r'^String should have at most (\d+) characters?$'): (m) => '${m[1]} caractères maximum.',
      RegExp(r'^Input should be greater than or equal to (.+)$'): (m) => 'Doit être supérieur ou égal à ${m[1]}.',
      RegExp(r'^Input should be greater than (.+)$'): (m) => 'Doit être supérieur à ${m[1]}.',
      RegExp(r'^Input should be less than or equal to (.+)$'): (m) => 'Doit être inférieur ou égal à ${m[1]}.',
      RegExp(r'^String should match pattern'): (_) => 'Format invalide.',
      RegExp(r'not a valid email'): (_) => 'Adresse email invalide.',
      RegExp(r'^Input should be a valid (number|integer)'): (_) => 'Nombre invalide.',
      RegExp(r'^Decimal input should have no more than (\d+) decimal places?'): (m) => '${m[1]} décimales maximum.',
    };
    for (final entry in rules.entries) {
      final match = entry.key.firstMatch(message);
      if (match != null) return entry.value(match);
    }
    return message;
  }
}
