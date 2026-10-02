import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/export/excel_export.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/adaptive_page.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/list_period_filter.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/store_selector.dart';
import '../categories/categories_repository.dart';
import '../products/product_detail_screen.dart';
import 'stock_models.dart';
import 'stock_operation_sheet.dart';
import 'stock_repository.dart';
import '../../core/widgets/app_dialog.dart';

/// Stock par magasin et historique des mouvements.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key, this.initialState});

  /// Filtre de départ : `low` (stock faible) ou `out` (épuisés).
  final String? initialState;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> with SingleTickerProviderStateMixin {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final PagedController<StockLine> _lines = PagedController(
    (query) => context.read<StockRepository>().lines(query),
    filters: _initialLineFilters(),
  );
  late final PagedController<StockMovement> _movements = PagedController(
    (query) => context.read<StockRepository>().movements(query),
    filters: {'store_id': _user.canChooseStore ? null : _user.store?.id},
  );
  bool _movementsLoaded = false;

  Map<String, Object?> _initialLineFilters() {
    final state = widget.initialState;
    return {
      'store_id': _user.canChooseStore ? null : _user.store?.id,
      'low_stock': state == 'low' ? true : null,
      'out_of_stock': state == 'out' ? true : null,
    };
  }

  @override
  void initState() {
    super.initState();
    _lines.load();
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_movementsLoaded) {
        _movementsLoaded = true;
        _movements.load();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _lines.dispose();
    _movements.dispose();
    super.dispose();
  }

  int? get _storeId => _lines.filter('store_id') as int?;

  Future<void> _newOperation() async {
    final changed = await showStockOperationSheet(context, storeId: _storeId ?? _user.store?.id);
    if (changed && mounted) {
      await _lines.refresh();
      if (_movementsLoaded) await _movements.refresh();
    }
  }

  Future<void> _lineActions(StockLine line) async {
    final operations = allowedStockOperations(_user);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(line.product.label, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text('${line.store.label} · ${Formats.quantity(line.quantity)} en stock'),
            ),
            const Divider(height: 1),
            for (final operation in operations)
              ListTile(
                leading: Icon(_operationIcon(operation)),
                title: Text(operation.label),
                onTap: () => Navigator.of(context).pop(operation.name),
              ),
            if (_user.can(Perm.stockAdjust))
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Modifier le seuil d\'alerte'),
                onTap: () => Navigator.of(context).pop('threshold'),
              ),
            if (_user.canCreateTransfer && line.quantity > 0)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Transférer vers un autre magasin'),
                onTap: () => Navigator.of(context).pop('transfer'),
              ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Voir la fiche produit'),
              onTap: () => Navigator.of(context).pop('product'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    var changed = false;
    switch (action) {
      case 'threshold':
        changed = await showThresholdDialog(context, line);
      case 'transfer':
        await context.push('/transfers/new?product=${line.product.id}&source=${line.store.id}');
        changed = true;
      case 'product':
        await context.push('/products/${line.product.id}');
        changed = true;
      default:
        changed = await showStockOperationSheet(context, line: line, operation: StockOperation.values.byName(action));
    }
    if (changed && mounted) await _lines.refresh();
  }

  IconData _operationIcon(StockOperation operation) => switch (operation) {
    StockOperation.entry => Icons.move_to_inbox_outlined,
    StockOperation.exit => Icons.outbox_outlined,
    StockOperation.loss => Icons.heart_broken_outlined,
    StockOperation.adjust => Icons.tune,
  };

  void _showValue() {
    showDialog<void>(
      context: context,
      builder: (_) => _StockValueDialog(storeId: _storeId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canOperate = allowedStockOperations(_user).isNotEmpty;
    return AdaptivePage(
      title: 'Stock',
      actions: [
        if (_user.can(Perm.reportView))
          IconButton(
            tooltip: 'Valeur du stock',
            onPressed: _showValue,
            icon: const Icon(Icons.account_balance_outlined),
          ),
      ],
      primaryAction: canOperate
          ? PrimaryAction(label: 'Opération de stock', icon: Icons.add, onPressed: _newOperation)
          : null,
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Stock par magasin'),
          Tab(text: 'Mouvements'),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _StockLinesTab(controller: _lines, user: _user, onTap: _lineActions),
          _MovementsTab(controller: _movements, user: _user),
        ],
      ),
    );
  }
}

// --- Onglet stock --------------------------------------------------------------------------------

class _StockLinesTab extends StatelessWidget {
  const _StockLinesTab({required this.controller, required this.user, required this.onTap});

  final PagedController<StockLine> controller;
  final CurrentUser user;
  final ValueChanged<StockLine> onTap;

