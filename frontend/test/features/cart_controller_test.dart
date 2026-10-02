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

  test('avance : reste à payer, échéance et téléphone obligatoires', () {
    cart.add(_product(1, 5000), available: 5);
    cart.setCustomer(const CartCustomer.create(firstName: 'Rasoa', lastName: 'Be'));
    cart.setPayment(inFull: false, advance: 2000);
    expect(cart.amountPaid, 2000);
    expect(cart.remaining, 3000);
    expect(cart.paymentErrors, contains('Choisissez la date d\'échéance du reste à payer.'));
    expect(cart.paymentErrors, contains('Le téléphone du client est obligatoire s\'il reste un montant à payer.'));
    cart.setCustomer(const CartCustomer.create(firstName: 'Rasoa', lastName: 'Be', phone: '034 12 345 67'));
    cart.setPayment(due: DateTime.now().add(const Duration(days: 7)));
    expect(cart.paymentErrors, isEmpty);
    cart.setPayment(advance: 6000);
    expect(cart.paymentErrors, contains('L\'avance ne peut pas dépasser le total.'));
  });

  test('vente à crédit : rien n\'est encaissé', () {
    cart.add(_product(1, 5000), available: 5);
    cart.setPayment(method: PaymentMethod.credit);
    expect(cart.amountPaid, 0);
    expect(cart.remaining, 5000);
  });

  test('données envoyées à l\'API : nouveau client, avance, échéance', () {
    cart.add(_product(1, 1000), available: 5);
    cart.add(_product(2, 2500), available: 5);
    cart.setQuantity(1, 3);
    cart.setCustomer(const CartCustomer.create(firstName: 'Rasoa', lastName: 'Be', phone: '0341234567'));
    cart.setDiscount(DiscountType.fixed, 500);
    cart.setPayment(
      method: PaymentMethod.mobileMoney,
      inFull: false,
      advance: 1000,
      reference: 'MVOLA-1',
      due: DateTime(2026, 12, 31),
    );
    final json = cart.toNewSale(includeStore: true).toJson();
    expect(json['store_id'], 1);
    expect(json['customer'], {'first_name': 'Rasoa', 'last_name': 'Be', 'phone': '0341234567'});
    expect(json.containsKey('customer_id'), isFalse);
    expect(json['items'], [
      {'product_id': 1, 'quantity': 3},
      {'product_id': 2, 'quantity': 1},
    ]);
    expect(json['discount_type'], 'FIXED');
    expect(json['discount_value'], 500);
    expect(json['payment'], {'method': 'MOBILE_MONEY', 'amount': 1000.0, 'reference': 'MVOLA-1'});
    expect(json['payment_due_date'], '2026-12-31');
  });

  test('données envoyées : client existant, paiement complet, magasin imposé par le serveur pour un vendeur', () {
    cart.add(_product(1, 1000), available: 5);
    cart.setCustomer(const CartCustomer.existing(CustomerRef(id: 7, firstName: 'rasoa', lastName: 'be')));
    cart.setPayment(due: DateTime(2026, 12, 31));
    final json = cart.toNewSale(includeStore: false).toJson();
    expect(json['store_id'], isNull);
    expect(json['customer_id'], 7);
    expect(json['payment'], {'method': 'CASH', 'amount': null, 'reference': null});
    expect(json['payment_due_date'], isNull, reason: 'paiement complet : pas d\'échéance');
  });

  test('changer de magasin vide le panier', () {
    cart.add(_product(1, 1000), available: 5);
    cart.setStore(const StoreRef(id: 2, name: 'h109'));
    expect(cart.isEmpty, isTrue);
  });
}
