import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:valmag/shared/widgets/states.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

final _h109 = storeJson(id: 2, name: 'h109', central: false);
final _userRef = {
  'id': 2,
  'username': 'vendeur1',
  'first_name': 'jean',
  'last_name': 'rakoto',
  'role': {'id': 2, 'name': 'VENDEUR'},
};
final _appUser = {
  'id': 2,
  'username': 'vendeur1',
  'first_name': 'jean',
  'last_name': 'rakoto',
  'email': 'vendeur1@local.mg',
  'phone': '0341234567',
  'role': {'id': 2, 'name': 'VENDEUR'},
  'store_id': 2,
  'store': _h109,
  'is_active': true,
  'created_at': '2026-09-01T08:00:00Z',
};
final _transfer = {
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
  'created_at': '2026-10-01T10:00:00Z',
  'completed_at': '2026-10-01T10:00:00Z',
};
final _installments = [
  {
    'due_date': '2026-09-30',
    'amount': 1500,
    'paid_amount': 500,
    'remaining_amount': 1000,
    'status': 'PARTIAL',
    'is_overdue': true,
  },
  {
    'due_date': '2026-10-30',
    'amount': 1500,
    'paid_amount': 0,
    'remaining_amount': 1500,
    'status': 'UNPAID',
    'is_overdue': false,
  },
];
final _contact = {
  'id': 7,
  'first_name': 'rasoa',
  'last_name': 'be',
  'phone': '0341234567',
  'total_purchases': 3,
  'total_amount': 12000,
  'total_paid': 9000,
  'remaining_amount': 3000,
  'has_debt': true,
  'last_sale_date': '2026-10-02T09:30:00Z',
};

