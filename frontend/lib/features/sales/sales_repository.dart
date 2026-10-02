import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
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
    this.paymentReference,
    this.dueDate,
  });

  /// product_id -> quantité
  final Map<int, int> lines;
  final int? storeId;
  final int? customerId;
  final String? customerFirstName;
  final String? customerLastName;
  final String? customerPhone;
  final DiscountType discountType;
  final double discountValue;

  /// null = vente à crédit (rien n'est encaissé).
  final PaymentMethod? paymentMethod;

  /// null = paiement complet (le serveur prend le total).
  final double? paidAmount;
  final String? paymentReference;
  final DateTime? dueDate;

  Json toJson() => {
    'store_id': storeId,
    if (customerId != null)
      'customer_id': customerId
    else
      'customer': {'first_name': customerFirstName, 'last_name': customerLastName, 'phone': customerPhone},
    'items': [
      for (final entry in lines.entries) {'product_id': entry.key, 'quantity': entry.value},
    ],
    'discount_type': discountType.code,
    'discount_value': discountType == DiscountType.none ? 0 : discountValue,
    if (paymentMethod != null)
      'payment': {
        'method': paymentMethod!.code,
        'amount': paymentMethod == PaymentMethod.credit ? null : paidAmount,
        'reference': paymentReference,
      },
    'payment_due_date': dueDate == null
        ? null
        : '${dueDate!.year.toString().padLeft(4, '0')}-${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}',
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
