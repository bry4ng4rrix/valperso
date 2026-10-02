import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/core/widgets/app_dialog.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

final _h109 = storeJson(id: 2, name: 'h109', central: false);

/// Vendeur de H109, avec un produit en stock (5 unités à 1 000 Ar).
FakeApi _sellerApi() {
  final api = FakeApi();
  api.on('GET', '/sales/history', (_) => page([]));
  api.on('GET', '/stock/low-stock', (_) => page([]));
  api.on('GET', '/stock', (request) {
    expect(request.queryParameters['store_id'], 2, reason: 'le catalogue est celui du magasin du vendeur');
    return page([
      stockLineJson(
        product: productJson(id: 10, name: 'stylo bleu', price: 1000),
        store: _h109,
        quantity: 5,
      ),
      stockLineJson(
        id: 101,
        product: productJson(id: 11, name: 'cahier', price: 2500),
        store: _h109,
        quantity: 0,
      ),
    ]);
  });
  return api;
}

Future<void> _openNewSale(WidgetTester tester) async {
  await tester.tap(find.text('Nouvelle vente').first);
  await settle(tester);
  expect(find.text('Stylo bleu'), findsOneWidget);
}

Future<void> _fillNewCustomer(WidgetTester tester, {String? phone}) async {
  await tester.ensureVisible(find.text('Nouveau client'));
  await tester.tap(find.text('Nouveau client'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Prénom *'), 'Rasoa');
  await tester.enterText(find.widgetWithText(TextFormField, 'Nom *'), 'Be');
  if (phone != null) await tester.enterText(find.widgetWithText(TextFormField, 'Téléphone'), phone);
  await tester.ensureVisible(find.text('Utiliser ce client'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Utiliser ce client'));
  await tester.pumpAndSettle();
}

Finder get _validateButton =>
    find.ancestor(of: find.text('Valider la vente'), matching: find.byWidgetPredicate((w) => w is FilledButton)).first;

/// Fait défiler le panneau de droite (grand écran) jusqu'au bouton de validation.
Future<void> _showValidateButton(WidgetTester tester) async {
  final panel = find.ancestor(of: find.text('Paiement').first, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(find.text('Valider la vente'), 200, scrollable: panel);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initFrenchDates);

  testWidgets('grand écran : la vente n\'est envoyée qu\'après confirmation, une seule fois', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = _sellerApi();
    api.on('POST', '/sales', (_) => saleJson(total: 2000, paid: 2000, store: _h109), status: 201);
    await pumpApp(tester, api, loggedIn: meJson(admin: false, id: 2, store: _h109));
    await _openNewSale(tester);

    // Produit épuisé : impossible à ajouter.
    expect(find.text('P-11 · Épuisé'), findsOneWidget);

    // 2 stylos.
    await tester.tap(find.byTooltip('Ajouter au panier').first);
    await tester.pump();
    await tester.tap(find.byTooltip('Ajouter au panier').first);
    await tester.pumpAndSettle();
    expect(find.text('1 000 Ar × 2 = 2 000 Ar'), findsOneWidget);

    // Sans client, le bouton reste actif mais la validation explique ce qui manque.
    await _fillNewCustomer(tester);
    expect(find.text('Rasoa Be'), findsOneWidget);

    // Validation : la confirmation s'affiche, rien n'est envoyé.
    await _showValidateButton(tester);
    await tester.tap(_validateButton);
    await tester.pumpAndSettle();
    expect(find.text('Valider la vente ?'), findsOneWidget);
    expect(api.calls('POST', '/sales'), isEmpty);

    // Annuler : toujours rien d'envoyé.
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.calls('POST', '/sales'), isEmpty);

    // Confirmer : un seul envoi, avec les bonnes données.
    await tester.tap(_validateButton);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AppDialog), matching: find.text('Valider la vente')));
    await settle(tester);

    final posts = api.calls('POST', '/sales');
    expect(posts, hasLength(1));
    final body = posts.single.data as Map;
    expect(body['store_id'], isNull, reason: 'un vendeur vend toujours dans son magasin (imposé par le serveur)');
    expect(body['customer'], {'first_name': 'Rasoa', 'last_name': 'Be', 'phone': null});
    expect(body['items'], [
      {'product_id': 10, 'quantity': 2},
    ]);
    expect(body['discount_type'], 'NONE');
    expect(body['payment'], {'method': 'CASH', 'amount': null});
    expect(body.containsKey('installments'), isFalse);

    expect(find.text('Vente enregistrée'), findsWidgets);
    expect(find.text('FAC-2026-000500'), findsOneWidget);
    expect(find.text('Voir la facture'), findsOneWidget);
    expect(find.text('Nouvelle vente'), findsWidgets);
  });

  testWidgets('avance sans téléphone : la vente est bloquée avant l\'envoi', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = _sellerApi();
    await pumpApp(tester, api, loggedIn: meJson(admin: false, id: 2, store: _h109));
    await _openNewSale(tester);
    await tester.tap(find.byTooltip('Ajouter au panier').first);
    await tester.pumpAndSettle();
    await _fillNewCustomer(tester);

    await tester.ensureVisible(find.text('Dette (avance)'));
    await tester.tap(find.text('Dette (avance)'));
    await tester.pumpAndSettle();
    final paid = find.widgetWithText(TextFormField, 'Payé maintenant');
    expect(tester.widget<TextFormField>(paid).controller!.text, '1\u00A0000', reason: 'pré-rempli avec le total');
    await tester.enterText(paid, '400');
    await tester.pumpAndSettle();
    expect(find.text('Avance 400 Ar — reste à payer 600 Ar'), findsOneWidget);
    expect(find.textContaining('Le téléphone du client est obligatoire'), findsWidgets);

    await _showValidateButton(tester);
    await tester.tap(_validateButton);
    await tester.pumpAndSettle();
    expect(find.text('Valider la vente ?'), findsNothing);
    expect(api.calls('POST', '/sales'), isEmpty);
  });

  testWidgets('vente refusée : message clair, le panier est conservé', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = _sellerApi();
    api.onError('POST', '/sales', status: 400, code: 'INVALID_PAYMENT', detail: 'Le paiement dépasse le total');
    await pumpApp(tester, api, loggedIn: meJson(admin: false, id: 2, store: _h109));
    await _openNewSale(tester);
    await tester.tap(find.byTooltip('Ajouter au panier').first);
    await tester.pumpAndSettle();
    await _fillNewCustomer(tester);
    await _showValidateButton(tester);
    await tester.tap(_validateButton);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AppDialog), matching: find.text('Valider la vente')));
    await settle(tester);

    expect(api.calls('POST', '/sales'), hasLength(1));
    expect(find.textContaining('Le paiement dépasse le total'), findsOneWidget);
    expect(find.text('Panier (1)'), findsOneWidget);
  });

  testWidgets('mobile : étapes Produits → Client → Paiement → Résumé', (tester) async {
    setScreenSize(tester, mobileSize);
    final api = _sellerApi();
    api.on('POST', '/sales', (_) => saleJson(total: 1000, paid: 1000, store: _h109), status: 201);
    await pumpApp(tester, api, loggedIn: meJson(admin: false, id: 2, store: _h109));

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Ventes')));
    await settle(tester);
    final next = find.widgetWithText(FilledButton, 'Suivant');
    expect(tester.widget<FilledButton>(next).onPressed, isNull, reason: 'panier vide : étape suivante bloquée');

    await tester.tap(find.byTooltip('Ajouter au panier').first);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNull, reason: 'pas encore de client');

    await _fillNewCustomer(tester, phone: '034 12 345 67');
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Payé'), findsOneWidget);
    expect(find.text('Dette (avance)'), findsOneWidget);
    expect(find.text('Mode de paiement'), findsNothing, reason: 'plus de choix du mode de paiement');
    expect(find.text('Mobile money'), findsNothing);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Résumé'), findsWidgets);

    await tester.tap(_validateButton);
    await tester.pumpAndSettle();
    expect(find.text('Valider la vente ?'), findsOneWidget);
    expect(api.calls('POST', '/sales'), isEmpty);
    await tester.tap(find.descendant(of: find.byType(AppDialog), matching: find.text('Valider la vente')));
    await settle(tester);
    expect(api.calls('POST', '/sales'), hasLength(1));
    expect((api.calls('POST', '/sales').single.data as Map)['customer'], {
      'first_name': 'Rasoa',
      'last_name': 'Be',
      'phone': '034 12 345 67',
    });
    expect(find.text('Vente enregistrée'), findsWidgets);
  });

  testWidgets('écran Ventes : onglets Nouvelle vente et Historique, le panier est conservé', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = _sellerApi();
    api.on('GET', '/sales/history', (_) => page([saleJson(store: _h109)]));
    await pumpApp(tester, api, loggedIn: meJson(admin: false, id: 2, store: _h109));

    // Une seule entrée « Ventes » dans le menu.
    expect(find.text('Ventes'), findsOneWidget);
    await tester.tap(find.text('Ventes'));
    await settle(tester);
    expect(find.widgetWithText(Tab, 'Nouvelle vente'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Historique'), findsOneWidget);
    expect(find.text('Stylo bleu'), findsOneWidget, reason: 'onglet Nouvelle vente ouvert par défaut');

    await tester.tap(find.byTooltip('Ajouter au panier').first);
    await tester.pumpAndSettle();
    expect(find.text('Panier (1)'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Historique'));
    await settle(tester);
    expect(find.text('FAC-2026-000500'), findsOneWidget);
    expect(find.text('Historique des ventes'), findsNothing, reason: 'pas de second titre dans l\'onglet');

    await tester.tap(find.widgetWithText(Tab, 'Nouvelle vente'));
    await settle(tester);
    expect(find.text('Panier (1)'), findsOneWidget, reason: 'le panier en cours est conservé');
  });

  testWidgets('lien direct vers l\'historique depuis l\'accueil', (tester) async {
    setScreenSize(tester, mobileSize);
    final api = _sellerApi();
    api.on('GET', '/sales/history', (_) => page([saleJson(store: _h109)]));
    await pumpApp(tester, api, loggedIn: meJson(admin: false, id: 2, store: _h109));
    await tester.tap(find.text('Historique des ventes'));
    await settle(tester);
    expect(find.text('FAC-2026-000500'), findsWidgets);
    final selected = tester.widget<TabBar>(find.byType(TabBar)).controller!.index;
    expect(selected, 1);
  });

  testWidgets('dette sans avance : champ vidé, rien n\'est encaissé, tout le total reste à payer', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = _sellerApi();
    api.on('POST', '/sales', (_) => saleJson(total: 2000, paid: 0, store: _h109), status: 201);
    await pumpApp(tester, api, loggedIn: meJson(admin: false, id: 2, store: _h109));
    await _openNewSale(tester);
    await tester.tap(find.byTooltip('Ajouter au panier').first);
    await tester.tap(find.byTooltip('Ajouter au panier').first);
    await tester.pumpAndSettle();
    await _fillNewCustomer(tester, phone: '034 12 345 67');

    expect(find.text('Remise'), findsNothing, reason: 'la carte Remise est remplacée');
    await tester.ensureVisible(find.text('Dette (avance)'));
    await tester.tap(find.text('Dette (avance)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Payé maintenant'), '');
    await tester.pumpAndSettle();
    expect(find.text('Dette sans avance : reste à payer 2\u00A0000 Ar'), findsOneWidget);

    expect(find.text('Dates de remboursement'), findsOneWidget);
    await tester.ensureVisible(find.text('Choisir la date'));
    await tester.tap(find.text('Choisir la date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await _showValidateButton(tester);
    await tester.tap(_validateButton);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AppDialog), matching: find.text('Valider la vente')));
    await settle(tester);
    final body = api.calls('POST', '/sales').single.data as Map;
    expect(body['payment'], {'method': 'CREDIT', 'amount': null});
    final installments = body['installments'] as List;
    expect(installments.single['amount'], 2000.0, reason: 'une seule date : tout le reste à payer');
    expect(installments.single['due_date'], isNotNull);
    expect(body['discount_type'], 'NONE');
  });

  testWidgets('dette avec avance : description d\'article et deux dates de remboursement', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = _sellerApi();
    api.on('POST', '/sales', (_) => saleJson(total: 2000, paid: 500, store: _h109), status: 201);
    await pumpApp(tester, api, loggedIn: meJson(admin: false, id: 2, store: _h109));
    await _openNewSale(tester);
    await tester.tap(find.byTooltip('Ajouter au panier').first);
    await tester.tap(find.byTooltip('Ajouter au panier').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Description (taille, couleur...)'), 'Taille M, noir');
    await _fillNewCustomer(tester, phone: '034 12 345 67');

    await tester.ensureVisible(find.text('Dette (avance)'));
    await tester.tap(find.text('Dette (avance)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Payé maintenant'), '500');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choisir la date'));
    await tester.tap(find.text('Choisir la date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ajouter une date'));
    await tester.tap(find.text('Ajouter une date'));
    await tester.pumpAndSettle();
    expect(find.text('Total prévu : 1\u00A0500 Ar sur 1\u00A0500 Ar'), findsOneWidget, reason: '750 + 750');

    await _showValidateButton(tester);
    await tester.tap(_validateButton);
    await tester.pumpAndSettle();
    expect(find.text('Taille M, noir'), findsWidgets, reason: 'la description figure dans le récapitulatif');
    await tester.tap(find.descendant(of: find.byType(AppDialog), matching: find.text('Valider la vente')));
    await settle(tester);

    final body = api.calls('POST', '/sales').single.data as Map;
    expect((body['items'] as List).first['description'], 'Taille M, noir');
    expect(body['payment'], {'method': 'CASH', 'amount': 500.0});
    final installments = (body['installments'] as List).cast<Map>();
    expect(installments.map((i) => i['amount']), [750.0, 750.0]);
    final dates = installments.map((i) => DateTime.parse(i['due_date'] as String)).toList();
    expect(dates.last.isAfter(dates.first), isTrue, reason: 'la seconde date suit la première d\'un mois');
  });
}
