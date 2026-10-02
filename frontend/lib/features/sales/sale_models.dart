import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';
import '../payments/payment_models.dart';

enum PaymentStatus {
  unpaid('UNPAID', 'Non payé'),
  partial('PARTIAL', 'Partiel'),
  paid('PAID', 'Payé');

  const PaymentStatus(this.code, this.label);
  final String code;
  final String label;

  static PaymentStatus fromCode(String code) =>
      values.firstWhere((status) => status.code == code, orElse: () => PaymentStatus.unpaid);
}

enum DiscountType {
  none('NONE', 'Aucune'),
  percentage('PERCENTAGE', 'Pourcentage'),
  fixed('FIXED', 'Montant fixe');

  const DiscountType(this.code, this.label);
  final String code;
  final String label;

  static DiscountType fromCode(String code) =>
      values.firstWhere((type) => type.code == code, orElse: () => DiscountType.none);
}

class SaleItem {
  const SaleItem({
    required this.productId,
    required this.reference,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.description,
  });

  factory SaleItem.fromJson(Json json) => SaleItem(
    productId: toInt(json['product_id']),
    reference: '${json['product_reference']}',
    name: '${json['product_name']}',
    description: toStringOrNull(json['description']),
    quantity: toInt(json['quantity']),
    unitPrice: toDouble(json['unit_price']),
    total: toDouble(json['total']),
  );

  final int productId;
  final String reference;
  final String name;

  /// Précision saisie dans le panier pour cet article (taille, couleur...).
  final String? description;
  final int quantity;
  final double unitPrice;
  final double total;
}

/// Échéance d'une vente avec dette. Son état est calculé par le serveur à partir des paiements,
/// qui soldent les échéances dans l'ordre des dates.
class SaleInstallment {
  const SaleInstallment({
    required this.dueDate,
    required this.amount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.status,
    this.isOverdue = false,
  });

  factory SaleInstallment.fromJson(Json json) => SaleInstallment(
    dueDate: toDate(json['due_date']) ?? DateTime.now(),
    amount: toDouble(json['amount']),
    paidAmount: toDouble(json['paid_amount']),
    remainingAmount: toDouble(json['remaining_amount']),
    status: PaymentStatus.fromCode('${json['status']}'),
    isOverdue: json['is_overdue'] == true,
  );

  final DateTime dueDate;
  final double amount;
  final double paidAmount;
  final double remainingAmount;
  final PaymentStatus status;
  final bool isOverdue;

  String get statusLabel => isOverdue
      ? 'En retard'
      : switch (status) {
          PaymentStatus.paid => 'Payé',
          PaymentStatus.partial => 'Reste ${Formats.money(remainingAmount)}',
          PaymentStatus.unpaid => 'À payer',
        };
}

/// Échéancier en texte (une ligne par date), pour les résumés et la facture.
String installmentsText(List<SaleInstallment> installments) => [
  for (final installment in installments)
    '${Formats.date(installment.dueDate)} : ${Formats.money(installment.amount)}'
        '${installment.status == PaymentStatus.unpaid && !installment.isOverdue ? '' : ' (${installment.statusLabel.toLowerCase()})'}',
].join('\n');

/// Vente (ligne d'historique). Les champs du détail sont renseignés par GET /sales/{id}.
class Sale {
  const Sale({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.customer,
    required this.user,
    required this.store,
    required this.total,
    required this.amountPaid,
    required this.remainingAmount,
    required this.paymentStatus,
    required this.status,
    this.paymentDueDate,
    this.subtotal,
    this.discountType = DiscountType.none,
    this.discountValue = 0,
    this.discountAmount = 0,
    this.items = const [],
    this.payments = const [],
    this.installments = const [],
  });

  factory Sale.fromJson(Json json) => Sale(
    id: toInt(json['id']),
    number: '${json['sale_number']}',
    createdAt: toDate(json['created_at']) ?? DateTime.now(),
    customer: CustomerRef.fromJson(Json.from(json['customer'] as Map)),
    user: UserRef.fromJson(Json.from(json['user'] as Map)),
    store: StoreRef.fromJson(Json.from(json['store'] as Map)),
    total: toDouble(json['total']),
    amountPaid: toDouble(json['amount_paid']),
    remainingAmount: toDouble(json['remaining_amount']),
    paymentStatus: PaymentStatus.fromCode('${json['payment_status']}'),
    status: '${json['status']}',
    paymentDueDate: toDate(json['payment_due_date']),
    subtotal: toDoubleOrNull(json['subtotal']),
    discountType: DiscountType.fromCode('${json['discount_type'] ?? 'NONE'}'),
    discountValue: toDouble(json['discount_value']),
    discountAmount: toDouble(json['discount_amount']),
    items: toList(json['items'], SaleItem.fromJson),
    payments: toList(json['payments'], Payment.fromJson),
    installments: toList(json['installments'], SaleInstallment.fromJson),
  );

