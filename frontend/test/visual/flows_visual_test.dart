@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:valmag/core/widgets/app_dialog.dart';
import 'package:valmag/features/sales/cart_controller.dart';
import 'package:valmag/features/sales/new_sale_panels.dart';

import '../support/demo_data.dart';
import '../support/fake_api.dart';
import '../support/test_app.dart';
import 'visual_helpers.dart';

/// Parcours avec saisie et dialogues, comparés à leurs captures de référence.

Future<void> _addToCart(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.tap(find.byTooltip('Ajouter au panier').at(i));
    await tester.pumpAndSettle();
  }
}

Future<void> _newCustomer(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Nouveau client'));
  await tester.tap(find.text('Nouveau client'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Prénom *'), 'Rasoa');
  await tester.enterText(find.widgetWithText(TextFormField, 'Nom *'), 'Be');
  await tester.enterText(find.widgetWithText(TextFormField, 'Téléphone'), '034 12 345 67');
  await tester.ensureVisible(find.text('Utiliser ce client'));
  await tester.tap(find.text('Utiliser ce client'));
  await tester.pumpAndSettle();
}

/// Dette : 100 000 payés maintenant, le reste en deux dates fixes (captures indépendantes du jour).
Future<void> _debtWithTwoDates(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Dette (avance)'));
  await tester.tap(find.text('Dette (avance)'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Payé maintenant'), '100000');
  await tester.pumpAndSettle();
  final cart = Provider.of<CartController>(tester.element(find.byType(PaymentPanel)), listen: false);
  cart.addInstallment();
  final [first, second] = cart.installments;
  cart.setInstallmentDate(first.id, DateTime(2029, 10, 30));
  cart.setInstallmentDate(second.id, DateTime(2029, 11, 30));
  await tester.pumpAndSettle();
}

/// Fait défiler la page jusqu'au bouton (les listes ne construisent que ce qui est à l'écran).
Future<void> _scrollTo(WidgetTester tester, String text) async {
  final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
  await tester.scrollUntilVisible(find.text(text), 300, scrollable: page);
  await tester.pumpAndSettle();
}

Finder _inDialog(String text) => find.descendant(of: find.byType(AppDialog).last, matching: find.text(text));

void main() {
  setUpAll(initFrenchDates);

  for (final size in [phone, desktop]) {
    final device = size == phone ? 'telephone' : 'ordinateur';

    testWidgets('$device : connexion', (tester) async {
      setScreenSize(tester, size);
      final api = FakeApi();
      stubDemoApi(api);
      await pumpApp(tester, api);
      await expectScreen(tester, api, 'parcours/$device/connexion');
    });

    testWidgets('$device : opération de stock', (tester) async {
      final api = await openScreen(tester, '/movements', size: size);
      await tester.tap(find.text('Opération de stock'));
      await settle(tester);
      await expectScreen(tester, api, 'parcours/$device/operation_stock');
    });

    testWidgets('$device : encaisser un paiement', (tester) async {
      final api = await openScreen(tester, '/sales/500', size: size);
      await _scrollTo(tester, 'Encaisser un paiement');
      await tester.tap(find.text('Encaisser un paiement'));
      await settle(tester);
      await expectScreen(tester, api, 'parcours/$device/encaisser_paiement');
    });

    testWidgets('$device : annuler une vente', (tester) async {
      final api = await openScreen(tester, '/sales/500', size: size);
      await _scrollTo(tester, 'Annuler la vente');
      await tester.tap(find.text('Annuler la vente'));
      await settle(tester);
      await expectScreen(tester, api, 'parcours/$device/annuler_vente');
    });
  }

  testWidgets('téléphone : filtres des mouvements', (tester) async {
    final api = await openScreen(tester, '/movements', size: phone);
    await tester.tap(find.text('Filtres'));
    await settle(tester);
    await expectScreen(tester, api, 'parcours/telephone/filtres_mouvements');
  });

  testWidgets('ordinateur : vente avec dette, échéancier, puis confirmation', (tester) async {
    final api = await openScreen(tester, '/sales/new', size: desktop);
    await _addToCart(tester, 2);
    await tester.enterText(find.widgetWithText(TextField, 'Description (taille, couleur...)').first, 'Taille M, noir');
    await _newCustomer(tester);
    await _debtWithTwoDates(tester);
    await expectScreen(tester, api, 'parcours/ordinateur/vente_dette_echeancier', unmount: false);

    final panel = find.ancestor(of: find.text('Paiement').first, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Valider la vente'), 200, scrollable: panel);
    await tester.tap(find.text('Valider la vente').last);
    await settle(tester);
    expect(_inDialog('Valider la vente'), findsOneWidget);
    await expectScreen(tester, api, 'parcours/ordinateur/vente_confirmation');
  });

  testWidgets('téléphone : vente en étapes (paiement en dette, puis résumé)', (tester) async {
    final api = await openScreen(tester, '/sales/new', size: phone);
    await _addToCart(tester, 2);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await _newCustomer(tester);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await _debtWithTwoDates(tester);
    await expectScreen(tester, api, 'parcours/telephone/vente_etape_paiement', unmount: false);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await expectScreen(tester, api, 'parcours/telephone/vente_etape_resume');
  });
}
