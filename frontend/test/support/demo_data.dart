import 'fake_api.dart';
import 'fixtures.dart';

/// Données de démonstration réalistes (boutique de vêtements, quatre magasins) pour les tests visuels.
///
/// Les dates n'ont pas de fuseau horaire (affichage identique sur toute machine) et les échéances
/// à venir sont lointaines : les captures ne changent pas avec la date du jour.

final demoCentral = storeJson();
final demoH109 = storeJson(id: 2, name: 'h109', central: false);
final demoC209 = storeJson(id: 3, name: 'c209', central: false);
final demoCity = storeJson(id: 4, name: 'la city', central: false);
final demoStores = [demoCentral, demoH109, demoC209, demoCity];

final demoAdminRef = {
  'id': 1,
  'username': 'valencia',
  'first_name': 'valheri',
  'last_name': 'wear',
  'role': {'id': 1, 'name': 'ADMIN'},
};
final demoSellerRef = {
  'id': 4,
  'username': 'fleur',
  'first_name': 'fleur',
  'last_name': 'rasoanaivo',
  'role': {'id': 2, 'name': 'VENDEUR'},
};

Map<String, Object?> demoMe({bool admin = true}) => {
  ...meJson(admin: admin, id: admin ? 1 : 4, store: admin ? null : demoH109),
  'username': admin ? 'valencia' : 'fleur',
  'first_name': admin ? 'valheri' : 'fleur',
  'last_name': admin ? 'wear' : 'rasoanaivo',
  'email': admin ? 'valenciaraza@gmail.com' : 'fleur@valheri.mg',
};

final demoCategories = [
  {'id': 1, 'name': 'abaya', 'description': null, 'is_active': true},
  {'id': 2, 'name': 'veste', 'description': null, 'is_active': true},
  {'id': 3, 'name': 'robe', 'description': null, 'is_active': true},
  {'id': 4, 'name': 'accessoires', 'description': null, 'is_active': false},
];

Map<String, Object?> _product(int id, String reference, String name, int category, double cost, double price) => {
  'id': id,
  'reference': reference,
  'name': name,
  'category': {'id': category, 'name': demoCategories[category - 1]['name']},
  'purchase_price': cost,
  'selling_price': price,
  'is_active': true,
};

final demoProducts = [
  _product(10, 'ab-001', 'abaya brodée', 1, 150000, 200000),
  _product(11, 've-014', 'veste tweed', 2, 60000, 85000),
  _product(12, 'ro-003', 'robe vintage', 3, 30000, 45000),
  _product(13, 'ab-007', 'yara', 1, 90000, 120000),
  _product(14, 've-020', 'veste femme longue en laine avec doublure satinée', 2, 70000, 95000),
  _product(15, 'ac-002', 'foulard soie', 4, 8000, 15000),
];

Map<String, Object?> _line(int id, int product, Map<String, Object?> store, int quantity) {
  final item = demoProducts.firstWhere((p) => p['id'] == product);
  final cost = item['purchase_price']! as double;
  final price = item['selling_price']! as double;
  return {
    'id': id,
    'product': item,
    'store': store,
    'quantity': quantity,
    'alert_threshold': 5,
    'low_stock': quantity <= 5,
    'out_of_stock': quantity == 0,
    'updated_at': '2026-10-02T10:00:00',
    'purchase_value': cost * quantity,
    'sale_value': price * quantity,
    'potential_profit': (price - cost) * quantity,
  };
}

final demoStockLines = [
  _line(100, 10, demoCentral, 12),
  _line(101, 10, demoH109, 3),
  _line(102, 11, demoCentral, 20),
  _line(103, 11, demoC209, 4),
  _line(104, 12, demoH109, 9),
  _line(105, 13, demoCentral, 16),
  _line(106, 14, demoCity, 2),
  _line(107, 15, demoC209, 30),
];

