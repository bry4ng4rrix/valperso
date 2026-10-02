import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';
import '../payments/payment_models.dart';
import '../sales/sale_models.dart';

/// Client avec le résumé de ses achats et de sa dette (GET /customers/contacts).
class CustomerContact {
  const CustomerContact({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.totalPurchases,
    required this.totalAmount,
    required this.totalPaid,
    required this.remainingAmount,
    required this.hasDebt,
    this.phone,
    this.lastSaleDate,
  });

  factory CustomerContact.fromJson(Json json) => CustomerContact(
    id: toInt(json['id']),
    firstName: '${json['first_name'] ?? ''}',
    lastName: '${json['last_name'] ?? ''}',
    phone: toStringOrNull(json['phone']),
    totalPurchases: toInt(json['total_purchases']),
    totalAmount: toDouble(json['total_amount']),
    totalPaid: toDouble(json['total_paid']),
    remainingAmount: toDouble(json['remaining_amount']),
    hasDebt: json['has_debt'] == true,
    lastSaleDate: toDate(json['last_sale_date']),
  );

  final int id;
  final String firstName;
  final String lastName;
  final String? phone;
  final int totalPurchases;
  final double totalAmount;
  final double totalPaid;
  final double remainingAmount;
  final bool hasDebt;
  final DateTime? lastSaleDate;

  String get fullName => '${Formats.capitalize(firstName)} ${Formats.capitalize(lastName)}'.trim();

  CustomerRef get ref => CustomerRef(id: id, firstName: firstName, lastName: lastName, phone: phone);
}

/// Vente non soldée d'un client.
class DebtSale {
  const DebtSale({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.store,
    required this.total,
    required this.amountPaid,
    required this.remainingAmount,
    required this.paymentStatus,
    required this.payments,
    this.dueDate,
    this.installments = const [],
  });

  factory DebtSale.fromJson(Json json) => DebtSale(
    id: toInt(json['id']),
    number: '${json['sale_number']}',
    createdAt: toDate(json['created_at']) ?? DateTime.now(),
    store: StoreRef.fromJson(Json.from(json['store'] as Map)),
    total: toDouble(json['total']),
    amountPaid: toDouble(json['amount_paid']),
    remainingAmount: toDouble(json['remaining_amount']),
    paymentStatus: PaymentStatus.fromCode('${json['payment_status']}'),
    dueDate: toDate(json['payment_due_date']),
    payments: toList(json['payments'], Payment.fromJson),
    installments: toList(json['installments'], SaleInstallment.fromJson),
  );

  final int id;
  final String number;
  final DateTime createdAt;
  final StoreRef store;
  final double total;
  final double amountPaid;
  final double remainingAmount;
  final PaymentStatus paymentStatus;

  /// Prochaine échéance non payée.
  final DateTime? dueDate;
  final List<Payment> payments;
  final List<SaleInstallment> installments;

  bool get isOverdue {
    final due = dueDate;
    if (due == null) return false;
    final now = DateTime.now();
    return DateTime(due.year, due.month, due.day).isBefore(DateTime(now.year, now.month, now.day));
  }
}

class CustomerDebts {
  const CustomerDebts({required this.customer, required this.totalDebt, required this.sales});

  factory CustomerDebts.fromJson(Json json) => CustomerDebts(
    customer: CustomerRef.fromJson(Json.from(json['customer'] as Map)),
    totalDebt: toDouble(json['total_debt']),
    sales: toList(json['sales'], DebtSale.fromJson),
  );

  final CustomerRef customer;
  final double totalDebt;
  final List<DebtSale> sales;
}
