import 'package:flutter/foundation.dart';

import '../../core/utils/formatters.dart';
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

  /// Précision pour cet article (taille, couleur...), facultative.
  String description = '';

  double get unitPrice => product.sellingPrice;
  double get total => roundMoney(unitPrice * quantity);
  bool get exceedsStock => quantity > available;
}

/// Une date de remboursement prévue pour le reste à payer, et son montant.
class CartInstallment {
  CartInstallment({required this.id, this.dueDate, this.amount = 0});

  final int id;
  DateTime? dueDate;
  double amount;
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

  /// true = « Payé » (paiement complet) ; false = « Dette (avance) » : [advanceAmount] payé maintenant.
  bool payInFull = true;
  double advanceAmount = 0;

  /// Dates de remboursement du reste à payer (dette).
  final List<CartInstallment> _installments = [];
  int _nextInstallmentId = 0;

  List<CartLine> get lines => List.unmodifiable(_lines.values);
  List<CartInstallment> get installments => List.unmodifiable(_installments);
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

  /// « Dette (avance) » sans montant payé : dette sans avance (tout le total reste à payer).
  bool get isDebtWithoutAdvance => !payInFull && advanceAmount <= 0;

  /// Code envoyé au serveur : CREDIT (rien payé) pour une dette sans avance, sinon CASH.
  PaymentMethod get effectiveMethod => isDebtWithoutAdvance ? PaymentMethod.credit : PaymentMethod.cash;

  double get amountPaid {
    if (effectiveMethod == PaymentMethod.credit) return 0;
    if (payInFull) return total;
    return roundMoney(advanceAmount.clamp(0, total));
  }

  double get remaining => roundMoney(total - amountPaid);
  bool get hasDebt => remaining > 0;

  /// Somme des remboursements prévus (doit être égale au reste à payer).
  double get installmentsTotal => roundMoney(_installments.fold(0.0, (sum, i) => sum + i.amount));

  /// Remboursements triés par date (les dates pas encore choisies à la fin).
  List<CartInstallment> get sortedInstallments => [..._installments]
    ..sort((a, b) {
      if (a.dueDate == null || b.dueDate == null) return a.dueDate == null ? (b.dueDate == null ? 0 : 1) : -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });

  // --- Modifications ------------------------------------------------------------------------

  void setStore(StoreRef? value) {
    if (store?.id == value?.id) return;
    store = value;
    // Les quantités disponibles dépendent du magasin : le panier est vidé.
    _lines.clear();
    _changed();
  }

  /// Ajoute un produit (ou une unité de plus s'il est déjà dans le panier).
  void add(Product product, {required int available}) {
    final line = _lines[product.id];
    if (line == null) {
      _lines[product.id] = CartLine(product: product, available: available);
    } else if (line.quantity < line.available) {
      line.quantity++;
    }
    _changed();
  }

  void setQuantity(int productId, int quantity) {
    final line = _lines[productId];
    if (line == null) return;
    if (quantity <= 0) {
      _lines.remove(productId);
    } else {
      line.quantity = quantity;
    }
    _changed();
  }

  void remove(int productId) {
    if (_lines.remove(productId) != null) _changed();
  }

  /// Précision de l'article (taille, couleur...). Aucun montant ne change : pas de nouvel affichage.
  void setDescription(int productId, String text) => _lines[productId]?.description = text.trim();

  void setCustomer(CartCustomer? value) {
    customer = value;
    notifyListeners();
  }

  void setDiscount(DiscountType type, double value) {
    discountType = type;
    discountValue = type == DiscountType.none ? 0 : value;
    _changed();
  }

  void setPayment({bool? inFull, double? advance}) {
    if (inFull != null) payInFull = inFull;
    if (advance != null) advanceAmount = advance;
    if (payInFull) {
      _installments.clear();
    } else if (_installments.isEmpty) {
      _installments.add(CartInstallment(id: _nextInstallmentId++));
    }
    _changed();
  }

  // --- Dates de remboursement (dette) --------------------------------------------------------------

  /// Ajoute une date (un mois après la précédente) et répartit le reste à payer également.
  void addInstallment() {
    final last = sortedInstallments.lastOrNull?.dueDate;
    _installments.add(
      CartInstallment(
        id: _nextInstallmentId++,
        dueDate: last == null ? null : DateTime(last.year, last.month + 1, last.day),
      ),
    );
    _changed();
  }

