import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/export/excel_export.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/status_badge.dart';
import 'sale_models.dart';

/// Badges d'une vente : statut de paiement, annulation, échéance dépassée.
class SaleBadges extends StatelessWidget {
  const SaleBadges({super.key, required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Gaps.xs,
      runSpacing: Gaps.xs,
      children: [
        if (sale.isCancelled) Badges.saleStatus(sale.status) else Badges.paymentStatus(sale.paymentStatus.code),
        if (sale.isOverdue) const StatusBadge('Échéance dépassée', tone: BadgeTone.danger, icon: Icons.event_busy),
      ],
    );
  }
}

/// Échéancier d'une vente : une ligne par date de remboursement, avec son montant et son état.
class InstallmentList extends StatelessWidget {
  const InstallmentList({super.key, required this.installments});

  final List<SaleInstallment> installments;

  static BadgeTone _tone(SaleInstallment installment) {
    if (installment.isOverdue) return BadgeTone.danger;
    return switch (installment.status) {
      PaymentStatus.paid => BadgeTone.success,
      PaymentStatus.partial => BadgeTone.warning,
      PaymentStatus.unpaid => BadgeTone.neutral,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, installment) in installments.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gaps.xs),
            child: Row(
              children: [
                Expanded(child: Text('${index + 1}. ${Formats.date(installment.dueDate)}')),
                Text(Formats.money(installment.amount), style: theme.textTheme.titleSmall),
                const SizedBox(width: Gaps.sm),
                StatusBadge(installment.statusLabel, tone: _tone(installment)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Carte d'une vente (historique, client, accueil).
class SaleCard extends StatelessWidget {
  const SaleCard({super.key, required this.sale, this.onTap, this.showStore = true});

  final Sale sale;
  final VoidCallback? onTap;
  final bool showStore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Gaps.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(sale.number, style: theme.textTheme.titleSmall)),
              Text(
                Formats.money(sale.total),
                style: theme.textTheme.titleMedium?.copyWith(
                  decoration: sale.isCancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gaps.xs),
          Row(
            children: [
              Expanded(
                child: Text(sale.customer.fullName, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
              ),
              Text(Formats.dateTime(sale.createdAt), style: muted),
            ],
          ),
          if (showStore) ...[
            const SizedBox(height: 2),
            Text('${sale.store.label} · ${sale.user.fullName}', style: muted, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: Gaps.sm),
          SaleBadges(sale: sale),
          if (sale.hasDebt) ...[
            const SizedBox(height: Gaps.xs),
            Wrap(
              spacing: Gaps.md,
              runSpacing: 2,
              children: [
                Text(
                  'Reste ${Formats.money(sale.remainingAmount)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger, fontWeight: FontWeight.w600),
                ),
                if (sale.paymentDueDate != null)
                  Text('Prochaine échéance ${Formats.date(sale.paymentDueDate)}', style: muted),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Colonnes du tableau des ventes (grand écran).
List<TableColumnDef<Sale>> saleTableColumns({bool showStore = true}) => [
  TableColumnDef.text('N° facture', (sale) => sale.number),
  TableColumnDef.text('Date', (sale) => Formats.dateTime(sale.createdAt)),
  TableColumnDef.text('Client', (sale) => sale.customer.fullName),
  if (showStore) TableColumnDef.text('Magasin', (sale) => sale.store.label),
  TableColumnDef.text('Vendeur', (sale) => sale.user.fullName),
  TableColumnDef('Total', (sale) => Text(Formats.money(sale.total)), numeric: true),
  TableColumnDef('Payé', (sale) => Text(Formats.money(sale.amountPaid)), numeric: true),
  TableColumnDef(
    'Reste',
    (sale) => Text(
      Formats.money(sale.remainingAmount),
      style: sale.hasDebt ? const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600) : null,
    ),
    numeric: true,
  ),
  TableColumnDef('État', (sale) => SaleBadges(sale: sale)),
];

/// Colonnes de l'export Excel des ventes.
final List<ExportColumn<Sale>> saleExportColumns = [
  ExportColumn('N° facture', (sale) => sale.number),
  ExportColumn('Date', (sale) => sale.createdAt),
  ExportColumn('Client', (sale) => sale.customer.fullName),
  ExportColumn('Téléphone', (sale) => sale.customer.phone),
  ExportColumn('Magasin', (sale) => sale.store.label),
  ExportColumn('Vendeur', (sale) => sale.user.fullName),
  ExportColumn('Total (Ar)', (sale) => sale.total),
  ExportColumn('Payé (Ar)', (sale) => sale.amountPaid),
  ExportColumn('Reste (Ar)', (sale) => sale.remainingAmount),
  ExportColumn('Paiement', (sale) => sale.paymentStatus.label),
  ExportColumn('Échéance', (sale) => sale.paymentDueDate),
  ExportColumn('Statut', (sale) => sale.isCancelled ? 'Annulée' : 'Validée'),
];
