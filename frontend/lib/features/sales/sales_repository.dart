import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../payments/payment_models.dart';
import 'sale_models.dart';

/// Données d'une nouvelle vente, envoyées seulement après la confirmation de l'utilisateur.
/// Les montants (sous-total, remise, total, reste) sont toujours recalculés par le serveur.
class NewSale {
  const NewSale({
    required this.lines,
    this.storeId,
    this.customerId,
    this.customerFirstName,
    this.customerLastName,
    this.customerPhone,
    this.discountType = DiscountType.none,
    this.discountValue = 0,
    this.paymentMethod,
    this.paidAmount,
    this.descriptions = const {},
    this.installments = const [],
  });

  /// product_id -> quantité
  final Map<int, int> lines;

  /// product_id -> précision de l'article (taille, couleur...)
  final Map<int, String> descriptions;
  final int? storeId;
  final int? customerId;
  final String? customerFirstName;
  final String? customerLastName;
  final String? customerPhone;
  final DiscountType discountType;
  final double discountValue;

  /// CASH = payé (complet ou avance) ; CREDIT ou null = dette sans avance.
  final PaymentMethod? paymentMethod;

  /// null = paiement complet (le serveur prend le total).
  final double? paidAmount;

  /// Dates de remboursement du reste à payer (dette), triées par date.
  final List<({DateTime dueDate, double amount})> installments;

  Json toJson() => {
    'store_id': storeId,
    if (customerId != null)
      'customer_id': customerId
    else if (customerFirstName != null)
      'customer': {'first_name': customerFirstName, 'last_name': customerLastName, 'phone': customerPhone},
    'items': [
      for (final entry in lines.entries)
        {
          'product_id': entry.key,
          'quantity': entry.value,
          if (descriptions[entry.key] != null) 'description': descriptions[entry.key],
        },
    ],
    'discount_type': discountType.code,
    'discount_value': discountType == DiscountType.none ? 0 : discountValue,
    if (paymentMethod != null)
      'payment': {'method': paymentMethod!.code, 'amount': paymentMethod == PaymentMethod.credit ? null : paidAmount},
    if (installments.isNotEmpty)
      'installments': [
        for (final installment in installments)
          {'due_date': Formats.apiDate(installment.dueDate), 'amount': installment.amount},
      ],
  };
}

class SalesRepository {
  SalesRepository(this._api);

  final ApiClient _api;

  Future<Paged<Sale>> history(PageQuery query) async =>
      Paged.fromJson(await _api.get('/sales/history', query: query.toQuery()) as Json, Sale.fromJson);

  Future<Sale> get(int id) async => Sale.fromJson(await _api.get('/sales/$id') as Json);

  Future<Invoice> invoice(int id) async => Invoice.fromJson(await _api.get('/sales/$id/invoice') as Json);

  Future<Sale> create(NewSale sale) async => Sale.fromJson(await _api.post('/sales', data: sale.toJson()) as Json);

  Future<Sale> cancel(int id, String reason) async =>
      Sale.fromJson(await _api.post('/sales/$id/cancel', data: {'reason': reason}) as Json);
}
