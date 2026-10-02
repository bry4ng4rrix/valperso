import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/features/payments/payment_models.dart';
import 'package:valmag/features/products/product_models.dart';
import 'package:valmag/features/sales/cart_controller.dart';
import 'package:valmag/features/sales/sale_models.dart';
import 'package:valmag/shared/models/refs.dart';

Product _product(int id, double price) => Product(
  id: id,
  reference: 'P-$id',
  name: 'produit $id',
  purchasePrice: price / 2,
  sellingPrice: price,
  isActive: true,
);

void main() {
  late CartController cart;

  setUp(() {
    cart = CartController()..setStore(const StoreRef(id: 1, name: 'stock local', isCentral: true));
  });

  test('ajout de produits : quantité limitée au stock disponible', () {
    final stylo = _product(1, 1000);
    cart.add(stylo, available: 2);
    cart.add(stylo, available: 2);
    cart.add(stylo, available: 2); // au-delà du stock : ignoré
    expect(cart.quantityOf(1), 2);
    cart.setQuantity(1, 5);
    expect(cart.cartErrors.single, contains('supérieure au stock'));
    cart.setQuantity(1, 0);
    expect(cart.isEmpty, isTrue);
    expect(cart.cartErrors.single, 'Ajoutez au moins un produit.');
  });

  test('sous-total, remise en pourcentage et montant fixe (arrondis à 2 décimales)', () {
    cart.add(_product(1, 3333.33), available: 10);
    cart.setQuantity(1, 3);
    expect(cart.subtotal, 9999.99);
    cart.setDiscount(DiscountType.percentage, 10);
    expect(cart.discountAmount, 1000.0);
    expect(cart.total, 8999.99);
    cart.setDiscount(DiscountType.fixed, 999.99);
    expect(cart.total, 9000.0);
    cart.setDiscount(DiscountType.fixed, 20000);
    expect(cart.discountErrors, contains('La remise ne peut pas dépasser le sous-total.'));
    cart.setDiscount(DiscountType.percentage, 120);
    expect(cart.discountErrors, contains('Une remise en pourcentage ne peut pas dépasser 100 %.'));
    cart.setDiscount(DiscountType.none, 50);
    expect(cart.discountValue, 0);
    expect(cart.total, 9999.99);
  });

  test('paiement complet : aucun reste, aucune échéance demandée', () {
    cart.add(_product(1, 5000), available: 5);
    cart.setCustomer(const CartCustomer.create(firstName: 'Rasoa', lastName: 'Be'));
    expect(cart.amountPaid, 5000);
    expect(cart.hasDebt, isFalse);
    expect(cart.isReady, isTrue);
  });

  test('avance : reste à payer, date de remboursement et téléphone obligatoires', () {
    cart.add(_product(1, 5000), available: 5);
    cart.setCustomer(const CartCustomer.create(firstName: 'Rasoa', lastName: 'Be'));
    cart.setPayment(inFull: false, advance: 2000);
    expect(cart.amountPaid, 2000);
    expect(cart.remaining, 3000);
    expect(cart.installments.single.amount, 3000, reason: 'une seule date : elle couvre tout le reste');
    expect(cart.paymentErrors, contains('Choisissez la date de chaque remboursement.'));
    expect(cart.paymentErrors, contains('Le téléphone du client est obligatoire s\'il reste un montant à payer.'));
    cart.setCustomer(const CartCustomer.create(firstName: 'Rasoa', lastName: 'Be', phone: '034 12 345 67'));
    cart.setInstallmentDate(cart.installments.single.id, DateTime.now().add(const Duration(days: 7)));
    expect(cart.paymentErrors, isEmpty);
    cart.setPayment(advance: 6000);
    expect(cart.paymentErrors, contains('L\'avance ne peut pas dépasser le total.'));
  });

  test('avec dette ou avance, montant vide : dette sans avance envoyée en crédit', () {
    cart.add(_product(1, 5000), available: 5);
    cart.setCustomer(const CartCustomer.create(firstName: 'Rasoa', lastName: 'Be', phone: '0341234567'));
    cart.setPayment(inFull: false, advance: 0);
    cart.setInstallmentDate(cart.installments.single.id, DateTime(2026, 12, 31));
    expect(cart.isDebtWithoutAdvance, isTrue);
    expect(cart.amountPaid, 0);
    expect(cart.remaining, 5000);
    expect(cart.paymentErrors, isEmpty, reason: 'aucune avance n\'est exigée');
    final json = cart.toNewSale(includeStore: false).toJson();
    expect(json['payment'], {'method': 'CREDIT', 'amount': null});
    expect(json['installments'], [
      {'due_date': '2026-12-31', 'amount': 5000.0},
    ]);
  });

  test('payé : tout le total est payé maintenant', () {
    cart.add(_product(1, 5000), available: 5);
    expect(cart.payInFull, isTrue);
    expect(cart.effectiveMethod, PaymentMethod.cash);
    expect(cart.amountPaid, 5000);
    expect(cart.hasDebt, isFalse);
  });

  test('données envoyées à l\'API : nouveau client, description, avance, échéancier', () {
    cart.add(_product(1, 1000), available: 5);
    cart.add(_product(2, 2500), available: 5);
    cart.setQuantity(1, 3);
    cart.setCustomer(const CartCustomer.create(firstName: 'Rasoa', lastName: 'Be', phone: '0341234567'));
    cart.setDiscount(DiscountType.fixed, 500);
    cart.setDescription(1, '  Taille M, noir ');
    cart.setPayment(inFull: false, advance: 1000);
    cart.addInstallment();
    final [first, second] = cart.installments;
    cart.setInstallmentDate(second.id, DateTime(2027, 1, 31));
    cart.setInstallmentDate(first.id, DateTime(2026, 12, 31));
    final json = cart.toNewSale(includeStore: true).toJson();
    expect(json['store_id'], 1);
    expect(json['customer'], {'first_name': 'Rasoa', 'last_name': 'Be', 'phone': '0341234567'});
    expect(json.containsKey('customer_id'), isFalse);
    expect(json['items'], [
      {'product_id': 1, 'quantity': 3, 'description': 'Taille M, noir'},
      {'product_id': 2, 'quantity': 1},
    ]);
    expect(json['discount_type'], 'FIXED');
    expect(json['discount_value'], 500);
    expect(json['payment'], {'method': 'CASH', 'amount': 1000.0});
    // Reste 4 000 (5 500 - 500 de remise - 1 000 d'avance), réparti également, trié par date.
    expect(json['installments'], [
      {'due_date': '2026-12-31', 'amount': 2000.0},
      {'due_date': '2027-01-31', 'amount': 2000.0},
    ]);
    expect(json.containsKey('payment_due_date'), isFalse);
  });

  test('données envoyées : client existant, paiement complet, magasin imposé par le serveur pour un vendeur', () {
    cart.add(_product(1, 1000), available: 5);
    cart.setCustomer(const CartCustomer.existing(CustomerRef(id: 7, firstName: 'rasoa', lastName: 'be')));
    final json = cart.toNewSale(includeStore: false).toJson();
    expect(json['store_id'], isNull);
    expect(json['customer_id'], 7);
    expect(json['payment'], {'method': 'CASH', 'amount': null});
    expect(json.containsKey('installments'), isFalse, reason: 'paiement complet : pas d\'échéance');
  });

  test('échéancier : répartition, montants saisis, contrôles', () {
    cart.add(_product(1, 10000), available: 5);
    cart.setCustomer(const CartCustomer.create(firstName: 'Rasoa', lastName: 'Be', phone: '0341234567'));
    cart.setPayment(inFull: false, advance: 1000);
    final today = DateTime.now();
    cart.setInstallmentDate(cart.installments.single.id, today.add(const Duration(days: 10)));

    cart.addInstallment();
    cart.addInstallment();
    expect(cart.installments.map((i) => i.amount), [3000, 3000, 3000], reason: '9 000 répartis en trois');
    final third = cart.installments.last;
    expect(cart.installments[1].dueDate, isNotNull, reason: 'un mois après la date précédente');

    cart.setPayment(advance: 2000);
    expect(cart.installments.map((i) => i.amount), [2666, 2666, 2668], reason: 'le dernier prend le reste');

    cart.setInstallmentAmount(third.id, 1000);
    expect(
      cart.paymentErrors,
      contains('Le total des remboursements (6\u00A0332 Ar) doit être égal au reste à payer (8\u00A0000 Ar).'),
    );
    cart.splitInstallmentsEvenly();
    expect(cart.installmentErrors, isEmpty);

    cart.setInstallmentDate(third.id, cart.installments.first.dueDate!);
    expect(cart.paymentErrors, contains('Deux remboursements ne peuvent pas avoir la même date.'));
    cart.setInstallmentDate(third.id, today.subtract(const Duration(days: 1)));
    expect(cart.paymentErrors, contains('Une date de remboursement ne peut pas être dans le passé.'));

    cart.removeInstallment(third.id);
    cart.removeInstallment(cart.installments.last.id);
    cart.removeInstallment(cart.installments.single.id);
    expect(cart.installments.single.amount, 8000, reason: 'il reste toujours une date, qui couvre tout');

    cart.setPayment(inFull: true);
    expect(cart.installments, isEmpty);
    expect(cart.installmentErrors, isEmpty);
  });

  test('changer de magasin vide le panier', () {
    cart.add(_product(1, 1000), available: 5);
    cart.setStore(const StoreRef(id: 2, name: 'h109'));
    expect(cart.isEmpty, isTrue);
  });
}
