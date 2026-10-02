import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';
import 'payment_models.dart';

class PaymentsRepository {
  PaymentsRepository(this._api);

  final ApiClient _api;

  Future<Paged<Payment>> list(PageQuery query) async =>
      Paged.fromJson(await _api.get('/payments', query: query.toQuery()) as Json, Payment.fromJson);

  /// Paiement d'une vente qui a un reste à payer (solde d'une avance ou d'une dette).
  /// Paiement (avance ou solde d'une dette) : il n'y a pas de mode de paiement à choisir.
  Future<Payment> create({required int saleId, required double amount}) async {
    final data = await _api.post(
      '/payments',
      data: {'sale_id': saleId, 'method': PaymentMethod.cash.code, 'amount': amount},
    );
    return Payment.fromJson(data as Json);
  }
}