  final int id;
  final String number;
  final DateTime createdAt;
  final CustomerRef customer;
  final UserRef user;
  final StoreRef store;
  final double total;
  final double amountPaid;
  final double remainingAmount;
  final PaymentStatus paymentStatus;
  final String status;

  /// Prochaine échéance non payée.
  final DateTime? paymentDueDate;
  final double? subtotal;
  final DiscountType discountType;
  final double discountValue;
  final double discountAmount;
  final List<SaleItem> items;
  final List<Payment> payments;

  /// Échéancier du reste à payer (vide pour une vente payée en une fois).
  final List<SaleInstallment> installments;

  bool get isCancelled => status == 'CANCELLED';
  bool get hasDebt => !isCancelled && remainingAmount > 0;

  /// Échéance dépassée et reste à payer.
  bool get isOverdue {
    final due = paymentDueDate;
    if (due == null || !hasDebt) return false;
    final today = DateTime.now();
    return DateTime(due.year, due.month, due.day).isBefore(DateTime(today.year, today.month, today.day));
  }

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);
}

/// Facture d'une vente (informations de la société figées au moment de la vente).
class Invoice {
  const Invoice({
    required this.companyName,
    required this.number,
    required this.date,
    required this.storeName,
    required this.seller,
    required this.customer,
    required this.lines,
    required this.subtotal,
    required this.discountType,
    required this.discountAmount,
    required this.total,
    required this.payments,
    required this.amountPaid,
    required this.remainingAmount,
    required this.paymentStatus,
    required this.status,
    required this.thankYouMessage,
    this.logoUrl,
    this.companyAddress,
    this.companyCity,
    this.companyPhone,
    this.companyEmail,
    this.storeAddress,
    this.storePhone,
    this.dueDate,
    this.installments = const [],
  });

  factory Invoice.fromJson(Json json) {
    final company = Json.from(json['company'] as Map);
    final store = Json.from(json['store'] as Map);
    return Invoice(
      companyName: '${company['name']}',
      logoUrl: toStringOrNull(company['logo_url']),
      companyAddress: toStringOrNull(company['address']),
      companyCity: toStringOrNull(company['city']),
      companyPhone: toStringOrNull(company['phone']),
      companyEmail: toStringOrNull(company['email']),
      number: '${json['invoice_number']}',
      date: toDate(json['date']) ?? DateTime.now(),
      storeName: '${store['name']}',
      storeAddress: toStringOrNull(store['address']),
      storePhone: toStringOrNull(store['phone']),
      seller: UserRef.fromJson(Json.from(json['user'] as Map)),
      customer: CustomerRef.fromJson(Json.from(json['customer'] as Map)),
      lines: toList(json['lines'], SaleItem.fromJson),
      subtotal: toDouble(json['subtotal']),
      discountType: DiscountType.fromCode('${json['discount_type']}'),
      discountAmount: toDouble(json['discount_amount']),
      total: toDouble(json['total']),
      payments: toList(json['payments'], Payment.fromJson),
      amountPaid: toDouble(json['amount_paid']),
      remainingAmount: toDouble(json['remaining_amount']),
      paymentStatus: PaymentStatus.fromCode('${json['payment_status']}'),
      dueDate: toDate(json['payment_due_date']),
      installments: toList(json['installments'], SaleInstallment.fromJson),
      status: '${json['status']}',
      thankYouMessage: [...(json['thank_you_message'] as List? ?? const []).map((line) => '$line')],
    );
  }

  final String companyName;
  final String? logoUrl;
  final String? companyAddress;
  final String? companyCity;
  final String? companyPhone;
  final String? companyEmail;
  final String number;
  final DateTime date;
  final String storeName;
  final String? storeAddress;
  final String? storePhone;
  final UserRef seller;
  final CustomerRef customer;
  final List<SaleItem> lines;
  final double subtotal;
  final DiscountType discountType;
  final double discountAmount;
  final double total;
  final List<Payment> payments;
  final double amountPaid;
  final double remainingAmount;
  final PaymentStatus paymentStatus;
  final DateTime? dueDate;
  final List<SaleInstallment> installments;
  final String status;
  final List<String> thankYouMessage;
}