Map<String, Object?> _movement(
  int id,
  String type,
  int product,
  Map<String, Object?> store,
  int quantity, {
  String? reason,
  String? reference,
  Map<String, Object?>? source,
  Map<String, Object?>? destination,
  String date = '2026-10-02T10:00:00',
}) {
  final item = demoProducts.firstWhere((p) => p['id'] == product);
  return {
    'id': id,
    'product': {'id': product, 'reference': item['reference'], 'name': item['name']},
    'store': store,
    'user': demoAdminRef,
    'type': type,
    'quantity': quantity,
    'reason': reason,
    'reference': reference,
    'source_store': source,
    'destination_store': destination,
    'created_at': date,
  };
}

final demoMovements = [
  _movement(9, 'SALE', 10, demoH109, -1, reference: 'FAC-2026-000502', date: '2026-10-02T16:20:00'),
  _movement(
    8,
    'TRANSFER_IN',
    11,
    demoC209,
    4,
    reference: 'TRF-2026-000002',
    source: demoCentral,
    destination: demoC209,
    date: '2026-10-02T14:00:00',
  ),
  _movement(
    7,
    'TRANSFER_OUT',
    11,
    demoCentral,
    -4,
    reference: 'TRF-2026-000002',
    source: demoCentral,
    destination: demoC209,
    date: '2026-10-02T14:00:00',
  ),
  _movement(6, 'LOSS', 15, demoC209, -2, reason: 'tache sur le tissu', date: '2026-10-02T11:00:00'),
  _movement(5, 'ADJUSTMENT', 12, demoH109, 1, reason: 'inventaire', date: '2026-10-02T09:00:00'),
  _movement(4, 'ENTRY', 10, demoCentral, 12, reason: 'livraison', reference: 'BL-118', date: '2026-10-01T08:30:00'),
];

final demoTransfers = [
  {
    'id': 2,
    'reference': 'TRF-2026-000002',
    'source_store': demoCentral,
    'destination_store': demoC209,
    'status': 'COMPLETED',
    'items': [
      {
        'id': 3,
        'product': {'id': 11, 'reference': 've-014', 'name': 'veste tweed'},
        'quantity': 4,
      },
      {
        'id': 4,
        'product': {'id': 15, 'reference': 'ac-002', 'name': 'foulard soie'},
        'quantity': 10,
      },
    ],
    'creator': demoAdminRef,
    'created_at': '2026-10-02T14:00:00',
    'completed_at': '2026-10-02T14:00:00',
  },
  {
    'id': 1,
    'reference': 'TRF-2026-000001',
    'source_store': demoCentral,
    'destination_store': demoH109,
    'status': 'CANCELLED',
    'items': [
      {
        'id': 1,
        'product': {'id': 10, 'reference': 'ab-001', 'name': 'abaya brodée'},
        'quantity': 2,
      },
    ],
    'creator': demoAdminRef,
    'created_at': '2026-10-01T09:00:00',
    'completed_at': '2026-10-01T09:00:00',
  },
];

final demoCustomers = [
  {'id': 7, 'first_name': 'rasoa', 'last_name': 'be', 'phone': '0341234567'},
  {'id': 8, 'first_name': 'hery', 'last_name': 'andriamanana', 'phone': '0329876543'},
  {'id': 9, 'first_name': 'mialy', 'last_name': 'rakotobe', 'phone': null},
];

Map<String, Object?> _contact(int index, int purchases, double total, double paid, String lastSale) => {
  ...demoCustomers[index],
  'total_purchases': purchases,
  'total_amount': total,
  'total_paid': paid,
  'remaining_amount': total - paid,
  'has_debt': total > paid,
  'last_sale_date': lastSale,
};

final demoContacts = [
  _contact(0, 3, 330000, 150000, '2026-10-02T15:10:00'),
  _contact(1, 1, 85000, 0, '2026-10-01T17:45:00'),
  _contact(2, 2, 60000, 60000, '2026-09-28T12:00:00'),
];

