import 'package:valmag/core/auth/permissions.dart';

/// Données de test au format de l'API (textes en minuscules, comme renvoyés par le backend).

const vendeurPermissions = [
  Perm.productView,
  Perm.stockView,
  Perm.storeStockView,
  Perm.saleView,
  Perm.saleCreate,
  Perm.paymentView,
  Perm.paymentCreate,
  Perm.companyView,
  Perm.chatView,
  Perm.chatSend,
];

const adminPermissions = [
  Perm.dashboardView,
  Perm.reportView,
  Perm.userView,
  Perm.userCreate,
  Perm.userUpdate,
  Perm.userDelete,
  Perm.roleView,
  Perm.permissionView,
  Perm.permissionAssign,
  Perm.storeView,
  Perm.storeCreate,
  Perm.storeUpdate,
  Perm.storeDelete,
  Perm.storeStockView,
  Perm.transferCreate,
  Perm.transferView,
  Perm.transferCancel,
  Perm.stockTransfer,
  Perm.productView,
  Perm.productCreate,
  Perm.productUpdate,
  Perm.productDelete,
  Perm.stockView,
  Perm.stockEntry,
  Perm.stockExit,
  Perm.stockAdjust,
  Perm.saleView,
  Perm.saleCreate,
  Perm.saleCancel,
  Perm.saleDiscount,
  Perm.paymentView,
  Perm.paymentCreate,
  Perm.auditView,
  Perm.companyView,
  Perm.companyUpdate,
  Perm.chatView,
  Perm.chatSend,
];

Map<String, Object?> storeJson({int id = 1, String name = 'stock local', bool central = true}) => {
  'id': id,
  'name': name,
  'address': null,
  'phone': null,
  'is_central': central,
  'is_active': true,
};

Map<String, Object?> meJson({required bool admin, int id = 1, Map<String, Object?>? store}) => {
  'id': id,
  'username': admin ? 'valenciaraza' : 'vendeur1',
  'first_name': admin ? 'valencia' : 'jean',
  'last_name': admin ? 'raza' : 'rakoto',
  'email': admin ? 'valenciaraza@local.mg' : 'vendeur1@local.mg',
  'phone': null,
  'role': {'id': admin ? 1 : 2, 'name': admin ? 'ADMIN' : 'VENDEUR'},
  'store_id': store?['id'],
  'store': store,
  'is_active': true,
  'permissions': admin ? adminPermissions : vendeurPermissions,
};

Map<String, Object?> page(List<Object?> items, {int? total, int page = 1, int pageSize = 20}) {
  final count = total ?? items.length;
  return {
    'items': items,
    'total': count,
    'page': page,
    'page_size': pageSize,
    'pages': count == 0 ? 0 : (count / pageSize).ceil(),
  };
}

Map<String, Object?> productJson({int id = 10, String name = 'stylo bleu', double price = 1000, double cost = 600}) => {
  'id': id,
  'reference': 'P-$id',
  'name': name,
  'category': {'id': 1, 'name': 'papeterie'},
  'purchase_price': cost,
  'selling_price': price,
  'is_active': true,
};

Map<String, Object?> stockLineJson({
  int id = 100,
  Map<String, Object?>? product,
  Map<String, Object?>? store,
  int quantity = 10,
}) => {
  'id': id,
  'product': product ?? productJson(),
  'store': store ?? storeJson(),
  'quantity': quantity,
  'alert_threshold': 5,
  'low_stock': quantity <= 5,
  'out_of_stock': quantity == 0,
  'updated_at': '2026-10-01T08:00:00Z',
  'purchase_value': 0,
  'sale_value': 0,
  'potential_profit': 0,
};

Map<String, Object?> saleJson({
  int id = 500,
  double total = 2000,
  double paid = 2000,
  Map<String, Object?>? store,
  String status = 'COMPLETED',
}) => {
  'id': id,
  'sale_number': 'FAC-2026-000500',
  'created_at': '2026-10-02T09:30:00Z',
  'customer': {'id': 7, 'first_name': 'rasoa', 'last_name': 'be', 'phone': '0341234567'},
  'user': {
    'id': 2,
    'username': 'vendeur1',
    'first_name': 'jean',
    'last_name': 'rakoto',
    'role': {'id': 2, 'name': 'VENDEUR'},
  },
  'store': store ?? storeJson(),
  'subtotal': total,
  'discount_type': 'NONE',
  'discount_value': 0,
  'discount_amount': 0,
  'total': total,
  'amount_paid': paid,
  'remaining_amount': total - paid,
  'payment_status': paid >= total ? 'PAID' : (paid > 0 ? 'PARTIAL' : 'UNPAID'),
  'payment_due_date': paid >= total ? null : '2026-10-30',
  'status': status,
  'items': [
    {
      'id': 1,
      'product_id': 10,
      'product_reference': 'p-10',
      'product_name': 'stylo bleu',
      'quantity': 2,
      'unit_price': 1000,
      'total': 2000,
    },
  ],
  'payments': [],
};

Map<String, Object?> dashboardJson() => {
  'sales_count': 3,
  'revenue': 15000,
  'estimated_profit': 5000,
  'sales_margin': 4000,
  'amount_collected': 12000,
  'debt_amount': 3000,
  'products_count': 12,
  'stores_count': 3,
  'stock_quantity': 150,
  'low_stock_count': 2,
  'out_of_stock_count': 1,
  'unavailable_products_count': 0,
  'top_products': [
    {'product_id': 10, 'reference': 'p-10', 'name': 'stylo bleu', 'quantity_sold': 5, 'revenue': 5000},
  ],
  'least_sold_products': [
    {'product_id': 11, 'reference': 'c-1', 'name': 'cahier', 'quantity_sold': 0, 'revenue': 0, 'stock_quantity': 40},
  ],
  'stores_performance': [
    {
      'store': storeJson(),
      'sales_count': 2,
      'revenue': 10000,
      'sales_margin': 3000,
      'debt_amount': 0,
      'stock_quantity': 100,
    },
    {
      'store': storeJson(id: 2, name: 'h109', central: false),
      'sales_count': 1,
      'revenue': 5000,
      'sales_margin': 1000,
      'debt_amount': 3000,
      'stock_quantity': 50,
    },
  ],
  'recent_sales': [saleJson()],
};

const tokensJson = {
  'access_token': 'access-1',
  'refresh_token': 'refresh-1',
  'token_type': 'bearer',
  'expires_in': 900,
};
