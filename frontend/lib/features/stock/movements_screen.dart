import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/session_controller.dart';
import '../../core/export/excel_export.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/list_period_filter.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/store_selector.dart';
import '../products/product_detail_screen.dart';
import 'stock_models.dart';
import 'stock_operation_sheet.dart';
import 'stock_repository.dart';

/// Mouvements de stock : entrées, sorties, ventes, pertes, ajustements et transferts.
/// Le stock de chaque magasin se consulte dans Produits (vue « Par magasin »).
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late final PagedController<StockMovement> _controller = PagedController(
    (query) => context.read<StockRepository>().movements(query),
    filters: {'store_id': _user.canChooseStore ? null : _user.store?.id, 'sort': '-created_at'},
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

  Future<void> _newOperation() async {
    final storeId = _controller.filter('store_id') as int? ?? _user.store?.id;
    final saved = await showStockOperationSheet(context, storeId: storeId);
    if (saved && mounted) await _controller.refresh();
  }

  void _openFilters() {
    showFilterSheet(
      context,
      onReset: () => _controller.clearFilters(keep: {'reference', 'date_from', 'date_to', 'sort'}),
      builder: (context, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterDropdown<String>(
            label: 'Type de mouvement',
            value: _controller.filter('type') as String?,
            options: {for (final type in MovementType.values) type.code: type.label},
            onChanged: (value) {
              _controller.setFilter('type', value);
              refresh();
            },
          ),
          if (_user.canChooseStore)
            StoreSelector(
              value: _controller.filter('store_id') as int?,
              allLabel: 'Tous les magasins',
              onChanged: (store) {
                _controller.setFilter('store_id', store?.id);
                refresh();
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canOperate = allowedStockOperations(_user).isNotEmpty;
    return ListPage(
      title: 'Mouvements de stock',
      controller: _controller,
      countLabel: (total) => '$total mouvement${total > 1 ? 's' : ''}',
      search: AppSearchField(
        hint: 'Référence (bon de livraison, facture, transfert...)',
        onChanged: (value) => _controller.setFilter('reference', value),
      ),
      onOpenFilters: _openFilters,
      quickFilters: ListPeriodFilter(controller: _controller),
      actions: [
        ExportButton<StockMovement>(
          controller: _controller,
          fileBaseName: 'mouvements_stock',
          sheetName: 'Mouvements',
          columns: [
            ExportColumn('Date', (movement) => movement.createdAt),
            ExportColumn('Type', (movement) => movement.typeLabel),
            ExportColumn('Référence produit', (movement) => movement.product.reference.toUpperCase()),
            ExportColumn('Produit', (movement) => Formats.capitalize(movement.product.name)),
            ExportColumn('Magasin', (movement) => movement.store.label),
            ExportColumn('Magasin d\'origine', (movement) => movement.sourceStore?.label),
            ExportColumn('Magasin de destination', (movement) => movement.destinationStore?.label),
            ExportColumn('Quantité', (movement) => movement.quantity),
            ExportColumn('Motif', (movement) => Formats.text(movement.reason)),
            ExportColumn('Référence', (movement) => movement.reference),
            ExportColumn('Utilisateur', (movement) => movement.user.fullName),
          ],
        ),
      ],
      primaryAction: canOperate
          ? PrimaryAction(label: 'Opération de stock', icon: Icons.add, onPressed: _newOperation)
          : null,
      body: PagedListView<StockMovement>(
        controller: _controller,
        emptyTitle: 'Aucun mouvement',
        emptyMessage: 'Modifiez la période ou les filtres.',
        columns: [
          TableColumnDef.text('Date', (movement) => Formats.dateTime(movement.createdAt)),
          TableColumnDef.text('Type', (movement) => movement.typeLabel),
          TableColumnDef.text('Produit', (movement) => Formats.capitalize(movement.product.name)),
          TableColumnDef.text('Magasin', (movement) => movement.store.label),
          TableColumnDef(
            'Quantité',
            (movement) => Text(
              '${movement.quantity >= 0 ? '+' : ''}${movement.quantity}',
              style: TextStyle(color: movement.quantity >= 0 ? AppColors.success : AppColors.danger),
            ),
            numeric: true,
          ),
          // Transferts seulement : d'où part le stock et où il arrive.
          TableColumnDef.text('Magasin d\'origine', (movement) => movement.sourceStore?.label ?? '—'),
          TableColumnDef.text('Magasin de destination', (movement) => movement.destinationStore?.label ?? '—'),
          TableColumnDef.text('Utilisateur', (movement) => movement.user.fullName),
        ],
        cardBuilder: (context, movement) => AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.md),
          child: MovementTile(movement: movement, showProduct: true, showReason: false),
        ),
      ),
    );
  }
}
