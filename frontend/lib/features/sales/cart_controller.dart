import 'package:flutter/foundation.dart';

import '../../shared/models/refs.dart';
import '../payments/payment_models.dart';
import '../products/product_models.dart';
import 'sale_models.dart';
import 'sales_repository.dart';

/// Une ligne du panier : un produit, la quantité choisie et la quantité disponible dans le magasin.
class CartLine {
  CartLine({required this.product, required this.available, this.quantity = 1});

  final Product product;
  final int available;
  int quantity;

  double get unitPrice => product.sellingPrice;
  double get total => roundMoney(unitPrice * quantity);
  bool get exceedsStock => quantity > available;
}

/// Arrondi à 2 décimales, comme le serveur.
double roundMoney(double value) => (value * 100).roundToDouble() / 100;

/// Client de la vente : un client existant ou un nouveau client.
class CartCustomer {
  const CartCustomer.existing(CustomerRef this.existing) : firstName = null, lastName = null, phone = null;

  const CartCustomer.create({required String this.firstName, required String this.lastName, this.phone})
    : existing = null;

  final CustomerRef? existing;
  final String? firstName;
  final String? lastName;
  final String? phone;

  bool get isNew => existing == null;

  String get fullName => existing?.fullName ?? '${firstName ?? ''} ${lastName ?? ''}'.trim();

  String? get phoneNumber {
    final value = existing?.phone ?? phone;
    return value == null || value.trim().isEmpty ? null : value.trim();
  }
}

/// Panier de la vente en cours.
///
/// Les montants affichés ici sont un aperçu : le serveur recalcule toujours le sous-total,
/// la remise, le total et le reste à payer au moment de l'enregistrement.
class CartController extends ChangeNotifier {
  final Map<int, CartLine> _lines = {};

  StoreRef? store;
  CartCustomer? customer;
  DiscountType discountType = DiscountType.none;
  double discountValue = 0;

  /// null tant que l'utilisateur n'a pas choisi ; [PaymentMethod.credit] = rien n'est encaissé.
  PaymentMethod paymentMethod = PaymentMethod.cash;

  /// true = paiement complet ; false = avance de [advanceAmount].
  bool payInFull = true;
  double advanceAmount = 0;
  String? paymentReference;
  DateTime? dueDate;

  List<CartLine> get lines => List.unmodifiable(_lines.values);
  bool get isEmpty => _lines.isEmpty;
  int get itemCount => _lines.values.fold(0, (sum, line) => sum + line.quantity);
  int quantityOf(int productId) => _lines[productId]?.quantity ?? 0;
  bool contains(int productId) => _lines.containsKey(productId);

  // --- Calculs ------------------------------------------------------------------------------

  double get subtotal => roundMoney(_lines.values.fold(0.0, (sum, line) => sum + line.total));

  double get discountAmount => switch (discountType) {
    DiscountType.none => 0,
    DiscountType.percentage => roundMoney(subtotal * discountValue.clamp(0, 100) / 100),
    DiscountType.fixed => roundMoney(discountValue.clamp(0, subtotal)),
  };

  double get total => roundMoney(subtotal - discountAmount);

  /// Montant encaissé maintenant.
  double get amountPaid {
    if (paymentMethod == PaymentMethod.credit) return 0;
    if (payInFull) return total;
    return roundMoney(advanceAmount.clamp(0, total));
  }

  double get remaining => roundMoney(total - amountPaid);
  bool get hasDebt => remaining > 0;

  // --- Modifications ------------------------------------------------------------------------

  void setStore(StoreRef? value) {
    if (store?.id == value?.id) return;
    store = value;
    // Les quantités disponibles dépendent du magasin : le panier est vidé.
    _lines.clear();
    notifyListeners();
  }

  /// Ajoute un produit (ou une unité de plus s'il est déjà dans le panier).
  void add(Product product, {required int available}) {
    final line = _lines[product.id];
    if (line == null) {
      _lines[product.id] = CartLine(product: product, available: available);
    } else if (line.quantity < line.available) {
      line.quantity++;
    }
    notifyListeners();
  }

  void setQuantity(int productId, int quantity) {
    final line = _lines[productId];
    if (line == null) return;
    if (quantity <= 0) {
      _lines.remove(productId);
    } else {
      line.quantity = quantity;
    }
    notifyListeners();
  }

