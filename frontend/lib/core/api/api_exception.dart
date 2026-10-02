import 'package:dio/dio.dart';

import '../errors/error_messages.dart';

/// Erreur d'appel API, déjà traduite en message lisible pour l'utilisateur.
///
/// Le backend renvoie toujours `{"detail": "...", "code": "..."}`, et pour une erreur 422
/// une liste `errors` (champ + message) utilisée pour afficher l'erreur sous chaque champ.
class ApiException implements Exception {
  ApiException({
    required this.message,
    this.code = 'UNKNOWN',
    this.statusCode,
    this.fieldErrors = const {},
  });

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionError:
        return ApiException(message: ErrorMessages.network, code: 'NETWORK');
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(message: ErrorMessages.timeout, code: 'TIMEOUT');
      default:
        break;
    }
    final response = error.response;
    if (response == null) return ApiException(message: ErrorMessages.network, code: 'NETWORK');
    return ApiException.fromResponse(response.statusCode, response.data);
  }

  factory ApiException.fromResponse(int? statusCode, Object? data) {
    if (statusCode != null && statusCode >= 500) {
      return ApiException(message: ErrorMessages.server, code: 'SERVER_ERROR', statusCode: statusCode);
    }
    final body = data is Map ? data : const {};
    final code = '${body['code'] ?? 'HTTP_$statusCode'}';
    final detail = body['detail'] is String ? body['detail'] as String : null;

    final fields = <String, String>{};
    if (body['errors'] is List) {
      for (final item in body['errors'] as List) {
        if (item is! Map) continue;
        final field = '${item['field'] ?? ''}'.split('.').last;
        fields.putIfAbsent(field, () => ErrorMessages.field('${item['message'] ?? ''}'));
      }
    }

    // Les messages métier du backend sont précis et en français : on les garde.
    // Les messages techniques (422 générique, 404...) sont remplacés par un texte clair.
    final useBackendDetail = detail != null && code != 'VALIDATION_ERROR' && !code.startsWith('HTTP_');
    final message = useBackendDetail
        ? detail
        : fields.length == 1
            ? fields.values.first
            : ErrorMessages.byCode[code] ?? detail ?? ErrorMessages.unknown;
    return ApiException(message: message, code: code, statusCode: statusCode, fieldErrors: fields);
  }

  final String message;
  final String code;
  final int? statusCode;

  /// Erreur par champ, ex. {"selling_price": "Le prix de vente doit être ..."}.
  final Map<String, String> fieldErrors;

  bool get isNetwork => code == 'NETWORK' || code == 'TIMEOUT';
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;

  String? fieldError(String field) => fieldErrors[field];

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
