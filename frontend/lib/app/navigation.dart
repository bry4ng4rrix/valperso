import 'package:flutter/material.dart';

import '../core/auth/current_user.dart';
import '../core/auth/permissions.dart';

/// Une entrée de menu. Elle n'est affichée que si l'utilisateur a la permission correspondante.
class NavItem {
  const NavItem({
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.isVisible,
    this.section = NavSection.main,
  });

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final bool Function(CurrentUser user) isVisible;
  final NavSection section;
}

enum NavSection {
  main('Activité'),
  inventory('Stock'),
  management('Gestion'),
  other('Autres');

  const NavSection(this.label);
  final String label;
}

/// Chemins des écrans principaux.
abstract final class Routes {
  static const login = '/login';
  static const home = '/';

  /// Écran « Ventes » : onglets Nouvelle vente et Historique.
  static const sales = '/sales';
  static const newSale = '/sales?tab=new';
  static const salesHistory = '/sales?tab=history';
  static const products = '/products';
  static const stock = '/stock';
  static const transfers = '/transfers';
  static const customers = '/customers';
  static const payments = '/payments';
  static const cash = '/cash';
  static const stores = '/stores';
  static const users = '/users';
  static const categories = '/categories';
  static const audit = '/audit';
  static const chat = '/chat';
  static const settings = '/settings';
  static const company = '/settings/company';
  static const roles = '/settings/roles';
  static const more = '/more';
}

bool _always(CurrentUser _) => true;

/// Tous les écrans accessibles depuis le menu, dans l'ordre d'affichage.
final List<NavItem> allNavItems = [
  const NavItem(
    label: 'Accueil',
    path: Routes.home,
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard,
    isVisible: _always,
  ),
  NavItem(
    label: 'Ventes',
    path: Routes.sales,
    icon: Icons.shopping_cart_outlined,
    selectedIcon: Icons.shopping_cart,
    isVisible: (user) => user.canAny(const [Perm.saleCreate, Perm.saleView]),
  ),
  NavItem(
    label: 'Clients',
    path: Routes.customers,
    icon: Icons.people_alt_outlined,
    selectedIcon: Icons.people_alt,
    isVisible: (user) => user.can(Perm.saleView),
  ),
  NavItem(
    label: 'Paiements et dettes',
    path: Routes.payments,
    icon: Icons.payments_outlined,
    selectedIcon: Icons.payments,
    isVisible: (user) => user.can(Perm.paymentView),
  ),
  NavItem(
    label: 'Caisse',
    path: Routes.cash,
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale,
    isVisible: (user) => user.can(Perm.cashView),
  ),
  NavItem(
    label: 'Produits',
    path: Routes.products,
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    section: NavSection.inventory,
    isVisible: (user) => user.can(Perm.productView),
  ),
  NavItem(
    label: 'Stock',
    path: Routes.stock,
    icon: Icons.warehouse_outlined,
    selectedIcon: Icons.warehouse,
    section: NavSection.inventory,
    isVisible: (user) => user.can(Perm.stockView),
  ),
  NavItem(
    label: 'Transferts',
    path: Routes.transfers,
    icon: Icons.swap_horiz_outlined,
    selectedIcon: Icons.swap_horiz,
    section: NavSection.inventory,
    isVisible: (user) => user.can(Perm.transferView) || user.canCreateTransfer,
  ),
  NavItem(
    label: 'Catégories',
    path: Routes.categories,
    icon: Icons.category_outlined,
    selectedIcon: Icons.category,
    section: NavSection.inventory,
    isVisible: (user) => user.can(Perm.productView) && user.canAny(const [Perm.productCreate, Perm.productUpdate]),
  ),
  NavItem(
    label: 'Magasins',
    path: Routes.stores,
    icon: Icons.storefront_outlined,
    selectedIcon: Icons.storefront,
    section: NavSection.management,
    isVisible: (user) => user.can(Perm.storeView),
  ),
  NavItem(
    label: 'Utilisateurs',
    path: Routes.users,
    icon: Icons.manage_accounts_outlined,
    selectedIcon: Icons.manage_accounts,
    section: NavSection.management,
    isVisible: (user) => user.can(Perm.userView),
  ),
  NavItem(
    label: 'Journal d\'audit',
    path: Routes.audit,
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    section: NavSection.management,
    isVisible: (user) => user.can(Perm.auditView),
  ),
  NavItem(
    label: 'Messages',
    path: Routes.chat,
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
    section: NavSection.other,
    isVisible: (user) => user.can(Perm.chatView),
  ),
  const NavItem(
    label: 'Paramètres',
    path: Routes.settings,
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    section: NavSection.other,
    isVisible: _always,
  ),
];

