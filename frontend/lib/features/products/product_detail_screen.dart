import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/product_avatar.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/status_badge.dart';
import '../stock/stock_models.dart';
import '../stock/stock_operation_sheet.dart';
import '../stock/stock_repository.dart';
import 'product_models.dart';
import 'product_widgets.dart';
import 'products_repository.dart';

class _ProductDetail {
  const _ProductDetail(this.product, this.lines, this.movements);

  final Product product;
  final List<StockLine> lines;
  final List<StockMovement> movements;

  int get globalQuantity => lines.fold(0, (sum, line) => sum + line.quantity);
}

/// Fiche produit : prix, stock par magasin, stock global, derniers mouvements et actions.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final int productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<_ProductDetail> _future = _load();

  Future<_ProductDetail> _load() async {
    final user = context.read<SessionController>().requireUser;
    final stock = context.read<StockRepository>();
    final product = await context.read<ProductsRepository>().get(widget.productId);
    final canSeeStock = user.can(Perm.stockView);
    final results = await Future.wait([
      canSeeStock ? stock.productLines(widget.productId) : Future.value(const <StockLine>[]),
      canSeeStock
          ? stock
                .movements(PageQuery(pageSize: 10, filters: {'product_id': widget.productId}))
                .then((page) => page.items)
          : Future.value(const <StockMovement>[]),
    ]);
    return _ProductDetail(product, results[0] as List<StockLine>, results[1] as List<StockMovement>);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _deactivate(Product product) async {
    final confirmed = await showConfirmation(
      context,
      title: 'Désactiver ce produit ?',
      message:
          '${product.label} (${product.reference.toUpperCase()}) ne pourra plus être vendu ni transféré. '
          'Son historique est conservé.',
      confirmLabel: 'Désactiver',
      type: ConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;
    final done = await runApiAction(
      context,
      () => context.read<ProductsRepository>().deactivate(product.id),
      success: 'Produit désactivé.',
    );
    if (done) _reload();
  }

  Future<void> _reactivate(Product product) async {
    final confirmed = await showConfirmation(
      context,
      title: 'Réactiver ce produit ?',
      message: '${product.label} pourra de nouveau être vendu.',
      changes: const [FieldChange('Statut', 'Inactif', 'Actif')],
      confirmLabel: 'Réactiver',
    );
    if (!confirmed || !mounted) return;
    final done = await runApiAction(
      context,
      () => context.read<ProductsRepository>().update(product.id, {'is_active': true}),
      success: 'Produit réactivé.',
    );
    if (done) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().requireUser;
    return FutureBuilder<_ProductDetail>(
      future: _future,
      builder: (context, snapshot) {
        final detail = snapshot.data;
        return DetailPage(
          title: detail?.product.label ?? 'Produit',
          actions: [
            if (detail != null && user.can(Perm.productUpdate))
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  await context.push('/products/${widget.productId}/edit');
                  if (mounted) _reload();
                },
              ),
            if (detail != null && (user.can(Perm.productDelete) || user.can(Perm.productUpdate)))
              PopupMenuButton<String>(
                onSelected: (value) => value == 'off' ? _deactivate(detail.product) : _reactivate(detail.product),
                itemBuilder: (_) => [
                  if (detail.product.isActive && user.can(Perm.productDelete))
                    const PopupMenuItem(
                      value: 'off',
                      child: ListTile(
                        leading: Icon(Icons.block, color: AppColors.danger),
                        title: Text('Désactiver le produit'),
                      ),
                    ),
                  if (!detail.product.isActive && user.can(Perm.productUpdate))
                    const PopupMenuItem(
                      value: 'on',
                      child: ListTile(leading: Icon(Icons.check_circle_outline), title: Text('Réactiver le produit')),
                    ),
                ],
              ),
          ],
          child: snapshot.hasError
              ? ErrorState(message: errorMessageOf(snapshot.error), onRetry: _reload)
              : detail == null
              ? const LoadingState(lines: 4)
              : RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _future;
                  },
                  child: _content(detail),
                ),
        );
      },
    );
  }

  Widget _content(_ProductDetail detail) {
    final user = context.read<SessionController>().requireUser;
    final theme = Theme.of(context);
    final product = detail.product;
    final showCost = user.canAny(const [Perm.productCreate, Perm.productUpdate]);
    final operations = allowedStockOperations(user);

    return ListView(
      padding: const EdgeInsets.all(Gaps.lg),
      children: [
        AppCard(
          child: Row(
            children: [
              ProductAvatar(name: product.label, imageUrl: product.imageUrl, size: 72),
              const SizedBox(width: Gaps.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.label, style: theme.textTheme.titleLarge),
                    const SizedBox(height: Gaps.xs),
                    Text(
                      [
                        product.reference.toUpperCase(),
                        if (product.category != null) Formats.capitalize(product.category!.name),
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Gaps.sm),
                    Wrap(spacing: Gaps.sm, children: [Badges.active(product.isActive)]),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gaps.lg),
        ResponsiveGrid(
          minItemWidth: 160,
          children: [
            _Figure(
              label: 'Prix de vente',
              value: Formats.money(product.sellingPrice),
              color: theme.colorScheme.primary,
            ),
            if (showCost) _Figure(label: 'Prix d\'achat', value: Formats.money(product.purchasePrice)),
            if (showCost)
              _Figure(
                label: 'Marge unitaire',
                value: marginLabel(product),
                color: product.unitProfit > 0 ? AppColors.success : null,
              ),
            if (user.can(Perm.stockView))
              _Figure(label: 'Stock global', value: Formats.quantity(detail.globalQuantity)),
          ],
        ),
        if (user.can(Perm.stockView)) ...[
          const SizedBox(height: Gaps.lg),
          SectionCard(
            title: 'Stock par magasin',
            icon: Icons.storefront_outlined,
            trailing: user.canCreateTransfer && product.isActive
                ? TextButton.icon(
                    onPressed: () => context.push('/transfers/new?product=${product.id}'),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Transférer'),
                  )
                : null,
            child: detail.lines.isEmpty
                ? const Text('Ce produit n\'est présent dans aucun magasin.')
                : Column(
                    children: [
                      for (final line in detail.lines)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(line.store.label),
                          subtitle: Text('Seuil d\'alerte : ${line.alertThreshold}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(Formats.quantity(line.quantity), style: theme.textTheme.titleMedium),
                              const SizedBox(width: Gaps.sm),
                              Badges.stock(outOfStock: line.outOfStock, lowStock: line.lowStock),
                              if (operations.isNotEmpty || user.can(Perm.stockAdjust))
                                PopupMenuButton<String>(
                                  tooltip: 'Actions',
                                  onSelected: (action) async {
                                    final changed = action == 'threshold'
                                        ? await showThresholdDialog(context, line)
                                        : await showStockOperationSheet(context, line: line);
                                    if (changed && mounted) _reload();
                                  },
                                  itemBuilder: (_) => [
                                    if (operations.isNotEmpty)
                                      const PopupMenuItem(value: 'operation', child: Text('Opération de stock')),
                                    if (user.can(Perm.stockAdjust))
                                      const PopupMenuItem(
                                        value: 'threshold',
                                        child: Text('Modifier le seuil d\'alerte'),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: Gaps.lg),
          SectionCard(
            title: 'Derniers mouvements',
            icon: Icons.history,
            child: detail.movements.isEmpty
                ? const Text('Aucun mouvement.')
                : Column(children: [for (final movement in detail.movements) MovementTile(movement: movement)]),
          ),
        ],
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(Gaps.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: Gaps.xs),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Ligne d'un mouvement de stock (quantité signée : + entrée, - sortie).
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement, this.showProduct = false});

  final StockMovement movement;
  final bool showProduct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = movement.quantity >= 0;
    final details = [
      movement.store.label,
      movement.user.fullName,
      if (movement.reference != null) movement.reference!,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        positive ? Icons.south_west : Icons.north_east,
        color: positive ? AppColors.success : AppColors.danger,
      ),
      title: Text(
        showProduct ? '${movement.type.label} — ${Formats.capitalize(movement.product.name)}' : movement.type.label,
      ),
      subtitle: Text(
        [
          Formats.dateTime(movement.createdAt),
          details,
          if (movement.reason != null) Formats.text(movement.reason),
        ].join('\n'),
      ),
      isThreeLine: true,
      trailing: Text(
        '${positive ? '+' : ''}${Formats.quantity(movement.quantity)}',
        style: theme.textTheme.titleMedium?.copyWith(color: positive ? AppColors.success : AppColors.danger),
      ),
    );
  }
}