  /// Retire une date (il en reste toujours au moins une) et répartit le reste à payer également.
  void removeInstallment(int id) {
    if (_installments.length <= 1) return;
    _installments.removeWhere((installment) => installment.id == id);
    _changed();
  }

  void setInstallmentDate(int id, DateTime date) {
    _installmentById(id)?.dueDate = DateTime(date.year, date.month, date.day);
    notifyListeners();
  }

  /// Montant saisi à la main : la répartition n'est pas refaite.
  void setInstallmentAmount(int id, double amount) {
    _installmentById(id)?.amount = amount;
    notifyListeners();
  }

  /// Répartit le reste à payer également entre les dates (montants ronds, le dernier prend le reste).
  void splitInstallmentsEvenly() => _changed();

  CartInstallment? _installmentById(int id) => _installments.where((i) => i.id == id).firstOrNull;

  void _splitInstallments() {
    if (_installments.isEmpty) return;
    final count = _installments.length;
    final share = (remaining / count).floorToDouble();
    for (final installment in _installments) {
      installment.amount = share;
    }
    _installments.last.amount = roundMoney(remaining - share * (count - 1));
  }

  /// Le reste à payer a pu changer : les remboursements sont répartis de nouveau, puis l'écran est prévenu.
  void _changed() {
    _splitInstallments();
    notifyListeners();
  }

  /// Vide le panier après une vente (le magasin choisi est conservé).
  void clear() {
    _lines.clear();
    customer = null;
    discountType = DiscountType.none;
    discountValue = 0;
    payInFull = true;
    advanceAmount = 0;
    _installments.clear();
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

  /// Problèmes de paiement (montant, dates de remboursement, téléphone du client).
  List<String> get paymentErrors => [
    if (!payInFull && advanceAmount > total) 'L\'avance ne peut pas dépasser le total.',
    if (hasDebt && customer == null) 'Choisissez le client : il est obligatoire pour une dette ou une avance.',
    ...installmentErrors,
    if (hasDebt && customer != null && customer!.phoneNumber == null)
      'Le téléphone du client est obligatoire s\'il reste un montant à payer.',
  ];

  /// Problèmes des dates de remboursement (seulement s'il reste un montant à payer).
  List<String> get installmentErrors {
    if (!hasDebt) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = [for (final installment in _installments) ?installment.dueDate];
    return [
      if (_installments.isEmpty) 'Ajoutez au moins une date de remboursement.',
      if (dates.length < _installments.length) 'Choisissez la date de chaque remboursement.',
      if (dates.any((date) => date.isBefore(today))) 'Une date de remboursement ne peut pas être dans le passé.',
      if (dates.toSet().length < dates.length) 'Deux remboursements ne peuvent pas avoir la même date.',
      if (_installments.any((installment) => installment.amount <= 0))
        'Chaque remboursement doit avoir un montant supérieur à 0.',
      if (_installments.isNotEmpty && installmentsTotal != remaining)
        'Le total des remboursements (${Formats.money(installmentsTotal)}) doit être égal '
            'au reste à payer (${Formats.money(remaining)}).',
    ];
  }

  List<String> get allErrors => [...cartErrors, ...discountErrors, ...paymentErrors];

  bool get isReady => allErrors.isEmpty;

  /// Données envoyées à POST /sales (une seule fois, après confirmation).
  /// Sans client (vente payée), le serveur enregistre la vente au nom de « Client comptant ».
  NewSale toNewSale({required bool includeStore}) {
    final client = customer;
    final method = effectiveMethod;
    final collected = method != PaymentMethod.credit;
    return NewSale(
      lines: {for (final line in _lines.values) line.product.id: line.quantity},
      descriptions: {
        for (final line in _lines.values)
          if (line.description.isNotEmpty) line.product.id: line.description,
      },
      storeId: includeStore ? store?.id : null,
      customerId: client?.existing?.id,
      customerFirstName: client?.firstName,
      customerLastName: client?.lastName,
      customerPhone: client?.phone,
      discountType: discountType,
      discountValue: discountValue,
      paymentMethod: method,
      paidAmount: collected && !payInFull ? roundMoney(advanceAmount) : null,
      installments: hasDebt
          ? [for (final i in sortedInstallments) (dueDate: i.dueDate!, amount: roundMoney(i.amount))]
          : const [],
    );
  }
}