  void _openFilters(BuildContext context) {
    showFilterSheet(
      context,
      onReset: () => controller.clearFilters(keep: {'search', 'store_id'}),
      builder: (context, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FutureBuilder<List<Category>>(
            future: context.read<CategoriesRepository>().active(),
            builder: (context, snapshot) => FilterDropdown<int>(
              label: 'Catégorie',
              value: controller.filter('category_id') as int?,
              allLabel: 'Toutes les catégories',
              options: {for (final category in snapshot.data ?? const <Category>[]) category.id: category.label},
              onChanged: (value) {
                controller.setFilter('category_id', value);
                refresh();
              },
            ),
          ),
          ChoiceChips<String>(
            label: 'Trier par',
            value: (controller.filter('sort') as String?) ?? 'name',
            options: const {
              'name': 'Nom',
              'reference': 'Référence',
              'quantity': 'Quantité ↑',
              '-quantity': 'Quantité ↓',
              '-updated_at': 'Dernière mise à jour',
            },
            onChanged: (value) {
              controller.setFilter('sort', value);
              refresh();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _TabList(
      controller: controller,
      search: AppSearchField(
        hint: 'Nom ou référence du produit',
        initialValue: controller.filter('search') as String?,
        onChanged: (value) => controller.setFilter('search', value),
      ),
      onOpenFilters: () => _openFilters(context),
      quickFilters: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final state = controller.filter('out_of_stock') == true
              ? 'out'
              : controller.filter('low_stock') == true
              ? 'low'
              : 'all';
          return Wrap(
            spacing: Gaps.sm,
            runSpacing: Gaps.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (user.canChooseStore)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: StoreSelector(
                    value: controller.filter('store_id') as int?,
                    allLabel: 'Tous les magasins',
                    dense: true,
                    onChanged: (store) => controller.setFilter('store_id', store?.id),
                  ),
                ),
              for (final (key, label) in const [('all', 'Tous'), ('low', 'Stock faible'), ('out', 'Épuisés')])
                ChoiceChip(
                  label: Text(label),
                  selected: state == key,
                  onSelected: (_) => controller.updateFilters({
                    'low_stock': key == 'low' ? true : null,
                    'out_of_stock': key == 'out' ? true : null,
                  }),
                ),
            ],
          );
        },
      ),
      exportButton: ExportButton<StockLine>(
        controller: controller,
        fileBaseName: 'stock',
        sheetName: 'Stock',
        columns: [
          ExportColumn('Référence', (line) => line.product.reference.toUpperCase()),
          ExportColumn('Produit', (line) => line.product.label),
          ExportColumn('Catégorie', (line) => Formats.capitalize(line.product.category?.name ?? '')),
          ExportColumn('Magasin', (line) => line.store.label),
          ExportColumn('Quantité', (line) => line.quantity),
          ExportColumn('Seuil d\'alerte', (line) => line.alertThreshold),
          ExportColumn('État', (line) => Badges.stock(outOfStock: line.outOfStock, lowStock: line.lowStock).label),
          if (user.can(Perm.reportView)) ...[
            ExportColumn('Valeur d\'achat (Ar)', (line) => line.purchaseValue),
            ExportColumn('Valeur de vente (Ar)', (line) => line.saleValue),
          ],
          ExportColumn('Mis à jour', (line) => line.updatedAt),
        ],
      ),
      list: PagedListView<StockLine>(
        controller: controller,
        onTap: onTap,
        emptyTitle: 'Aucune ligne de stock',
        emptyMessage: 'Modifiez la recherche ou les filtres.',
        columns: [
          TableColumnDef.text('Produit', (line) => line.product.label),
          TableColumnDef.text('Référence', (line) => line.product.reference.toUpperCase()),
          TableColumnDef.text('Magasin', (line) => line.store.label),
          TableColumnDef.text('Quantité', (line) => Formats.quantity(line.quantity), numeric: true),
          TableColumnDef.text('Seuil', (line) => '${line.alertThreshold}', numeric: true),
          TableColumnDef('État', (line) => Badges.stock(outOfStock: line.outOfStock, lowStock: line.lowStock)),
          if (user.can(Perm.reportView))
            TableColumnDef.text('Valeur de vente', (line) => Formats.money(line.saleValue), numeric: true),
          TableColumnDef.text('Mis à jour', (line) => Formats.dateTime(line.updatedAt)),
        ],
        cardBuilder: (context, line) => AppCard(
          onTap: () => onTap(line),
          padding: const EdgeInsets.all(Gaps.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.product.label, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${line.product.reference.toUpperCase()} · ${line.store.label}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: Gaps.sm),
                    Badges.stock(outOfStock: line.outOfStock, lowStock: line.lowStock),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formats.quantity(line.quantity),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: line.outOfStock ? AppColors.danger : (line.lowStock ? AppColors.warning : null),
                    ),
                  ),
                  Text('seuil ${line.alertThreshold}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Onglet mouvements -----------------------------------------------------------------------------

class _MovementsTab extends StatelessWidget {
  const _MovementsTab({required this.controller, required this.user});

  final PagedController<StockMovement> controller;
  final CurrentUser user;

  void _openFilters(BuildContext context) {
    showFilterSheet(
      context,
      onReset: () => controller.clearFilters(keep: {'reference', 'date_from', 'date_to'}),
      builder: (context, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterDropdown<String>(
            label: 'Type de mouvement',
            value: controller.filter('type') as String?,
            options: {for (final type in MovementType.values) type.code: type.label},
            onChanged: (value) {
              controller.setFilter('type', value);
              refresh();
            },
          ),
          if (user.canChooseStore)
            StoreSelector(
              value: controller.filter('store_id') as int?,
              allLabel: 'Tous les magasins',
              onChanged: (store) {
                controller.setFilter('store_id', store?.id);
                refresh();
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _TabList(
      controller: controller,
      search: AppSearchField(
        hint: 'Référence du mouvement',
        initialValue: controller.filter('reference') as String?,
        onChanged: (value) => controller.setFilter('reference', value),
      ),
      onOpenFilters: () => _openFilters(context),
      quickFilters: ListPeriodFilter(controller: controller),
      exportButton: ExportButton<StockMovement>(
        controller: controller,
        fileBaseName: 'mouvements_stock',
        sheetName: 'Mouvements',
        columns: [
          ExportColumn('Date', (movement) => movement.createdAt),
          ExportColumn('Type', (movement) => movement.type.label),
          ExportColumn('Référence produit', (movement) => movement.product.reference.toUpperCase()),
          ExportColumn('Produit', (movement) => Formats.capitalize(movement.product.name)),
          ExportColumn('Magasin', (movement) => movement.store.label),
          ExportColumn('Quantité', (movement) => movement.quantity),
          ExportColumn('Motif', (movement) => Formats.capitalize(movement.reason)),
          ExportColumn('Référence', (movement) => movement.reference),
          ExportColumn('Utilisateur', (movement) => movement.user.fullName),
        ],
      ),
      list: PagedListView<StockMovement>(
        controller: controller,
        emptyTitle: 'Aucun mouvement',
        emptyMessage: 'Modifiez la période ou les filtres.',
        columns: [
          TableColumnDef.text('Date', (movement) => Formats.dateTime(movement.createdAt)),
          TableColumnDef.text('Type', (movement) => movement.type.label),
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
          TableColumnDef.text('Motif', (movement) => Formats.capitalize(movement.reason ?? '—')),
          TableColumnDef.text('Utilisateur', (movement) => movement.user.fullName),
        ],
        cardBuilder: (context, movement) => AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.md),
          child: MovementTile(movement: movement, showProduct: true),
        ),
      ),
    );
  }
}

/// Barre d'outils (recherche, filtres, export) + liste, pour un onglet.
class _TabList extends StatelessWidget {
  const _TabList({
    required this.controller,
    required this.search,
    required this.onOpenFilters,
    required this.quickFilters,
    required this.exportButton,
    required this.list,
  });

  final PagedController<dynamic> controller;
  final Widget search;
  final VoidCallback onOpenFilters;
  final Widget quickFilters;
  final Widget exportButton;
  final Widget list;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.md, Gaps.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: search),
                    ),
                  ),
                  const SizedBox(width: Gaps.sm),
                  ListenableBuilder(
                    listenable: controller,
                    builder: (_, _) =>
                        FilterButton(activeCount: controller.activeFilterCount, onPressed: onOpenFilters),
                  ),
                  exportButton,
                ],
              ),
              const SizedBox(height: Gaps.sm),
              quickFilters,
              const SizedBox(height: Gaps.sm),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Text(
                  controller.hasLoaded ? '${controller.total} résultat${controller.total > 1 ? 's' : ''}' : ' ',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gaps.sm),
        Expanded(child: list),
      ],
    );
  }
}

