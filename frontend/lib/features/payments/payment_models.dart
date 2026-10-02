import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';

/// Code envoyé au serveur : il n'y a plus de choix du mode de paiement.
/// CASH = payé (paiement complet ou avance) ; CREDIT = dette sans avance (rien n'est payé).
enum PaymentMethod {
  cash('CASH'),
  credit('CREDIT');

  const PaymentMethod(this.code);
  final String code;
}

class Payment {
  const Payment({
    required this.id,
    required this.saleId,
    required this.amount,
    required this.createdAt,
    this.reference,
    this.creator,
  });

  factory Payment.fromJson(Json json) => Payment(
    id: toInt(json['id']),
    saleId: toInt(json['sale_id']),
    amount: toDouble(json['amount']),
    reference: toStringOrNull(json['reference']),
    creator: toObject(json['creator'], UserRef.fromJson),
    createdAt: toDate(json['created_at']) ?? DateTime.now(),
  );

  final int id;
  final int saleId;
  final double amount;
  final String? reference;
  final UserRef? creator;
  final DateTime createdAt;
}
