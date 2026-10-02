import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/auth/auth_repository.dart';
import '../core/auth/session_controller.dart';
import '../core/auth/settings_controller.dart';
import '../core/storage/key_value_store.dart';
import '../features/audit/audit_repository.dart';
import '../features/cash/cash_repository.dart';
import '../features/categories/categories_repository.dart';
import '../features/chat/chat_repository.dart';
import '../features/company/company_repository.dart';
import '../features/customers/customers_repository.dart';
import '../features/dashboard/dashboard_repository.dart';
import '../features/payments/payments_repository.dart';
import '../features/products/products_repository.dart';
import '../features/roles/roles_repository.dart';
import '../features/sales/cart_controller.dart';
import '../features/sales/sales_repository.dart';
import '../features/stock/stock_repository.dart';
import '../features/stores/stores_repository.dart';
import '../features/transfers/transfers_repository.dart';
import '../features/users/users_repository.dart';

/// Objets partagés par toute l'application, créés une seule fois au démarrage.
class AppDependencies {
  AppDependencies._(this.storage, this.api)
    : session = SessionController(auth: AuthRepository(api), api: api),
      settings = SettingsController(store: storage, api: api);

  /// [adapter] permet aux tests de remplacer le réseau par de fausses réponses.
  factory AppDependencies({required KeyValueStore storage, String? baseUrl, HttpClientAdapter? adapter}) {
    final api = ApiClient(baseUrl: baseUrl ?? ApiConfig.defaultBaseUrl, tokens: TokenStore(storage), adapter: adapter);
    return AppDependencies._(storage, api);
  }

  final KeyValueStore storage;
  final ApiClient api;
  final SessionController session;
  final SettingsController settings;
  final CartController cart = CartController();

  /// Préférences locales puis reprise de la session (sans bloquer l'affichage).
  Future<void> start() async {
    await settings.load();
    session.addListener(_clearCartOnLogout);
    await session.restore();
  }

  void _clearCartOnLogout() {
    if (!session.isAuthenticated && !cart.isEmpty) cart.reset();
  }

  List<SingleChildWidget> get providers => [
    Provider<ApiClient>.value(value: api),
    ChangeNotifierProvider<SessionController>.value(value: session),
    ChangeNotifierProvider<SettingsController>.value(value: settings),
    ChangeNotifierProvider<CartController>.value(value: cart),
    Provider(create: (_) => StoresRepository(api)),
    Provider(create: (_) => UsersRepository(api)),
    Provider(create: (_) => RolesRepository(api)),
    Provider(create: (_) => CategoriesRepository(api)),
    Provider(create: (_) => ProductsRepository(api)),
    Provider(create: (_) => StockRepository(api)),
    Provider(create: (_) => TransfersRepository(api)),
    Provider(create: (_) => CustomersRepository(api)),
    Provider(create: (_) => SalesRepository(api)),
    Provider(create: (_) => PaymentsRepository(api)),
    Provider(create: (_) => CashRepository(api)),
    Provider(create: (_) => CompanyRepository(api)),
    Provider(create: (_) => DashboardRepository(api)),
    Provider(create: (_) => AuditRepository(api)),
    Provider(create: (_) => ChatRepository(api)),
  ];
}
