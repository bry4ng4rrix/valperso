import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/core/widgets/app_dialog.dart';
import 'package:valmag/features/dashboard/bar_chart.dart';
import 'package:valmag/shared/widgets/stat_card.dart';
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
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix *'), '1000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix de vente *'), '800');
    await tester.pumpAndSettle();
    expect(find.text('Prix de vente inférieur au prix : non autorisé.'), findsOneWidget);

    await tester.tap(find.text('Créer le produit'));
    await settle(tester);
    expect(find.textContaining('Le prix de vente doit être supérieur ou égal au prix ('), findsOneWidget);
    expect(find.text('Prix d\'achat'), findsNothing, reason: 'le libellé est « Prix »');
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

  testWidgets('mouvements : type « Transfert », magasins d\'origine et de destination', (tester) async {
    final h109 = storeJson(id: 2, name: 'h109', central: false);
    Map<String, Object?> movement(int id, String type, int quantity, Map<String, Object?> store) => {
      'id': id,
      'product': {'id': 10, 'reference': 'p-10', 'name': 'stylo bleu'},
      'store': store,
      'user': _userRef,
      'type': type,
      'quantity': quantity,
      'reason': null,
      'reference': 'TRF-2026-000001',
      'source_store': storeJson(),
      'destination_store': h109,
      'created_at': '2026-10-02T10:00:00Z',
    };
    await _admin(tester, '/movements', (api) {
      api.on(
        'GET',
        '/stock/movements',
        (_) => page([
          movement(1, 'TRANSFER_OUT', -4, storeJson()),
          movement(2, 'TRANSFER_IN', 4, h109),
          {
            ...movement(3, 'ENTRY', 5, storeJson()),
            'reference': 'BL-1',
            'source_store': null,
            'destination_store': null,
          },
        ]),
      );
    });
    expect(find.text('Transfert'), findsNWidgets(2), reason: 'sortie et entrée du même transfert');
    expect(find.text('Magasin d\'origine'), findsOneWidget);
    expect(find.text('Magasin de destination'), findsOneWidget);
    expect(find.text('Motif'), findsNothing);
    expect(find.text('Référence'), findsNothing);
    expect(find.text('BL-1'), findsNothing, reason: 'la colonne Référence est retirée');
    expect(find.text('H109'), findsNWidgets(3), reason: 'magasin de l\'entrée + destination des deux lignes');
    expect(find.text('—'), findsNWidgets(2), reason: 'entrée simple : ni origine ni destination');
  });

  testWidgets('stock : entrée confirmée (quantité avant → après)', (tester) async {
    final api = await _admin(tester, '/movements', (api) {
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

  testWidgets('menu Stock : la page « Mouvements » remplace l\'onglet Stock', (tester) async {
    final api = await _admin(tester, '/', (api) {
      api.on(
        'GET',
        '/stock/movements',
        (_) => page([
          {
            'id': 1,
            'product': {'id': 10, 'reference': 'p-10', 'name': 'stylo bleu'},
            'store': storeJson(),
            'user': _userRef,
            'type': 'TRANSFER_OUT',
            'quantity': -4,
            'reason': 'transfert vers h109',
            'reference': 'trf-2026-000001',
            'created_at': '2026-10-02T10:00:00Z',
          },
        ]),
      );
    });
    expect(find.text('Mouvements'), findsOneWidget);
    expect(find.text('Stock'), findsNothing, reason: 'plus d\'entrée « Stock » dans le menu');

    await tester.tap(find.text('Mouvements'));
    await settle(tester);
    expect(find.text('Mouvements de stock'), findsOneWidget);
    expect(find.text('Transfert'), findsOneWidget, reason: 'sortie de transfert affichée « Transfert »');
    expect(find.text('Opération de stock'), findsOneWidget);
    expect(find.text('Stock par magasin'), findsNothing);
    expect(api.calls('GET', '/stock/movements'), isNotEmpty);
  });

  testWidgets('accueil « Stock faible » : Produits filtrés, tous les magasins', (tester) async {
    final api = await _admin(tester, '/', (_) {});
    await tester.tap(find.byTooltip('Afficher 4 de plus').first); // indicateurs masqués derrière « ⋯ »
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock faible').first); // la carte du tableau de bord
    await settle(tester);
    final request = api.calls('GET', '/stock').last;
    expect(request.queryParameters['low_stock'], true);
    expect(request.queryParameters.containsKey('store_id'), isFalse, reason: 'tous les magasins');
    final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Stock faible'));
    expect(chip.selected, isTrue);
  });

  testWidgets('accueil : produits les plus et les moins vendus, performance des magasins', (tester) async {
    await _admin(tester, '/', (_) {});
    expect(find.text('Stocks à surveiller (1)'), findsNothing, reason: 'remplacé par les graphiques de ventes');
    expect(find.text('Produits les plus vendus'), findsOneWidget);
    expect(find.text('Produits les moins vendus'), findsOneWidget);
    expect(find.text('Parmi les produits en stock'), findsOneWidget);
    expect(find.text('0 vendu'), findsOneWidget);
    expect(find.textContaining('40\u00A0en\u00A0stock'), findsOneWidget);
    expect(find.text('Performance des magasins'), findsOneWidget);
    expect(find.text('10\u00A0000 Ar'), findsOneWidget, reason: 'chiffre d\'affaires du Stock Local');
    expect(
      find.textContaining('1\u00A0vente · marge\u00A01\u00A0000 Ar · reste\u00A03\u00A0000 Ar · 50\u00A0en\u00A0stock'),
      findsOneWidget,
    );
    expect(find.byType(HorizontalBarChart), findsNWidgets(3));
  });

  testWidgets('accueil : 4 indicateurs et 3 actions rapides, « ⋯ » affiche les autres', (tester) async {
    await _admin(tester, '/', (_) {});
    for (final label in ['Chiffre d\'affaires', 'Ventes', 'Bénéfice estimé', 'Encaissé']) {
      expect(find.widgetWithText(StatCard, label), findsOneWidget, reason: label);
    }
    expect(find.widgetWithText(StatCard, 'Reste à encaisser'), findsNothing);
    expect(find.byType(QuickActionCard), findsNWidgets(3));
    // Bénéfice estimé = marge du stock actuel ; Encaissé = marge des produits vendus (sales_margin).
    expect(
      find.descendant(of: find.widgetWithText(StatCard, 'Bénéfice estimé'), matching: find.text('5\u00A0000 Ar')),
      findsOneWidget,
    );
    expect(find.text('Marge du stock actuel'), findsOneWidget);
    expect(
      find.descendant(of: find.widgetWithText(StatCard, 'Encaissé'), matching: find.text('4\u00A0000 Ar')),
      findsOneWidget,
    );
    expect(find.text('Marge des produits vendus'), findsOneWidget);

    await tester.tap(find.byTooltip('Afficher 4 de plus').first); // indicateurs
    await tester.pumpAndSettle();
    expect(find.widgetWithText(StatCard, 'Reste à encaisser'), findsOneWidget);
    expect(find.widgetWithText(StatCard, 'Produits indisponibles partout'), findsOneWidget);

    await tester.tap(find.byTooltip('Afficher 3 de plus')); // actions rapides : 6 au total pour l'admin
    await tester.pumpAndSettle();
    expect(find.byType(QuickActionCard), findsNWidgets(6));
    expect(find.widgetWithText(QuickActionCard, 'Caisse'), findsNothing);

    await tester.tap(find.byTooltip('Réduire').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(StatCard, 'Reste à encaisser'), findsNothing);
  });
}
