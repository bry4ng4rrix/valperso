import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/core/widgets/app_dialog.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

final _h109 = storeJson(id: 2, name: 'h109', central: false);
final _userRef = {
  'id': 1,
  'username': 'valenciaraza',
  'first_name': 'valencia',
  'last_name': 'raza',
  'role': {'id': 1, 'name': 'ADMIN'},
};

Future<FakeApi> _admin(WidgetTester tester, String route, void Function(FakeApi api) stub) async {
  setScreenSize(tester, desktopSize);
  final api = FakeApi();
  stubAdminBasics(api);
  api.on('GET', '/products', (_) => page([productJson()]));
  api.on('GET', '/products/10', (_) => productJson());
  api.on('GET', '/stock', (_) => page([stockLineJson()]));
  api.on('GET', '/stock/movements', (_) => page([]));
  api.on('GET', '/stock-transfers', (_) => page([]));
  stub(api);
  await pumpApp(tester, api, loggedIn: meJson(admin: true));
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
  await settle(tester);
  return api;
}

Finder _inDialog(String text) => find.descendant(of: find.byType(AppDialog).last, matching: find.text(text));

void main() {
  setUpAll(initFrenchDates);

  testWidgets('produit : le prix de vente inférieur au prix d\'achat est refusé avant l\'envoi', (tester) async {
    final api = await _admin(tester, '/products/new', (api) {
      api.on(
        'POST',
        '/products',
        (request) => {...productJson(id: 11, name: 'gomme'), ...?(request.data as Map?)?.cast()},
        status: 201,
      );
    });
    await tester.enterText(find.widgetWithText(TextFormField, 'Référence *'), 'G-01');
    await tester.enterText(find.widgetWithText(TextFormField, 'Nom du produit *'), 'Gomme');
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix d\'achat (prix de stock) *'), '1000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix de vente *'), '800');
    await tester.pumpAndSettle();
    expect(find.text('Prix de vente inférieur au prix d\'achat : non autorisé.'), findsOneWidget);

    await tester.tap(find.text('Créer le produit'));
    await settle(tester);
    expect(find.textContaining('Le prix de vente doit être supérieur ou égal au prix d\'achat'), findsOneWidget);
    expect(api.calls('POST', '/products'), isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Prix de vente *'), '1 500');
    await tester.tap(find.text('Créer le produit'));
    await settle(tester);
    final body = api.calls('POST', '/products').single.data as Map;
    expect(body, {
      'reference': 'G-01',
      'name': 'Gomme',
      'category_id': null,
      'purchase_price': 1000.0,
      'selling_price': 1500.0,
    });
  });

  testWidgets('produit : modification confirmée avec avant → après, seuls les champs modifiés sont envoyés', (
    tester,
  ) async {
    final api = await _admin(tester, '/products/10/edit', (api) {
      api.on('PATCH', '/products/10', (_) => productJson(price: 1200));
    });
    expect(find.text('Modifier le produit'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix de vente *'), '1200');
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer les modifications ?'), findsOneWidget);
    expect(find.text('1 000 Ar'), findsWidgets);
    expect(find.text('1 200 Ar'), findsOneWidget);
    expect(api.calls('PATCH', '/products/10'), isEmpty);
    await tester.tap(_inDialog('Enregistrer'));
    await settle(tester);
    expect(api.calls('PATCH', '/products/10').single.data, {'selling_price': 1200.0});
  });

  testWidgets('transfert : confirmation puis résultat avec les stocks des deux magasins', (tester) async {
    final api = await _admin(tester, '/transfers/new', (api) {
      api.on(
        'POST',
        '/stock-transfers',
        (_) => {
          'id': 1,
          'reference': 'TRF-2026-000001',
          'source_store': storeJson(),
          'destination_store': _h109,
          'status': 'COMPLETED',
          'items': [
            {
              'id': 1,
              'product': {'id': 10, 'reference': 'p-10', 'name': 'stylo bleu'},
              'quantity': 4,
            },
          ],
          'creator': _userRef,
          'created_at': '2026-10-02T10:00:00Z',
          'completed_at': '2026-10-02T10:00:00Z',
          'stock_levels': [
            {
              'product': {'id': 10, 'reference': 'p-10', 'name': 'stylo bleu'},
              'source_quantity': 6,
              'destination_quantity': 4,
            },
          ],
        },
        status: 201,
      );
    });
    expect(find.text('Stock Local'), findsWidgets, reason: 'source par défaut : le Stock Local');

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int?>, 'Magasin de destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('H109').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ajouter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Quantité'), '4');
    await tester.pumpAndSettle();
    expect(find.text('Source : 10 → 6'), findsOneWidget);

    await tester.ensureVisible(find.text('Valider le transfert'));
    await tester.tap(find.text('Valider le transfert'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmer le transfert ?'), findsOneWidget);
    expect(api.calls('POST', '/stock-transfers'), isEmpty);
    await tester.tap(_inDialog('Transférer'));
    await settle(tester);

    expect(api.calls('POST', '/stock-transfers').single.data, {
      'source_store_id': 1,
      'destination_store_id': 2,
      'items': [
        {'product_id': 10, 'quantity': 4},
      ],
    });
    expect(find.text('Transfert TRF-2026-000001 effectué'), findsOneWidget);
    expect(find.textContaining('Stock Local : 6'), findsOneWidget);
    expect(find.textContaining('H109 : 4'), findsOneWidget);
  });

  testWidgets('utilisateur : changement de rôle confirmé deux fois (avant → après)', (tester) async {
    final vendeur = {
      'id': 2,
      'username': 'vendeur1',
      'first_name': 'jean',
      'last_name': 'rakoto',
      'email': null,
      'phone': null,
      'role': {'id': 2, 'name': 'VENDEUR'},
      'store_id': 2,
      'store': _h109,
      'is_active': true,
    };
    final api = await _admin(tester, '/users/2', (api) {
      api.on('GET', '/users', (_) => page([vendeur]));
      api.on('GET', '/users/2', (_) => vendeur);
      api.on(
        'PUT',
        '/users/2/role',
        (_) => {
          ...vendeur,
          'role': {'id': 1, 'name': 'ADMIN'},
        },
      );
    });
    await tester.tap(find.text('Changer').first);
    await tester.pumpAndSettle();
    expect(find.text('Changer le rôle de Jean Rakoto ?'), findsOneWidget);
    expect(_inDialog('VENDEUR'), findsOneWidget);
    expect(_inDialog('ADMIN'), findsOneWidget);
    await tester.tap(_inDialog('Changer le rôle'));
    await tester.pumpAndSettle();
    expect(find.text('Êtes-vous vraiment sûr ?'), findsOneWidget);
    expect(api.calls('PUT', '/users/2/role'), isEmpty);
    await tester.tap(_inDialog('Changer le rôle'));
    await settle(tester);
    expect(api.calls('PUT', '/users/2/role').single.data, {'role': 'ADMIN'});
  });

  testWidgets('caisse : fermeture avec écart affiché et confirmé', (tester) async {
    final register = {
      'id': 3,
      'store_id': 1,
      'opened_by': 1,
      'closed_by': null,
      'opening_amount': 50000,
      'closing_amount': null,
      'expected_amount': 62000,
      'difference': null,
      'status': 'OPEN',
      'opened_at': '2026-10-02T07:00:00Z',
      'closed_at': null,
    };
    final api = await _admin(tester, '/cash', (api) {
      api.on('GET', '/cash/registers/current', (_) => {...register, 'opened_by': null, 'opened_automatically': true});
      api.on(
        'GET',
        '/cash/schedule',
        (_) => {'enabled': true, 'open_time': '06:00', 'close_time': '19:00', 'timezone': 'Indian/Antananarivo'},
      );
      api.on('GET', '/cash/registers/3/transactions', (_) => page([]));
      api.on(
        'POST',
        '/cash/registers/3/close',
        (_) => {
          ...register,
          'status': 'CLOSED',
          'closing_amount': 61000,
          'difference': -1000,
          'closed_at': '2026-10-02T18:00:00Z',
        },
      );
    });
    expect(find.text('Caisse ouverte'), findsOneWidget);
    expect(find.textContaining('Ouverture automatique à 06:00 et fermeture automatique à 19:00'), findsOneWidget);
    expect(find.textContaining('heure de Madagascar'), findsOneWidget);
    expect(find.textContaining('(automatique)'), findsOneWidget, reason: 'caisse ouverte automatiquement');
    expect(find.text('Stock Local'), findsWidgets, reason: 'le sélecteur affiche le magasin de la caisse');
    expect(find.text('62 000 Ar'), findsOneWidget);

    await tester.tap(find.text('Fermer la caisse'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Montant compté *'), '61000');
    await tester.pumpAndSettle();
    expect(find.textContaining('(manque)'), findsOneWidget);
    await tester.tap(_inDialog('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('Fermer la caisse ?'), findsOneWidget);
    expect(find.textContaining('un écart de'), findsOneWidget);
    expect(api.calls('POST', '/cash/registers/3/close'), isEmpty);
    await tester.tap(_inDialog('Fermer la caisse'));
    await settle(tester);
    expect(api.calls('POST', '/cash/registers/3/close').single.data, {'closing_amount': 61000.0});
  });

  testWidgets('stock : entrée confirmée (quantité avant → après)', (tester) async {
    final api = await _admin(tester, '/stock', (api) {
      api.on(
        'POST',
        '/stock/entry',
        (_) => {
          'id': 9,
          'product': {'id': 10, 'reference': 'p-10', 'name': 'stylo bleu'},
          'store': storeJson(),
          'user': _userRef,
          'type': 'ENTRY',
          'quantity': 20,
          'reason': null,
          'reference': 'BL-7',
          'created_at': '2026-10-02T10:00:00Z',
        },
        status: 201,
      );
    });
    await tester.tap(find.text('Opération de stock'));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Stylo bleu')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantité *'), '20');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Référence (bon de livraison, facture fournisseur...)'),
      'BL-7',
    );
    await tester.pumpAndSettle();
    expect(find.text('Après l\'opération : 30'), findsOneWidget);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Entrée de stock'), findsWidgets);
    expect(api.calls('POST', '/stock/entry'), isEmpty);
    await tester.tap(_inDialog('Enregistrer'));
    await settle(tester);
    expect(api.calls('POST', '/stock/entry').single.data, {
      'quantity': 20,
      'reference': 'BL-7',
      'product_id': 10,
      'store_id': 1,
      'reason': null,
    });
  });

  testWidgets('catégories : sans description, actions en icônes (modifier, désactiver)', (tester) async {
    final api = await _admin(tester, '/categories', (api) {
      api.on('DELETE', '/categories/1', (_) => null, status: 204);
      api.on(
        'PATCH',
        '/categories/1',
        (_) => {'id': 1, 'name': 'papeterie fine', 'description': null, 'is_active': true},
      );
    });
    expect(find.text('Papeterie'), findsOneWidget);
    expect(find.text('Description'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing, reason: 'plus de menu « ⋮ »');
    expect(find.byTooltip('Modifier'), findsOneWidget);
    expect(find.byTooltip('Désactiver'), findsOneWidget);

    await tester.tap(find.byTooltip('Désactiver'));
    await tester.pumpAndSettle();
    expect(find.text('Désactiver « Papeterie » ?'), findsOneWidget);
    expect(api.calls('DELETE', '/categories/1'), isEmpty);
    await tester.tap(_inDialog('Désactiver'));
    await settle(tester);
    expect(api.calls('DELETE', '/categories/1'), hasLength(1));

    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Description'), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, 'Nom *'), 'Papeterie fine');
    await tester.tap(_inDialog('Enregistrer'));
    await tester.pumpAndSettle();
    await tester.tap(_inDialog('Confirmer'));
    await settle(tester);
    expect(api.calls('PATCH', '/categories/1').single.data, {'name': 'Papeterie fine'});
  });
}
