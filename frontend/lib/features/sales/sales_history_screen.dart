import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/navigation.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/periods.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/list_period_filter.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/store_selector.dart';
import '../users/user_models.dart';
import '../users/users_repository.dart';
import 'sale_models.dart';
import 'sale_widgets.dart';
import 'sales_repository.dart';

/// Historique des ventes : période, recherche (n° de facture, client), filtres, export.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key, this.customerId, this.embedded = false});

  /// Ventes d'un seul client (depuis la fiche client).
  final int? customerId;

  /// Affiché dans l'onglet « Historique » de l'écran Ventes.
  final bool embedded;

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late final PagedController<Sale> _controller = PagedController(
    (query) => context.read<SalesRepository>().history(query),
    filters: {if (widget.customerId != null) 'customer_id': widget.customerId else ...periodFilters(Period.today)},
  );

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(Sale sale) async {
    await context.push('/sales/${sale.id}');
    if (mounted) await _controller.refresh();
  }

  void _openFilters() {
    showFilterSheet(
      context,
      onReset: () => _controller.clearFilters(keep: {'search', 'date_from', 'date_to', 'customer_id'}),
      builder: (context, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterDropdown<String>(
            label: 'Paiement',
            value: _controller.filter('payment_status') as String?,
            options: {for (final status in PaymentStatus.values) status.code: status.label},
            onChanged: (value) {
              _controller.setFilter('payment_status', value);
              refresh();
            },
          ),
          FilterDropdown<bool>(
            label: 'Dette',
            value: _controller.filter('has_debt') as bool?,
            options: const {true: 'Avec reste à payer', false: 'Soldées'},
            onChanged: (value) {
              _controller.setFilter('has_debt', value);
              refresh();
            },
          ),
          FilterDropdown<String>(
            label: 'Statut',
            value: _controller.filter('status') as String?,
            options: const {'COMPLETED': 'Validées', 'CANCELLED': 'Annulées'},
            onChanged: (value) {
              _controller.setFilter('status', value);
              refresh();
            },
          ),
          if (_user.canChooseStore) ...[
            StoreSelector(
              value: _controller.filter('store_id') as int?,
              allLabel: 'Tous les magasins',
              onChanged: (store) {
                _controller.setFilter('store_id', store?.id);
                refresh();
              },
            ),
            const SizedBox(height: Gaps.md),
          ],
          if (_user.can(Perm.userView))
            FutureBuilder<Paged<AppUser>>(
              future: context.read<UsersRepository>().list(const PageQuery(pageSize: PageQuery.maxPageSize)),
              builder: (context, snapshot) => FilterDropdown<int>(
                label: 'Vendeur',
                value: _controller.filter('user_id') as int?,
                options: {for (final user in snapshot.data?.items ?? const <AppUser>[]) user.id: user.fullName},
                onChanged: (value) {
                  _controller.setFilter('user_id', value);
                  refresh();
                },
              ),
            ),
          ChoiceChips<String>(
            label: 'Trier par',
            value: (_controller.filter('sort') as String?) ?? '-created_at',
            options: const {
              '-created_at': 'Plus récentes',
              'created_at': 'Plus anciennes',
              '-total': 'Montant ↓',
              'total': 'Montant ↑',
              'sale_number': 'N° de facture',
            },
            onChanged: (value) {
              _controller.setFilter('sort', value);
              refresh();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListPage(
      embedded: widget.embedded,
      title: widget.customerId == null ? 'Historique des ventes' : 'Ventes du client',
      controller: _controller,
      countLabel: (total) => '$total vente${total > 1 ? 's' : ''}',
      search: AppSearchField(
        hint: 'N° de facture, client ou téléphone',
        onChanged: (value) => _controller.setFilter('search', value),
      ),
      onOpenFilters: _openFilters,
      quickFilters: ListPeriodFilter(controller: _controller),
      actions: [
        ExportButton<Sale>(
          controller: _controller,
          columns: saleExportColumns,
          fileBaseName: 'ventes',
          sheetName: 'Ventes',
        ),
      ],
      // Dans l'écran Ventes, la nouvelle vente est un onglet voisin : pas de bouton en double.
      primaryAction: _user.can(Perm.saleCreate) && !widget.embedded
          ? PrimaryAction(
              label: 'Nouvelle vente',
              icon: Icons.add_shopping_cart,
              onPressed: () => context.go(Routes.newSale),
            )
          : null,
      body: PagedListView<Sale>(
        controller: _controller,
        onTap: _open,
        emptyTitle: 'Aucune vente',
        emptyMessage: 'Aucune vente sur cette période. Essayez « Tout » ou une autre période.',
        columns: saleTableColumns(showStore: _user.canChooseStore),
        cardBuilder: (context, sale) => SaleCard(sale: sale, showStore: _user.canChooseStore, onTap: () => _open(sale)),
      ),
    );
  }
}