// --- Valeur du stock -------------------------------------------------------------------------------

class _StockValueDialog extends StatelessWidget {
  const _StockValueDialog({required this.storeId});

  final int? storeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      title: 'Valeur du stock',
      size: DialogSize.medium,
      content: FutureBuilder<StockValueReport>(
        future: context.read<StockRepository>().value(storeId: storeId),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('Impossible de calculer la valeur du stock.');
          if (!snapshot.hasData) {
            return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
          }
          final report = snapshot.data!;
          Widget block(String title, StockValue value, {bool total = false}) => Padding(
            padding: const EdgeInsets.only(bottom: Gaps.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: total ? theme.textTheme.titleMedium : theme.textTheme.titleSmall),
                InfoRow(label: 'Quantité', value: Formats.quantity(value.quantity)),
                InfoRow(label: 'Valeur d\'achat', value: Formats.money(value.purchaseValue)),
                InfoRow(label: 'Valeur de vente', value: Formats.money(value.saleValue)),
                InfoRow(label: 'Bénéfice potentiel', value: Formats.money(value.potentialProfit), emphasis: total),
              ],
            ),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final value in report.stores) block(value.store?.label ?? 'Magasin', value),
              if (report.stores.length != 1) ...[const Divider(), block('Total', report.total, total: true)],
            ],
          );
        },
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer'))],
    );
  }
}