  void remove(int productId) {
    if (_lines.remove(productId) != null) notifyListeners();
  }

  void setCustomer(CartCustomer? value) {
    customer = value;
    notifyListeners();
  }

  void setDiscount(DiscountType type, double value) {
    discountType = type;
    discountValue = type == DiscountType.none ? 0 : value;
    notifyListeners();
  }

  void setPayment({
    PaymentMethod? method,
    bool? inFull,
    double? advance,
    String? reference,
    DateTime? due,
    bool clearDueDate = false,
  }) {
    if (method != null) paymentMethod = method;
    if (inFull != null) payInFull = inFull;
    if (advance != null) advanceAmount = advance;
    if (reference != null) paymentReference = reference.trim().isEmpty ? null : reference.trim();
    if (due != null) dueDate = due;
    if (clearDueDate) dueDate = null;
    notifyListeners();
  }

  /// Vide le panier après une vente (le magasin choisi est conservé).
  void clear() {
    _lines.clear();
    customer = null;
    discountType = DiscountType.none;
    discountValue = 0;
    paymentMethod = PaymentMethod.cash;
    payInFull = true;
    advanceAmount = 0;
    paymentReference = null;
    dueDate = null;
    notifyListeners();
  }

  /// Tout remettre à zéro (déconnexion).
  void reset() {
    store = null;
    clear();
  }

  // --- Contrôles avant confirmation -----------------------------------------------------------

  /// Problèmes empêchant de valider le panier (étape produits).
  List<String> get cartErrors => [
    if (_lines.isEmpty) 'Ajoutez au moins un produit.',
    for (final line in _lines.values)
      if (line.exceedsStock)
        '${line.product.label} : quantité demandée (${line.quantity}) supérieure au stock (${line.available}).',
  ];

  /// Problèmes de remise.
  List<String> get discountErrors => [
    if (discountType != DiscountType.none && discountValue <= 0) 'Saisissez une remise supérieure à 0.',
    if (discountType == DiscountType.percentage && discountValue > 100)
      'Une remise en pourcentage ne peut pas dépasser 100 %.',
    if (discountType == DiscountType.fixed && discountValue > subtotal) 'La remise ne peut pas dépasser le sous-total.',
  ];

  /// Problèmes de paiement (montant, échéance, téléphone du client).
  List<String> get paymentErrors {
    final today = DateTime.now();
    final due = dueDate;
    return [
      if (paymentMethod != PaymentMethod.credit && !payInFull && advanceAmount <= 0)
        'Saisissez le montant de l\'avance.',
      if (paymentMethod != PaymentMethod.credit && !payInFull && advanceAmount > total)
        'L\'avance ne peut pas dépasser le total.',
      if (hasDebt && due == null) 'Choisissez la date d\'échéance du reste à payer.',
      if (hasDebt &&
          due != null &&
          DateTime(due.year, due.month, due.day).isBefore(DateTime(today.year, today.month, today.day)))
        'La date d\'échéance ne peut pas être dans le passé.',
      if (hasDebt && customer != null && customer!.phoneNumber == null)
        'Le téléphone du client est obligatoire s\'il reste un montant à payer.',
    ];
  }

  List<String> get allErrors => [
    ...cartErrors,
    if (customer == null) 'Choisissez ou créez le client.',
    ...discountErrors,
    ...paymentErrors,
  ];

  bool get isReady => allErrors.isEmpty;

  /// Données envoyées à POST /sales (une seule fois, après confirmation).
  NewSale toNewSale({required bool includeStore}) {
    final client = customer!;
    final collected = paymentMethod != PaymentMethod.credit;
    return NewSale(
      lines: {for (final line in _lines.values) line.product.id: line.quantity},
      storeId: includeStore ? store?.id : null,
      customerId: client.existing?.id,
      customerFirstName: client.firstName,
      customerLastName: client.lastName,
      customerPhone: client.phone,
      discountType: discountType,
      discountValue: discountValue,
      paymentMethod: paymentMethod,
      paidAmount: collected && !payInFull ? roundMoney(advanceAmount) : null,
      paymentReference: collected ? paymentReference : null,
      dueDate: hasDebt ? dueDate : null,
    );
  }
}
