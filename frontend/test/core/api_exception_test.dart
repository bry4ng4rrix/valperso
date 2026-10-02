import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/core/api/api_exception.dart';
import 'package:valmag/core/errors/error_messages.dart';

void main() {
  group('ApiException.fromResponse', () {
    test('garde le message métier du backend', () {
      final error = ApiException.fromResponse(400, {
        'detail': 'Stock insuffisant pour STYLO dans H109 (disponible : 2, demandé : 5)',
        'code': 'INSUFFICIENT_STOCK',
      });
      expect(error.code, 'INSUFFICIENT_STOCK');
      expect(error.message, contains('Stock insuffisant'));
      expect(error.statusCode, 400);
    });

    test('erreur de validation : message général et erreurs par champ traduites', () {
      final error = ApiException.fromResponse(422, {
        'detail': 'Validation error',
        'code': 'VALIDATION_ERROR',
        'errors': [
          {'field': 'body.name', 'message': 'String should have at least 2 characters'},
          {'field': 'body.selling_price', 'message': 'Value error, Le prix de vente doit être >= au prix de stock'},
          {'field': 'body.reference', 'message': 'Field required'},
        ],
      });
      expect(error.message, ErrorMessages.byCode['VALIDATION_ERROR']);
      expect(error.fieldError('name'), '2 caractères minimum.');
      expect(error.fieldError('selling_price'), 'Le prix de vente doit être >= au prix de stock');
      expect(error.fieldError('reference'), 'Champ obligatoire.');
    });

    test('code HTTP sans détail exploitable : message générique en français', () {
      final error = ApiException.fromResponse(404, null);
      expect(error.isNotFound, isTrue);
      expect(error.message, 'Élément introuvable.');
    });

    test('statuts 401 / 403', () {
      expect(ApiException.fromResponse(401, {'detail': 'x', 'code': 'TOKEN_EXPIRED'}).isUnauthorized, isTrue);
      expect(ApiException.fromResponse(403, {'detail': 'Refusé', 'code': 'PERMISSION_DENIED'}).isForbidden, isTrue);
    });
  });

  group('ApiException.fromDio', () {
    test('serveur injoignable', () {
      final error = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(error.isNetwork, isTrue);
      expect(error.message, ErrorMessages.network);
    });

    test('délai dépassé', () {
      final error = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(error.isNetwork, isTrue);
      expect(error.message, ErrorMessages.timeout);
    });
  });

  test('ErrorMessages.field traduit les messages Pydantic', () {
    expect(ErrorMessages.field('Input should be greater than 0'), 'Doit être supérieur à 0.');
    expect(ErrorMessages.field('String should match pattern \'^x\$\''), 'Format invalide.');
    expect(ErrorMessages.field('message inconnu'), 'message inconnu');
  });
}
