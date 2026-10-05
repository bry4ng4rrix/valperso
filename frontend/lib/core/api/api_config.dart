import 'package:flutter/foundation.dart';

/// Adresse de l'API.
///
/// Ordre de priorité : valeur enregistrée dans les paramètres de l'application,
/// puis `--dart-define=API_URL=...`, puis une valeur par défaut adaptée à la plateforme
/// (l'émulateur Android voit la machine hôte à l'adresse 10.0.2.2). Dans le navigateur, l'API est
/// servie par le même serveur que la page (nginx transmet /api à l'API) : son adresse est celle du site.
abstract final class ApiConfig {
  static const _fromEnvironment = String.fromEnvironment('API_URL');

  static String get defaultBaseUrl {
    if (_fromEnvironment.isNotEmpty) return _fromEnvironment;
    if (kIsWeb) return Uri.base.origin;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8001';
    return 'http://localhost:8001';
  }

  static const apiPrefix = '/api/v1';
  static const connectTimeout = Duration(seconds: 10);
  static const receiveTimeout = Duration(seconds: 30);

  /// Normalise une adresse saisie : retire les "/" finaux et le préfixe /api/v1 s'il a été collé.
  static String normalize(String url) {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith(apiPrefix)) value = value.substring(0, value.length - apiPrefix.length);
    if (!value.startsWith('http://') && !value.startsWith('https://')) value = 'http://$value';
    return value;
  }
}
