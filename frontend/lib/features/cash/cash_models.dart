import '../../core/utils/json.dart';

enum CashTransactionType {
  sale('SALE', 'Vente', manual: false),
  expense('EXPENSE', 'Dépense'),
  withdrawal('WITHDRAWAL', 'Retrait'),
  deposit('DEPOSIT', 'Dépôt'),
  refund('REFUND', 'Remboursement', manual: false),
  adjustment('ADJUSTMENT', 'Ajustement');

  const CashTransactionType(this.code, this.label, {this.manual = true});
  final String code;
  final String label;

  /// SALE et REFUND sont créés automatiquement par les ventes.
  final bool manual;

  static CashTransactionType fromCode(String code) =>
      values.firstWhere((type) => type.code == code, orElse: () => CashTransactionType.adjustment);

  static List<CashTransactionType> get manualTypes => values.where((type) => type.manual).toList();
}

class CashRegister {
  const CashRegister({
    required this.id,
    required this.storeId,
    required this.openingAmount,
    required this.expectedAmount,
    required this.status,
    required this.openedAt,
    this.openedBy,
    this.openedAutomatically = false,
    this.closedAutomatically = false,
    this.closedBy,
    this.closingAmount,
    this.difference,
    this.closedAt,
  });

  factory CashRegister.fromJson(Json json) => CashRegister(
    id: toInt(json['id']),
    storeId: toInt(json['store_id']),
    openedBy: json['opened_by'] == null ? null : toInt(json['opened_by']),
    openedAutomatically: json['opened_automatically'] == true,
    closedAutomatically: json['closed_automatically'] == true,
    closedBy: json['closed_by'] == null ? null : toInt(json['closed_by']),
    openingAmount: toDouble(json['opening_amount']),
    closingAmount: toDoubleOrNull(json['closing_amount']),
    expectedAmount: toDouble(json['expected_amount']),
    difference: toDoubleOrNull(json['difference']),
    status: '${json['status']}',
    openedAt: toDate(json['opened_at']) ?? DateTime.now(),
    closedAt: toDate(json['closed_at']),
  );

  final int id;
  final int storeId;

  /// null : caisse ouverte automatiquement par le serveur.
  final int? openedBy;
  final int? closedBy;
  final bool openedAutomatically;
  final bool closedAutomatically;
  final double openingAmount;
  final double? closingAmount;

  /// Montant théorique en caisse.
  final double expectedAmount;

  /// Montant compté - montant théorique (négatif = manque).
  final double? difference;
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;

  bool get isOpen => status == 'OPEN';
}

class CashTransaction {
  const CashTransaction({
    required this.id,
    required this.registerId,
    required this.type,
    required this.amount,
    required this.createdBy,
    required this.createdAt,
    this.reason,
    this.reference,
  });

  factory CashTransaction.fromJson(Json json) => CashTransaction(
    id: toInt(json['id']),
    registerId: toInt(json['cash_register_id']),
    type: CashTransactionType.fromCode('${json['type']}'),
    amount: toDouble(json['amount']),
    reason: toStringOrNull(json['reason']),
    reference: toStringOrNull(json['reference']),
    createdBy: toInt(json['created_by']),
    createdAt: toDate(json['created_at']) ?? DateTime.now(),
  );

  final int id;
  final int registerId;
  final CashTransactionType type;

  /// Positif = entrée d'argent, négatif = sortie.
  final double amount;
  final String? reason;
  final String? reference;
  final int createdBy;
  final DateTime createdAt;
}

/// Horaires d'ouverture et de fermeture automatiques des caisses (GET /cash/schedule).
class CashSchedule {
  const CashSchedule({required this.enabled, required this.openTime, required this.closeTime, required this.timezone});

  factory CashSchedule.fromJson(Json json) => CashSchedule(
    enabled: json['enabled'] == true,
    openTime: '${json['open_time']}',
    closeTime: '${json['close_time']}',
    timezone: '${json['timezone']}',
  );

  final bool enabled;
  final String openTime; // ex. 06:00
  final String closeTime; // ex. 19:00
  final String timezone;

  String get timezoneLabel => timezone == 'Indian/Antananarivo' ? 'heure de Madagascar' : timezone;
}
