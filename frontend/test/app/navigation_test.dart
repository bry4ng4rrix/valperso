import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/app/navigation.dart';
import 'package:valmag/core/auth/current_user.dart';

import '../support/fixtures.dart';

void main() {
  final admin = CurrentUser.fromJson(meJson(admin: true));
  final vendeur = CurrentUser.fromJson(
    meJson(admin: false, id: 2, store: storeJson(id: 2, name: 'h109', central: false)),
  );

  List<String> labels(List<NavItem> items) => items.map((item) => item.label).toList();

  test('l\'administrateur voit toute la gestion', () {
    final items = labels(navItemsFor(admin));
    expect(
      items,
      containsAll([
        'Accueil',
        'Ventes',
        'Produits',
        'Mouvements',
        'Transferts',
        'Magasins',
        'Utilisateurs',
        'Journal d\'audit',
      ]),
    );
  });

  test('le vendeur ne voit que ce que ses permissions autorisent', () {
    final items = labels(navItemsFor(vendeur));
    expect(items, containsAll(['Accueil', 'Ventes', 'Produits', 'Mouvements', 'Clients', 'Messages']));
    expect(items, isNot(contains('Utilisateurs')));
    expect(items, isNot(contains('Magasins')));
    expect(items, isNot(contains('Transferts')));
    expect(items, isNot(contains('Journal d\'audit')));
  });

  test('une seule entrée « Ventes » (nouvelle vente et historique en onglets)', () {
    final items = labels(navItemsFor(admin));
    expect(items.where((label) => label == 'Ventes'), hasLength(1));
    expect(items, isNot(contains('Nouvelle vente')));
    expect(items, isNot(contains('Historique des ventes')));
  });

  test('barre du bas mobile : Accueil, Ventes, Produits, Clients, Plus', () {
    expect(labels(bottomNavItemsFor(vendeur)), ['Accueil', 'Ventes', 'Produits', 'Clients', 'Plus']);
    expect(labels(bottomNavItemsFor(admin)), ['Accueil', 'Ventes', 'Produits', 'Clients', 'Plus']);
  });

  test('entrée de menu correspondant à un chemin', () {
    expect(navItemForLocation('/', allNavItems)?.path, Routes.home);
    expect(navItemForLocation('/sales', allNavItems)?.path, Routes.sales);
    expect(navItemForLocation('/sales/new', allNavItems)?.path, Routes.sales);
    expect(navItemForLocation('/sales/12', allNavItems)?.path, Routes.sales);
    expect(navItemForLocation('/sales/12/invoice', allNavItems)?.path, Routes.sales);
    expect(navItemForLocation('/settings/company', allNavItems)?.path, Routes.settings);
    expect(isTopLevelLocation('/products', allNavItems), isTrue);
    expect(isTopLevelLocation('/products/3', allNavItems), isFalse);
  });

  test('garde des routes selon les permissions', () {
    expect(canOpenLocation('/users', admin), isTrue);
    expect(canOpenLocation('/users', vendeur), isFalse);
    expect(canOpenLocation('/products/new', vendeur), isFalse);
    expect(canOpenLocation('/products/5', vendeur), isTrue);
    expect(canOpenLocation('/products/5/edit', vendeur), isFalse);
    expect(canOpenLocation('/transfers/new', vendeur), isFalse);
    expect(canOpenLocation('/settings/company', vendeur), isTrue);
    expect(canOpenLocation('/settings/roles', vendeur), isFalse);
    expect(canOpenLocation('/customers/new', vendeur), isTrue);
    expect(canOpenLocation('/audit', vendeur), isFalse);
    expect(canOpenLocation('/more', vendeur), isTrue);
  });

  test('profil courant : permissions et magasin', () {
    expect(admin.isAdmin, isTrue);
    expect(admin.canChooseStore, isTrue);
    expect(admin.canCreateTransfer, isTrue);
    expect(vendeur.isAdmin, isFalse);
    expect(vendeur.store?.label, 'H109');
    expect(vendeur.fullName, 'Jean Rakoto');
  });
}
