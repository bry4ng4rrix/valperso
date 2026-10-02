import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/session_controller.dart';
import '../features/audit/audit_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/conversation_screen.dart';
import '../features/company/company_screen.dart';
import '../features/customers/customer_detail_screen.dart';
import '../features/customers/customer_form_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/home_screen.dart';
import '../features/invoices/invoice_screen.dart';
import '../features/payments/payments_screen.dart';
import '../features/products/product_detail_screen.dart';
import '../features/products/product_form_screen.dart';
import '../features/products/products_screen.dart';
import '../features/roles/roles_screen.dart';
import '../features/sales/sale_detail_screen.dart';
import '../features/sales/sales_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/stock/movements_screen.dart';
import '../features/stores/store_detail_screen.dart';
import '../features/stores/store_form_screen.dart';
import '../features/stores/stores_screen.dart';
import '../features/transfers/new_transfer_screen.dart';
import '../features/transfers/transfer_detail_screen.dart';
import '../features/transfers/transfers_screen.dart';
import '../features/users/user_detail_screen.dart';
import '../features/users/user_form_screen.dart';
import '../features/users/users_screen.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/states.dart';
import 'navigation.dart';
import 'shell/app_shell.dart';
import 'shell/more_screen.dart';

const _splash = '/splash';

int _id(GoRouterState state) => int.tryParse(state.pathParameters['id'] ?? '') ?? 0;

/// Routeur de l'application.
///
/// - sans session : écran de connexion ;
/// - écran non autorisé (permission manquante) : retour à l'accueil ;
/// - tous les écrans connectés sont affichés dans [AppShell] (menu latéral ou barre du bas).
GoRouter buildRouter(SessionController session) {
  return GoRouter(
    initialLocation: Routes.home,
    observers: [PopupTracker()],
    refreshListenable: session,
    redirect: (context, state) {
      final location = state.uri.path;
      if (session.status == SessionStatus.unknown) return location == _splash ? null : _splash;
      final user = session.user;
      if (user == null) return location == Routes.login ? null : Routes.login;
      if (location == Routes.login || location == _splash) return Routes.home;
      return canOpenLocation(location, user) ? null : Routes.home;
    },
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page introuvable')),
      body: EmptyState(
        title: 'Cette page n\'existe pas.',
        icon: Icons.link_off,
        action: FilledButton(onPressed: () => context.go(Routes.home), child: const Text('Retour à l\'accueil')),
      ),
    ),
    routes: [
      GoRoute(path: _splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      ShellRoute(
        observers: [PopupTracker()],
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          GoRoute(path: Routes.more, builder: (_, _) => const MoreScreen()),
          GoRoute(
            path: Routes.sales,
            builder: (_, state) => SalesScreen(
              initialTab: SalesTab.fromCode(state.uri.queryParameters['tab']),
              customerId: int.tryParse(state.uri.queryParameters['customer_id'] ?? ''),
            ),
            routes: [
              // Ancienne adresse de la nouvelle vente : onglet « Nouvelle vente » de l'écran Ventes.
              GoRoute(path: 'new', redirect: (_, _) => Routes.newSale),
              GoRoute(
                path: ':id',
                builder: (_, state) => SaleDetailScreen(saleId: _id(state)),
                routes: [
                  GoRoute(
                    path: 'invoice',
                    builder: (_, state) => InvoiceScreen(saleId: _id(state)),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: Routes.products,
            builder: (_, state) => ProductsScreen(
              initialStockState: state.uri.queryParameters['state'],
              initialStoreId: int.tryParse(state.uri.queryParameters['store'] ?? ''),
            ),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const ProductFormScreen()),
              GoRoute(
                path: ':id',
                builder: (_, state) => ProductDetailScreen(productId: _id(state)),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => ProductFormScreen(productId: _id(state)),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(path: Routes.movements, builder: (_, _) => const MovementsScreen()),
          GoRoute(
            path: Routes.transfers,
            builder: (_, _) => const TransfersScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, state) => NewTransferScreen(
                  productId: int.tryParse(state.uri.queryParameters['product'] ?? ''),
                  sourceStoreId: int.tryParse(state.uri.queryParameters['source'] ?? ''),
                ),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) => TransferDetailScreen(transferId: _id(state)),
              ),
            ],
          ),
          GoRoute(
            path: Routes.customers,
            builder: (_, state) => CustomersScreen(debtOnly: state.uri.queryParameters['debt'] == '1'),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const CustomerFormScreen()),
              GoRoute(
                path: ':id',
                builder: (_, state) => CustomerDetailScreen(customerId: _id(state)),
              ),
            ],
          ),
          GoRoute(path: Routes.payments, builder: (_, _) => const PaymentsScreen()),
          GoRoute(
            path: Routes.stores,
            builder: (_, _) => const StoresScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const StoreFormScreen()),
              GoRoute(
                path: ':id',
                builder: (_, state) => StoreDetailScreen(storeId: _id(state)),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => StoreFormScreen(storeId: _id(state)),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: Routes.users,
            builder: (_, _) => const UsersScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const UserFormScreen()),
              GoRoute(
                path: ':id',
                builder: (_, state) => UserDetailScreen(userId: _id(state)),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => UserFormScreen(userId: _id(state)),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(path: Routes.categories, builder: (_, _) => const CategoriesScreen()),
          GoRoute(path: Routes.audit, builder: (_, _) => const AuditScreen()),
          GoRoute(
            path: Routes.chat,
            builder: (_, _) => const ChatScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => ConversationScreen(conversationId: _id(state)),
              ),
            ],
          ),
          GoRoute(
            path: Routes.settings,
            builder: (_, _) => const SettingsScreen(),
            routes: [
              GoRoute(path: 'company', builder: (_, _) => const CompanyScreen()),
              GoRoute(path: 'roles', builder: (_, _) => const RolesScreen()),
            ],
          ),
        ],
      ),
    ],
  );
}
