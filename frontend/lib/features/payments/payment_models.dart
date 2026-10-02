import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';

/// Modes de paiement. CREDIT = vente à crédit (rien n'est encaissé).
enum PaymentMethod {
  cash('CASH', 'Espèces'),
  mobileMoney('MOBILE_MONEY', 'Mobile money'),
  card('CARD', 'Carte'),
  bankTransfer('BANK_TRANSFER', 'Virement'),
  credit('CREDIT', 'Crédit');

  const PaymentMethod(this.code, this.label);
  final String code;
  final String label;

  static PaymentMethod fromCode(String code) =>
      values.firstWhere((method) => method.code == code, orElse: () => PaymentMethod.cash);

  /// Modes correspondant à un encaissement réel.
  static List<PaymentMethod> get collected => values.where((m) => m != PaymentMethod.credit).toList();
}

class Payment {
  const Payment({
    required this.id,
    required this.saleId,
    required this.method,
    required this.amount,
    required this.createdAt,
    this.reference,
    this.creator,
  });

  factory Payment.fromJson(Json json) => Payment(
    id: toInt(json['id']),
    saleId: toInt(json['sale_id']),
    method: PaymentMethod.fromCode('${json['method']}'),
    amount: toDouble(json['amount']),
    reference: toStringOrNull(json['reference']),
    creator: toObject(json['creator'], UserRef.fromJson),
    createdAt: toDate(json['created_at']) ?? DateTime.now(),
  );

  final int id;
  final int saleId;
  final PaymentMethod method;
  final double amount;
  final String? reference;
  final UserRef? creator;
  final DateTime createdAt;
}
