import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';
import 'cash_models.dart';

class CashRepository {
  CashRepository(this._api);

  final ApiClient _api;

  Future<Paged<CashRegister>> registers(PageQuery query) async =>
      Paged.fromJson(await _api.get('/cash/registers', query: query.toQuery()) as Json, CashRegister.fromJson);

  /// Caisse ouverte du magasin, ou null si aucune caisse n'est ouverte.
  Future<CashRegister?> current({int? storeId}) async {
    try {
      final data = await _api.get('/cash/registers/current', query: {'store_id': ?storeId});
      return CashRegister.fromJson(data as Json);
    } on ApiException catch (error) {
      if (error.isNotFound) return null;
      rethrow;
    }
  }

  /// Horaires automatiques. null si l'API ne les publie pas (ancienne version du serveur).
  Future<CashSchedule?> schedule() async {
    try {
      return CashSchedule.fromJson(await _api.get('/cash/schedule') as Json);
    } on ApiException catch (error) {
      if (error.isNotFound) return null;
      rethrow;
    }
  }

  Future<CashRegister> get(int id) async => CashRegister.fromJson(await _api.get('/cash/registers/$id') as Json);

  Future<CashRegister> open({required double openingAmount, int? storeId}) async => CashRegister.fromJson(
    await _api.post('/cash/registers/open', data: {'store_id': storeId, 'opening_amount': openingAmount}) as Json,
  );

  Future<CashRegister> close(int id, {required double closingAmount}) async => CashRegister.fromJson(
    await _api.post('/cash/registers/$id/close', data: {'closing_amount': closingAmount}) as Json,
  );

  Future<Paged<CashTransaction>> transactions(int registerId, PageQuery query) async => Paged.fromJson(
    await _api.get('/cash/registers/$registerId/transactions', query: query.toQuery()) as Json,
    CashTransaction.fromJson,
  );

  Future<CashTransaction> addTransaction(
    int registerId, {
    required CashTransactionType type,
    required double amount,
    required String reason,
    String? reference,
  }) async => CashTransaction.fromJson(
    await _api.post(
          '/cash/registers/$registerId/transactions',
          data: {'type': type.code, 'amount': amount, 'reason': reason, 'reference': reference},
        )
        as Json,
  );
}