/// Échéancier d'une dette de 180 000 Ar : une date en retard (en partie payée), deux à venir.
final demoInstallments = [
  {
    'due_date': '2026-09-30',
    'amount': 60000,
    'paid_amount': 20000,
    'remaining_amount': 40000,
    'status': 'PARTIAL',
    'is_overdue': true,
  },
  {
    'due_date': '2029-10-30',
    'amount': 60000,
    'paid_amount': 0,
    'remaining_amount': 60000,
    'status': 'UNPAID',
    'is_overdue': false,
  },
  {
    'due_date': '2029-11-30',
    'amount': 60000,
    'paid_amount': 0,
    'remaining_amount': 60000,
    'status': 'UNPAID',
    'is_overdue': false,
  },
];

Map<String, Object?> _payment(int id, int sale, double amount, String date) => {
  'id': id,
  'sale_id': sale,
  'method': 'CASH',
  'amount': amount,
  'reference': null,
  'creator': demoSellerRef,
  'created_at': date,
};

Map<String, Object?> _saleLine(int id, int product, int quantity, {String? description}) {
  final item = demoProducts.firstWhere((p) => p['id'] == product);
  final price = item['selling_price']! as double;
  return {
    'id': id,
    'product_id': product,
    'product_reference': item['reference'],
    'product_name': item['name'],
    'description': description,
    'quantity': quantity,
    'unit_price': price,
    'total': price * quantity,
  };
}

Map<String, Object?> _sale({
  required int id,
  required Map<String, Object?> customer,
  required Map<String, Object?> store,
  required List<Map<String, Object?>> items,
  required List<Map<String, Object?>> payments,
  required String date,
  List<Map<String, Object?>> installments = const [],
  double discount = 0,
  String status = 'COMPLETED',
}) {
  final subtotal = items.fold<double>(0, (sum, item) => sum + (item['total']! as double));
  final total = subtotal - discount;
  final paid = payments.fold<double>(0, (sum, payment) => sum + (payment['amount']! as double));
  final next = installments.where((i) => (i['remaining_amount']! as num) > 0).firstOrNull;
  return {
    'id': id,
    'sale_number': 'FAC-2026-${id.toString().padLeft(6, '0')}',
    'created_at': date,
    'customer': customer,
    'user': demoSellerRef,
    'store': store,
    'subtotal': subtotal,
    'discount_type': discount > 0 ? 'FIXED' : 'NONE',
    'discount_value': discount,
    'discount_amount': discount,
    'total': total,
    'amount_paid': paid,
    'remaining_amount': total - paid,
    'payment_status': paid >= total ? 'PAID' : (paid > 0 ? 'PARTIAL' : 'UNPAID'),
    'payment_due_date': next?['due_date'],
    'status': status,
    'items': items,
    'payments': payments,
    'installments': installments,
    'updated_at': date,
  };
}

/// Vente avec avance et échéancier (en retard sur la première date), deux articles décrits.
final demoDebtSale = _sale(
  id: 500,
  customer: demoCustomers[0],
  store: demoH109,
  items: [
    _saleLine(1, 10, 1, description: 'taille m, noir'),
    _saleLine(2, 11, 1, description: 'taille s, beige, ourlet à reprendre'),
  ],
  payments: [_payment(1, 500, 100000, '2026-09-15T10:00:00'), _payment(2, 500, 20000, '2026-10-01T11:30:00')],
  installments: demoInstallments,
  discount: 5000,
  date: '2026-09-15T10:00:00',
);

final demoSales = [
  _sale(
    id: 502,
    customer: demoCustomers[2],
    store: demoH109,
    items: [_saleLine(5, 12, 1)],
    payments: [_payment(5, 502, 45000, '2026-10-02T16:20:00')],
    date: '2026-10-02T16:20:00',
  ),
  _sale(
    id: 501,
    customer: demoCustomers[1],
    store: demoC209,
    items: [_saleLine(3, 11, 1)],
    payments: const [],
    installments: [
      {
        'due_date': '2029-12-15',
        'amount': 85000,
        'paid_amount': 0,
        'remaining_amount': 85000,
        'status': 'UNPAID',
        'is_overdue': false,
      },
    ],
    date: '2026-10-01T17:45:00',
  ),
  demoDebtSale,
  _sale(
    id: 499,
    customer: demoCustomers[2],
    store: demoCentral,
    items: [_saleLine(4, 15, 1)],
    payments: [_payment(4, 499, 15000, '2026-09-10T09:00:00')],
    status: 'CANCELLED',
    date: '2026-09-10T09:00:00',
  ),
];