void _stubEverything(FakeApi api) {
  stubAdminBasics(api);
  // Dette de 3 000 en deux dates de remboursement (la première en retard), article avec description.
  final debtSale = {
    ...saleJson(total: 5000, paid: 2000, store: _h109),
    'items': [
      {
        'id': 1,
        'product_id': 10,
        'product_reference': 'p-10',
        'product_name': 'stylo bleu',
        'description': 'taille m, encre noire et très longue description pour vérifier le retour à la ligne',
        'quantity': 2,
        'unit_price': 1000,
        'total': 2000,
      },
    ],
    'installments': _installments,
  };
  api.on('GET', '/stores/2', (_) => _h109);
  api.on('GET', '/stores/2/employees', (_) => page([_appUser]));
  api.on('GET', '/products', (_) => page([productJson()]));
  api.on('GET', '/products/10', (_) => productJson());
  api.on('GET', '/stock', (_) => page([stockLineJson(), stockLineJson(id: 101, store: _h109, quantity: 0)]));
  api.on(
    'GET',
    '/stock/movements',
    (_) => page([
      {
        'id': 1,
        'product': {'id': 10, 'reference': 'p-10', 'name': 'stylo bleu'},
        'store': storeJson(),
        'user': _userRef,
        'type': 'ENTRY',
        'quantity': 20,
        'reason': 'livraison',
        'reference': 'BL-1',
        'created_at': '2026-10-01T08:00:00Z',
      },
    ]),
  );
  api.on('GET', '/stock/low-stock', (_) => page([stockLineJson(quantity: 2)]));
  api.on(
    'GET',
    '/dashboard/stock-value',
    (_) => {
      'stores': [
        {'store': storeJson(), 'quantity': 10, 'purchase_value': 6000, 'sale_value': 10000, 'potential_profit': 4000},
      ],
      'total': {'quantity': 10, 'purchase_value': 6000, 'sale_value': 10000, 'potential_profit': 4000},
    },
  );
  api.on('GET', '/stock-transfers', (_) => page([_transfer]));
  api.on('GET', '/stock-transfers/1', (_) => _transfer);
  api.on('GET', '/customers/contacts', (_) => page([_contact]));
  api.on('GET', '/customers/7', (_) => {'id': 7, 'first_name': 'rasoa', 'last_name': 'be', 'phone': '0341234567'});
  api.on(
    'GET',
    '/customers/7/debts',
    (_) => {
      'customer': {'id': 7, 'first_name': 'rasoa', 'last_name': 'be', 'phone': '0341234567'},
      'total_debt': 3000,
      'sales': [
        {
          'id': 500,
          'sale_number': 'FAC-2026-000500',
          'created_at': '2026-10-02T09:30:00Z',
          'store': _h109,
          'total': 5000,
          'amount_paid': 2000,
          'remaining_amount': 3000,
          'payment_status': 'PARTIAL',
          'payment_due_date': '2026-09-30',
          'payments': [],
          'installments': _installments,
        },
      ],
    },
  );
  api.on('GET', '/customers/7/sales', (_) => page([debtSale]));
  api.on('GET', '/sales/history', (_) => page([saleJson(), debtSale]));
  api.on('GET', '/sales/500', (_) => debtSale);
  api.on(
    'GET',
    '/sales/500/invoice',
    (_) => {
      'company': {
        'name': 'allsafe',
        'logo_url': null,
        'address': 'boutique h101',
        'city': 'antananarivo',
        'phone': '034 00 000 00',
        'email': null,
      },
      'invoice_number': 'FAC-2026-000500',
      'date': '2026-10-02T09:30:00Z',
      'store': {'name': 'h109', 'address': 'behoririka', 'phone': null},
      'user': _userRef,
      'customer': {'id': 7, 'first_name': 'rasoa', 'last_name': 'be', 'phone': '0341234567'},
      'lines': (debtSale['items'] as List),
      'subtotal': 5000,
      'discount_type': 'NONE',
      'discount_value': 0,
      'discount_amount': 0,
      'total': 5000,
      'payments': [
        {
          'id': 1,
          'sale_id': 500,
          'method': 'CASH',
          'amount': 2000,
          'reference': null,
          'creator': _userRef,
          'created_at': '2026-10-02T09:30:00Z',
        },
      ],
      'amount_paid': 2000,
      'remaining_amount': 3000,
      'payment_status': 'PARTIAL',
      'payment_due_date': '2026-10-30',
      'installments': _installments,
      'status': 'COMPLETED',
      'thank_you_message': ['Merci pour votre achat !', 'À bientôt chez allsafe.'],
    },
  );
  api.on(
    'GET',
    '/payments',
    (_) => page([
      {
        'id': 1,
        'sale_id': 500,
        'method': 'MOBILE_MONEY',
        'amount': 2000,
        'reference': 'MVOLA-1',
        'creator': _userRef,
        'created_at': '2026-10-02T09:30:00Z',
      },
    ]),
  );
  api.on('GET', '/users', (_) => page([_appUser]));
  api.on('GET', '/users/2', (_) => _appUser);
  final permissions = [
    {'id': 1, 'name': 'sale.create', 'description': 'créer une vente'},
    {'id': 2, 'name': 'sale.view', 'description': null},
  ];
  api.on(
    'GET',
    '/roles',
    (_) => [
      {'id': 1, 'name': 'ADMIN', 'description': 'administrateur', 'permissions': permissions},
      {
        'id': 2,
        'name': 'VENDEUR',
        'description': 'vendeur',
        'permissions': [permissions.first],
      },
    ],
  );
  api.on('GET', '/permissions', (_) => permissions);
  api.on(
    'GET',
    '/company',
    (_) => {
      'id': 1,
      'name': 'allsafe',
      'logo_url': null,
      'phone': null,
      'email': 'contact@allsafe.mg',
      'address': null,
      'city': 'antananarivo',
      'updated_at': '2026-10-01T08:00:00Z',
    },
  );
  api.on(
    'GET',
    '/audit',
    (_) => page([
      {
        'id': 1,
        'user_id': 1,
        'action': 'product.update',
        'entity_type': 'product',
        'entity_id': 10,
        'old_data': {'selling_price': '900'},
        'new_data': {'selling_price': '1000'},
        'ip_address': '127.0.0.1',
        'created_at': '2026-10-02T08:00:00Z',
      },
    ]),
  );
  final conversation = {
    'id': 1,
    'type': 'PRIVATE',
    'name': null,
    'created_by': 1,
    'created_at': '2026-10-01T08:00:00Z',
    'updated_at': '2026-10-02T08:00:00Z',
    'members': [
      {
        'user': {
          'id': 1,
          'username': 'valenciaraza',
          'first_name': 'valencia',
          'last_name': 'raza',
          'role': {'id': 1, 'name': 'ADMIN'},
        },
        'joined_at': '2026-10-01T08:00:00Z',
        'last_read_at': null,
      },
      {'user': _userRef, 'joined_at': '2026-10-01T08:00:00Z', 'last_read_at': null},
    ],
    'unread_count': 2,
  };
  api.on('GET', '/chat/conversations', (_) => [conversation]);
  api.on('GET', '/chat/conversations/1', (_) => conversation);
  api.on(
    'GET',
    '/chat/conversations/1/messages',
    (_) => page([
      {
        'id': 2,
        'conversation_id': 1,
        'sender_id': 2,
        'content': 'Bonjour, il reste des stylos ?',
        'is_deleted': false,
        'created_at': '2026-10-02T08:01:00Z',
        'updated_at': '2026-10-02T08:01:00Z',
      },
      {
        'id': 1,
        'conversation_id': 1,
        'sender_id': 1,
        'content': null,
        'is_deleted': true,
        'created_at': '2026-10-02T08:00:00Z',
        'updated_at': '2026-10-02T08:00:00Z',
      },
    ]),
  );
  api.on('POST', '/chat/conversations/1/read', (_) => null, status: 204);
}

