@Tags(['visual'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import 'visual_helpers.dart';

/// Tous les écrans, comparés à leur capture de référence (test/visual/goldens) :
/// téléphone et ordinateur, thème sombre (et clair pour une sélection), administrateur et vendeur.

/// Écran : route à ouvrir et nom de la capture.
typedef Screen = ({String route, String name});

const adminScreens = <Screen>[
  (route: '/', name: 'accueil'),
  (route: '/sales/new', name: 'vente_nouvelle_vide'),
  (route: '/sales', name: 'ventes_historique'),
  (route: '/sales/500', name: 'vente_detail_dette'),
  (route: '/sales/499', name: 'vente_detail_annulee'),
  (route: '/sales/500/invoice', name: 'facture'),
  (route: '/products', name: 'produits'),
  (route: '/products?state=low', name: 'produits_stock_faible'),
  (route: '/products/10', name: 'produit_detail'),
  (route: '/products/new', name: 'produit_nouveau'),
  (route: '/products/10/edit', name: 'produit_modifier'),
  (route: '/movements', name: 'mouvements'),
  (route: '/transfers', name: 'transferts'),
  (route: '/transfers/2', name: 'transfert_detail'),
  (route: '/transfers/new', name: 'transfert_nouveau'),
  (route: '/customers', name: 'clients'),
  (route: '/customers/7', name: 'client_detail'),
  (route: '/customers/new', name: 'client_nouveau'),
  (route: '/payments', name: 'paiements'),
  (route: '/stores', name: 'magasins'),
  (route: '/stores/2', name: 'magasin_detail'),
  (route: '/stores/new', name: 'magasin_nouveau'),
  (route: '/users', name: 'utilisateurs'),
  (route: '/users/4', name: 'utilisateur_detail'),
  (route: '/users/new', name: 'utilisateur_nouveau'),
  (route: '/categories', name: 'categories'),
  (route: '/audit', name: 'audit'),
  (route: '/chat', name: 'messages'),
  (route: '/chat/1', name: 'conversation'),
  (route: '/settings', name: 'parametres'),
  (route: '/settings/company', name: 'societe'),
  (route: '/settings/roles', name: 'roles_permissions'),
];

/// Écrans revus aussi en thème clair.
const lightScreens = <Screen>[
  (route: '/', name: 'accueil'),
  (route: '/sales', name: 'ventes_historique'),
  (route: '/sales/500', name: 'vente_detail_dette'),
  (route: '/products', name: 'produits'),
  (route: '/movements', name: 'mouvements'),
  (route: '/customers/7', name: 'client_detail'),
  (route: '/settings', name: 'parametres'),
];

/// Écrans longs, capturés aussi en page entière sur téléphone (contenu sous l'écran).
const longScreens = <Screen>[
  (route: '/', name: 'accueil'),
  (route: '/sales/500', name: 'vente_detail_dette'),
  (route: '/sales/500/invoice', name: 'facture'),
  (route: '/customers/7', name: 'client_detail'),
  (route: '/products/10', name: 'produit_detail'),
  (route: '/stores/2', name: 'magasin_detail'),
  (route: '/transfers/2', name: 'transfert_detail'),
  (route: '/settings', name: 'parametres'),
];

const sellerScreens = <Screen>[
  (route: '/', name: 'accueil'),
  (route: '/more', name: 'plus'),
  (route: '/payments', name: 'paiements'),
];

void main() {
  setUpAll(initFrenchDates);

  group('téléphone, page entière', () {
    for (final screen in longScreens) {
      testWidgets(screen.name, (tester) async {
        final api = await openScreen(tester, screen.route, size: phoneLong);
        await expectScreen(tester, api, '${folder(phoneLong)}/${screen.name}');
      });
    }
  });

  for (final size in [phone, desktop]) {
    group(size == phone ? 'téléphone' : 'ordinateur', () {
      for (final screen in adminScreens) {
        testWidgets('${screen.name} (sombre)', (tester) async {
          final api = await openScreen(tester, screen.route, size: size);
          await expectScreen(tester, api, '${folder(size)}/${screen.name}');
        });
      }
      for (final screen in lightScreens) {
        testWidgets('${screen.name} (clair)', (tester) async {
          final api = await openScreen(tester, screen.route, size: size, light: true);
          await expectScreen(tester, api, '${folder(size, light: true)}/${screen.name}');
        });
      }
      for (final screen in sellerScreens) {
        if (screen.route == '/more' && size != phone) continue; // page « Plus » : téléphone seulement
        testWidgets('vendeur : ${screen.name}', (tester) async {
          final api = await openScreen(tester, screen.route, size: size, seller: true);
          await expectScreen(tester, api, '${folder(size, seller: true)}/${screen.name}');
        });
      }
    });
  }
}
