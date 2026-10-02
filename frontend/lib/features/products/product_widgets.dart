import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/export/excel_export.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/product_avatar.dart';
import '../../shared/widgets/status_badge.dart';
import 'product_models.dart';

/// Marge en pourcentage du prix d'achat (null si le prix d'achat est nul).
double? marginPercent(Product product) =>
    product.purchasePrice <= 0 ? null : product.unitProfit / product.purchasePrice * 100;

String marginLabel(Product product) {
  final percent = marginPercent(product);
  if (percent == null) return Formats.money(product.unitProfit);
  return '${Formats.money(product.unitProfit)} (${percent.toStringAsFixed(1).replaceAll('.', ',')} %)';
}

/// État d'un élément de la liste des produits.
StatusBadge productStateBadge(ProductListItem item) {
  if (!item.product.isActive) {
    return const StatusBadge('Inactif', tone: BadgeTone.neutral, icon: Icons.visibility_off_outlined);
  }
  if (!item.hasStock) return const StatusBadge('Actif', tone: BadgeTone.success);
  return Badges.stock(outOfStock: item.outOfStock, lowStock: item.lowStock);
}

/// Carte produit : image, nom, référence, catégorie, prix, marge, quantité et état.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.item, required this.showCost, this.onTap, this.trailing});

  final ProductListItem item;

  /// Afficher le prix d'achat et la marge (réservé aux gestionnaires).
  final bool showCost;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = item.product;
    final muted = theme.textTheme.bodySmall;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Gaps.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductAvatar(name: product.label, imageUrl: product.imageUrl),
          const SizedBox(width: Gaps.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.label, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  [
                    product.reference.toUpperCase(),
                    if (product.category != null) Formats.capitalize(product.category!.name),
                  ].join(' · '),
                  style: muted,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Gaps.sm),
                Wrap(
                  spacing: Gaps.md,
                  runSpacing: Gaps.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      Formats.money(product.sellingPrice),
                      style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                    if (showCost) Text('Achat ${Formats.money(product.purchasePrice)}', style: muted),
                    if (showCost)
                      Text(
                        'Marge ${marginLabel(product)}',
                        style: muted?.copyWith(color: product.unitProfit > 0 ? AppColors.success : null),
                      ),
                  ],
                ),
                const SizedBox(height: Gaps.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: productStateBadge(item)),
                    if (item.hasStock) ...[
                      const SizedBox(width: Gaps.sm),
                      Flexible(
                        child: Text(
                          '${Formats.quantity(item.quantity)} en stock',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: item.outOfStock ? AppColors.danger : null,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.store != null) ...[const SizedBox(height: 2), Text(item.store!.label, style: muted)],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

List<TableColumnDef<ProductListItem>> productTableColumns({required bool showCost, required bool withStock}) => [
  TableColumnDef(
    'Produit',
    (item) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProductAvatar(name: item.product.label, imageUrl: item.product.imageUrl, size: 36),
        const SizedBox(width: Gaps.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(item.product.label, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  ),
  TableColumnDef.text('Référence', (item) => item.product.reference.toUpperCase()),
  TableColumnDef.text('Catégorie', (item) => Formats.capitalize(item.product.category?.name ?? '—')),
  if (showCost)
    TableColumnDef.text('Prix d\'achat', (item) => Formats.money(item.product.purchasePrice), numeric: true),
  TableColumnDef.text('Prix de vente', (item) => Formats.money(item.product.sellingPrice), numeric: true),
  if (showCost) TableColumnDef.text('Marge', (item) => marginLabel(item.product), numeric: true),
  if (withStock) TableColumnDef.text('Magasin', (item) => item.store?.label ?? '—'),
  if (withStock) TableColumnDef.text('Quantité', (item) => Formats.quantity(item.quantity), numeric: true),
  const TableColumnDef('État', productStateBadge),
];

List<ExportColumn<ProductListItem>> productExportColumns({required bool showCost, required bool withStock}) => [
  ExportColumn('Référence', (item) => item.product.reference.toUpperCase()),
  ExportColumn('Nom', (item) => item.product.label),
  ExportColumn('Catégorie', (item) => Formats.capitalize(item.product.category?.name ?? '')),
  if (showCost) ExportColumn('Prix d\'achat (Ar)', (item) => item.product.purchasePrice),
  ExportColumn('Prix de vente (Ar)', (item) => item.product.sellingPrice),
  if (showCost) ExportColumn('Marge unitaire (Ar)', (item) => item.product.unitProfit),
  if (withStock) ExportColumn('Magasin', (item) => item.store?.label),
  if (withStock) ExportColumn('Quantité', (item) => item.quantity),
  ExportColumn('État', (item) => productStateBadge(item).label),
];