const _routes = [
  '/',
  '/sales/new',
  '/sales',
  '/sales/500',
  '/sales/500/invoice',
  '/products',
  '/products/10',
  '/products/new',
  '/products/10/edit',
  '/movements',
  '/products?state=low',
  '/transfers',
  '/transfers/1',
  '/transfers/new',
  '/customers',
  '/customers/7',
  '/customers/new',
  '/payments',
  '/stores',
  '/stores/2',
  '/stores/new',
  '/stores/2/edit',
  '/users',
  '/users/2',
  '/users/new',
  '/users/2/edit',
  '/categories',
  '/audit',
  '/chat',
  '/chat/1',
  '/settings',
  '/settings/company',
  '/settings/roles',
  '/more',
];

/// Écrans accessibles à un vendeur (permissions par défaut).
const _sellerRoutes = [
  '/',
  '/sales/new',
  '/sales',
  '/sales/500',
  '/sales/500/invoice',
  '/products',
  '/products/10',
  '/movements',
  '/products?state=low',
  '/customers',
  '/customers/7',
  '/customers/new',
  '/payments',
  '/chat',
  '/chat/1',
  '/settings',
  '/settings/company',
  '/more',
];

Future<void> _visitAll(WidgetTester tester, {bool seller = false}) async {
  final api = FakeApi();
  _stubEverything(api);
  await pumpApp(tester, api, loggedIn: seller ? meJson(admin: false, id: 2, store: _h109) : meJson(admin: true));
  for (final route in seller ? _sellerRoutes : _routes) {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'écran $route');
    expect(find.byType(ErrorState), findsNothing, reason: 'écran $route : erreur de chargement');
    expect(api.unmatched, isEmpty, reason: 'écran $route : routes non simulées');
  }
}

void main() {
  setUpAll(initFrenchDates);

  testWidgets('tous les écrans s\'affichent sans erreur sur ordinateur', (tester) async {
    setScreenSize(tester, desktopSize);
    await _visitAll(tester);
  });

  testWidgets('tous les écrans s\'affichent sans erreur sur tablette', (tester) async {
    setScreenSize(tester, const Size(800, 1100));
    await _visitAll(tester);
  });

  testWidgets('tous les écrans s\'affichent sans erreur sur mobile', (tester) async {
    setScreenSize(tester, mobileSize);
    await _visitAll(tester);
  });

  testWidgets('petit téléphone (360 px) : aucun débordement', (tester) async {
    setScreenSize(tester, const Size(360, 720));
    await _visitAll(tester);
  });

  testWidgets('vendeur : ses écrans s\'affichent sans erreur (mobile)', (tester) async {
    setScreenSize(tester, mobileSize);
    await _visitAll(tester, seller: true);
  });

  testWidgets('détail de vente : échéancier avec état de chaque date, description de l\'article', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = FakeApi();
    _stubEverything(api);
    await pumpApp(tester, api, loggedIn: meJson(admin: true));
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/sales/500');
    await settle(tester);

    expect(find.text('Échéancier'), findsOneWidget);
    expect(find.text('1. 30/09/2026'), findsOneWidget);
    expect(find.text('En retard'), findsOneWidget, reason: 'première date passée, pas encore soldée');
    expect(find.text('À payer'), findsOneWidget);
    expect(find.text('Prochaine échéance'), findsOneWidget);
    expect(find.textContaining('Taille m, encre noire'), findsOneWidget);
  });

  testWidgets('vendeur : un écran non autorisé renvoie à l\'accueil', (tester) async {
    setScreenSize(tester, mobileSize);
    final api = FakeApi();
    _stubEverything(api);
    await pumpApp(tester, api, loggedIn: meJson(admin: false, id: 2, store: _h109));
    for (final route in ['/users', '/stores/new', '/audit', '/settings/roles', '/products/new']) {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
      await settle(tester);
      expect(find.text('Bonjour Jean Rakoto'), findsOneWidget, reason: route);
    }
  });
}