Map<String, Object?> demoInvoice(Map<String, Object?> sale) => {
  'company': {
    'name': 'valheri wear',
    'logo_url': null,
    'address': 'behoririka, pavillon h109',
    'city': 'antananarivo',
    'phone': '034 00 000 00',
    'email': 'valenciaraza@gmail.com',
  },
  'invoice_number': sale['sale_number'],
  'date': sale['created_at'],
  'store': {'name': (sale['store']! as Map)['name'], 'address': 'behoririka', 'phone': '034 11 111 11'},
  'user': sale['user'],
  'customer': sale['customer'],
  'lines': sale['items'],
  'subtotal': sale['subtotal'],
  'discount_type': sale['discount_type'],
  'discount_value': sale['discount_value'],
  'discount_amount': sale['discount_amount'],
  'total': sale['total'],
  'payments': sale['payments'],
  'amount_paid': sale['amount_paid'],
  'remaining_amount': sale['remaining_amount'],
  'payment_status': sale['payment_status'],
  'payment_due_date': sale['payment_due_date'],
  'installments': sale['installments'],
  'status': sale['status'],
  'thank_you_message': ['Merci pour votre achat !', 'À bientôt chez valheri wear.'],
};

Map<String, Object?> _user(int id, String username, String first, String last, bool admin, Map<String, Object?>? store) => {
  'id': id,
  'username': username,
  'first_name': first,
  'last_name': last,
  'email': '$username@valheri.mg',
  'phone': '034 12 345 6$id',
  'role': {'id': admin ? 1 : 2, 'name': admin ? 'ADMIN' : 'VENDEUR'},
  'store_id': store?['id'],
  'store': store,
  'is_active': true,
  'created_at': '2026-09-01T08:00:00',
};

final demoUsers = [
  _user(1, 'valencia', 'valheri', 'wear', true, null),
  _user(3, 'antsa', 'antsa', 'rakoto', true, null),
  _user(4, 'fleur', 'fleur', 'rasoanaivo', false, demoH109),
  {..._user(5, 'sitraka', 'sitraka', 'andry', false, demoC209), 'is_active': false},
];

