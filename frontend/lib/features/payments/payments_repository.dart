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
  Future<Payment> create({
    required int saleId,
    required PaymentMethod method,
    required double amount,
    String? reference,
  }) async {
    final data = await _api.post(
      '/payments',
      data: {'sale_id': saleId, 'method': method.code, 'amount': amount, 'reference': reference},
    );
    return Payment.fromJson(data as Json);
  }
}