/// Entrées visibles pour cet utilisateur.
List<NavItem> navItemsFor(CurrentUser user) => allNavItems.where((item) => item.isVisible(user)).toList();

/// Barre du bas sur mobile : Accueil, Ventes, Produits, Clients, Plus.
/// Une entrée sans permission est retirée ; « Plus » donne accès au reste.
List<NavItem> bottomNavItemsFor(CurrentUser user) {
  const bottomPaths = [Routes.home, Routes.sales, Routes.products, Routes.customers];
  final visible = navItemsFor(user);
  return [
    for (final path in bottomPaths) ...visible.where((item) => item.path == path),
    const NavItem(
      label: 'Plus',
      path: Routes.more,
      icon: Icons.menu,
      selectedIcon: Icons.menu_open,
      isVisible: _always,
    ),
  ];
}

/// Entrée de menu correspondant à un chemin (la plus précise).
/// `/sales/12` (détail d'une vente) correspond à l'entrée « Ventes ».
NavItem? navItemForLocation(String location, Iterable<NavItem> items) {
  NavItem? best;
  for (final item in items) {
    final matches = item.path == Routes.home
        ? location == Routes.home
        : location == item.path || location.startsWith('${item.path}/');
    if (matches && (best == null || item.path.length > best.path.length)) best = item;
  }
  return best;
}

/// Écrans de premier niveau : la barre du bas y est affichée, pas sur les écrans de détail.
bool isTopLevelLocation(String location, Iterable<NavItem> items) =>
    location == Routes.more || items.any((item) => item.path == location);

/// Règles d'accès des sous-écrans (création, modification...) en plus de celles du menu.
final List<(RegExp, bool Function(CurrentUser user))> _routeRules = [
  (RegExp(r'^/sales/new$'), (user) => user.can(Perm.saleCreate)),
  (RegExp(r'^/sales/\d+'), (user) => user.can(Perm.saleView)),
  (RegExp(r'^/products/new$'), (user) => user.can(Perm.productCreate)),
  (RegExp(r'^/products/\d+/edit$'), (user) => user.can(Perm.productUpdate)),
  (RegExp(r'^/transfers/new$'), (user) => user.canCreateTransfer),
  (RegExp(r'^/transfers/\d+$'), (user) => user.can(Perm.transferView)),
  (RegExp(r'^/customers/new$'), (user) => user.can(Perm.saleCreate)),
  (RegExp(r'^/stores/new$'), (user) => user.can(Perm.storeCreate)),
  (RegExp(r'^/stores/\d+/edit$'), (user) => user.can(Perm.storeUpdate)),
  (RegExp(r'^/users/new$'), (user) => user.can(Perm.userCreate)),
  (RegExp(r'^/users/\d+/edit$'), (user) => user.can(Perm.userUpdate)),
  (RegExp(r'^/settings/company$'), (user) => user.can(Perm.companyView)),
  (RegExp(r'^/settings/roles$'), (user) => user.can(Perm.roleView)),
];

/// L'utilisateur peut-il ouvrir cet écran ? Sinon le routeur le renvoie à l'accueil.
/// (L'API vérifie de toute façon chaque permission.)
bool canOpenLocation(String location, CurrentUser user) {
  for (final (pattern, isAllowed) in _routeRules) {
    if (pattern.hasMatch(location) && !isAllowed(user)) return false;
  }
  final item = navItemForLocation(location, allNavItems);
  return item == null || item.isVisible(user);
}