/// Toutes les routes de l'API utilisées par l'application, avec les données de démonstration.
void stubDemoApi(FakeApi api) {
  int? queryInt(Map<String, dynamic> query, String key) => int.tryParse('${query[key] ?? ''}');

  api.on('GET', '/stores', (_) => page(demoStores));
  for (final store in demoStores) {
    api.on('GET', '/stores/${store['id']}', (_) => store);
    api.on(
      'GET',
      '/stores/${store['id']}/employees',
      (_) => page(demoUsers.where((u) => (u['store'] as Map?)?['id'] == store['id']).toList()),
    );
  }
  api.on('GET', '/categories', (_) => page(demoCategories));
  api.on('GET', '/products', (_) => page(demoProducts));
  for (final product in demoProducts) {
    api.on('GET', '/products/${product['id']}', (_) => product);
  }
  api.on('GET', '/stock', (request) {
    final store = queryInt(request.queryParameters, 'store_id');
    final product = queryInt(request.queryParameters, 'product_id');
    return page([
      for (final line in demoStockLines)
        if ((store == null || (line['store']! as Map)['id'] == store) &&
            (product == null || (line['product']! as Map)['id'] == product))
          line,
    ]);
  });
  final low = demoStockLines.where((line) => line['low_stock'] == true).toList();
  api.on('GET', '/stock/low-stock', (_) => page(low));
  api.on('GET', '/dashboard/low-stock', (_) => page(low));
  api.on('GET', '/stock/movements', (request) {
    final product = queryInt(request.queryParameters, 'product_id');
    return page([
      for (final movement in demoMovements)
        if (product == null || (movement['product']! as Map)['id'] == product) movement,
    ]);
  });
  api.on('GET', '/dashboard/stock-value', (_) {
    double sum(Iterable<Map<String, Object?>> lines, String key) =>
        lines.fold(0, (total, line) => total + (line[key]! as num).toDouble());
    Map<String, Object?> totals(Iterable<Map<String, Object?>> lines) => {
      'quantity': lines.fold<int>(0, (total, line) => total + (line['quantity']! as int)),
      'purchase_value': sum(lines, 'purchase_value'),
      'sale_value': sum(lines, 'sale_value'),
      'potential_profit': sum(lines, 'potential_profit'),
    };
    return {
      'stores': [
        for (final store in demoStores)
          {'store': store, ...totals(demoStockLines.where((line) => (line['store']! as Map)['id'] == store['id']))},
      ],
      'total': totals(demoStockLines),
    };
  });
  api.on('GET', '/stock-transfers', (_) => page(demoTransfers));
  for (final transfer in demoTransfers) {
    api.on('GET', '/stock-transfers/${transfer['id']}', (_) => transfer);
  }
  api.on('GET', '/customers/contacts', (request) {
    final debtOnly = '${request.queryParameters['has_debt']}' == 'true';
    return page([
      for (final contact in demoContacts)
        if (!debtOnly || contact['has_debt'] == true) contact,
    ]);
  });
  api.on('GET', '/customers', (_) => page(demoCustomers));
  for (final customer in demoCustomers) {
    final id = customer['id'];
    final sales = [...demoSales.where((s) => (s['customer']! as Map)['id'] == id)];
    final debts = sales.where((s) => s['status'] == 'COMPLETED' && (s['remaining_amount']! as num) > 0).toList();
    api.on('GET', '/customers/$id', (_) => customer);
    api.on('GET', '/customers/$id/sales', (_) => page(sales));
    api.on(
      'GET',
      '/customers/$id/debts',
      (_) => {
        'customer': customer,
        'total_debt': debts.fold<double>(0, (sum, s) => sum + (s['remaining_amount']! as num)),
        'sales': debts,
      },
    );
  }
  api.on('GET', '/sales/history', (request) {
    final debtOnly = '${request.queryParameters['has_debt']}' == 'true';
    return page([
      for (final sale in demoSales)
        if (!debtOnly || (sale['status'] == 'COMPLETED' && (sale['remaining_amount']! as num) > 0)) sale,
    ]);
  });
  for (final sale in demoSales) {
    api.on('GET', '/sales/${sale['id']}', (_) => sale);
    api.on('GET', '/sales/${sale['id']}/invoice', (_) => demoInvoice(sale));
    api.on('GET', '/sales/${sale['id']}/payments', (_) => sale['payments']);
  }
  api.on(
    'GET',
    '/payments',
    (_) => page([
      for (final sale in demoSales)
        if (sale['status'] == 'COMPLETED') ...(sale['payments']! as List),
    ]),
  );
  api.on(
    'GET',
    '/dashboard/summary',
    (_) => {
      ...dashboardJson(),
      'sales_count': 3,
      'revenue': 330000,
      'estimated_profit': 95000,
      'amount_collected': 165000,
      'debt_amount': 245000,
      'products_count': demoProducts.length,
      'stores_count': demoStores.length,
      'stock_quantity': 96,
      'low_stock_count': low.length,
      'out_of_stock_count': 0,
      'unavailable_products_count': 0,
      'top_products': [
        {'product_id': 10, 'reference': 'ab-001', 'name': 'abaya brodée', 'quantity_sold': 4, 'revenue': 800000},
        {'product_id': 11, 'reference': 've-014', 'name': 'veste tweed', 'quantity_sold': 3, 'revenue': 255000},
        {'product_id': 12, 'reference': 'ro-003', 'name': 'robe vintage', 'quantity_sold': 2, 'revenue': 90000},
      ],
      'recent_sales': demoSales.take(3).toList(),
    },
  );
  api.on(
    'GET',
    '/dashboard/sales',
    (_) => [
      for (var day = 26; day <= 30; day++)
        {'period': '2026-09-${day}T00:00:00', 'sales_count': day % 3 + 1, 'revenue': 40000.0 * (day % 4 + 1)},
      {'period': '2026-10-01T00:00:00', 'sales_count': 2, 'revenue': 130000},
      {'period': '2026-10-02T00:00:00', 'sales_count': 3, 'revenue': 330000},
    ],
  );
  api.on('GET', '/users', (_) => page(demoUsers));
  for (final user in demoUsers) {
    api.on('GET', '/users/${user['id']}', (_) => user);
  }
  final permissions = [
    for (final (index, code) in adminPermissions.indexed) {'id': index + 1, 'name': code, 'description': null},
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
        'permissions': permissions.where((p) => vendeurPermissions.contains(p['name'])).toList(),
      },
    ],
  );
  api.on('GET', '/permissions', (_) => permissions);
  api.on(
    'GET',
    '/company',
    (_) => {
      'id': 1,
      'name': 'valheri wear',
      'logo_url': null,
      'phone': '034 00 000 00',
      'email': 'valenciaraza@gmail.com',
      'address': 'behoririka, pavillon h109',
      'city': 'antananarivo',
      'updated_at': '2026-10-01T08:00:00',
    },
  );
  api.on(
    'GET',
    '/audit',
    (_) => page([
      {
        'id': 3,
        'user_id': 1,
        'action': 'product.update',
        'entity_type': 'product',
        'entity_id': 10,
        'old_data': {'selling_price': '190000'},
        'new_data': {'selling_price': '200000'},
        'ip_address': '192.168.1.20',
        'created_at': '2026-10-02T08:00:00',
      },
      {
        'id': 2,
        'user_id': 4,
        'action': 'sale.create',
        'entity_type': 'sale',
        'entity_id': 502,
        'old_data': null,
        'new_data': {'sale_number': 'FAC-2026-000502', 'total': 45000},
        'ip_address': '192.168.1.31',
        'created_at': '2026-10-02T16:20:00',
      },
      {
        'id': 1,
        'user_id': 1,
        'action': 'stock_transfer.create',
        'entity_type': 'stock_transfer',
        'entity_id': 2,
        'old_data': null,
        'new_data': {'reference': 'TRF-2026-000002'},
        'ip_address': '192.168.1.20',
        'created_at': '2026-10-02T14:00:00',
      },
    ]),
  );
  final conversation = {
    'id': 1,
    'type': 'PRIVATE',
    'name': null,
    'created_by': 1,
    'created_at': '2026-10-01T08:00:00',
    'updated_at': '2026-10-02T08:05:00',
    'members': [
      {'user': demoAdminRef, 'joined_at': '2026-10-01T08:00:00', 'last_read_at': null},
      {'user': demoSellerRef, 'joined_at': '2026-10-01T08:00:00', 'last_read_at': null},
    ],
    'unread_count': 2,
  };
  final group = {
    ...conversation,
    'id': 2,
    'type': 'GROUP',
    'name': 'équipe behoririka',
    'unread_count': 0,
    'updated_at': '2026-10-01T18:00:00',
  };
  api.on('GET', '/chat/conversations', (_) => [conversation, group]);
  api.on('GET', '/chat/conversations/1', (_) => conversation);
  api.on(
    'GET',
    '/chat/conversations/1/messages',
    (_) => page([
      {
        'id': 3,
        'conversation_id': 1,
        'sender_id': 1,
        'content': 'Oui, 4 vestes partent au C209 cet après-midi.',
        'is_deleted': false,
        'created_at': '2026-10-02T08:05:00',
        'updated_at': '2026-10-02T08:05:00',
      },
      {
        'id': 2,
        'conversation_id': 1,
        'sender_id': 4,
        'content': 'Bonjour, il reste des vestes tweed au Stock Local ?',
        'is_deleted': false,
        'created_at': '2026-10-02T08:01:00',
        'updated_at': '2026-10-02T08:01:00',
      },
      {
        'id': 1,
        'conversation_id': 1,
        'sender_id': 1,
        'content': null,
        'is_deleted': true,
        'created_at': '2026-10-02T08:00:00',
        'updated_at': '2026-10-02T08:00:00',
      },
    ]),
  );
  api.on('POST', '/chat/conversations/1/read', (_) => null, status: 204);
}
