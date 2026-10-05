import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/realtime/live_refresh.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/states.dart';
import '../invoices/invoice_actions.dart';
import '../payments/payment_dialog.dart';
import 'sale_models.dart';
import 'sale_widgets.dart';
import 'sales_repository.dart';

/// Détail d'une vente : articles, montants, paiements, actions (facture, encaissement, annulation).
class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({super.key, required this.saleId});

  final int saleId;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  late Future<Sale> _future = context.read<SalesRepository>().get(widget.saleId);

  void _reload() => setState(() {
    _future = context.read<SalesRepository>().get(widget.saleId);
  });

  Future<void> _collect(Sale sale) async {
    final payment = await showPaymentDialog(
      context,
      saleId: sale.id,
      saleNumber: sale.number,
      remaining: sale.remainingAmount,
      customerName: sale.customer.fullName,
    );
    if (payment != null && mounted) _reload();
  }

  Future<void> _cancel(Sale sale) async {
    final reason = await showReasonConfirmation(
      context,
      title: 'Annuler la vente ${sale.number} ?',
      message:
          'Les produits retournent dans le stock de ${sale.store.label}. '
          'Les paiements restent visibles dans l\'historique. Cette action est définitive.',
      fieldLabel: 'Motif de l\'annulation',
      confirmLabel: 'Annuler la vente',
    );
    if (reason == null || !mounted) return;
    final confirmed = await showConfirmation(
      context,
      title: 'Confirmer l\'annulation ?',
      message: 'Vente ${sale.number} — ${Formats.money(sale.total)}\nMotif : $reason',
      changes: const [FieldChange('Statut', 'Validée', 'Annulée')],
      confirmLabel: 'Oui, annuler',
      cancelLabel: 'Non',
      type: ConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;
    final done = await runApiAction(
      context,
      () => context.read<SalesRepository>().cancel(sale.id, reason),
      success: 'Vente annulée.',
    );
    if (done) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return LiveRefresh(
      // Paiement, annulation ou échéance de cette vente.
      entities: const {'sale'},
      when: (change) => change.id == widget.saleId,
      onChange: _reload,
      child: FutureBuilder<Sale>(
        future: _future,
        builder: (context, snapshot) {
          final sale = snapshot.data;
          return DetailPage(
            title: sale?.number ?? 'Vente',
            actions: [
              if (sale != null)
                IconButton(
                  tooltip: 'Facture',
                  onPressed: () => context.push('/sales/${sale.id}/invoice'),
                  icon: const Icon(Icons.receipt_long_outlined),
                ),
            ],
            child: snapshot.hasError
                ? ErrorState(message: errorMessageOf(snapshot.error), onRetry: _reload)
                : sale == null
                ? const LoadingState(lines: 4)
                : RefreshIndicator(
                    onRefresh: () async {
                      _reload();
                      await _future;
                    },
                    child: _content(sale),
                  ),
          );
        },
      ),
    );
  }

  Widget _content(Sale sale) {
    final user = context.read<SessionController>().requireUser;
    final theme = Theme.of(context);
    final canCollect = sale.hasDebt && user.can(Perm.paymentCreate);
    final canCancel = !sale.isCancelled && user.can(Perm.saleCancel);
    return ListView(
      padding: const EdgeInsets.all(Gaps.lg),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Numéro puis badges : sur téléphone, les badges passent à la ligne sans couper le numéro.
              Wrap(
                spacing: Gaps.md,
                runSpacing: Gaps.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(sale.number, style: theme.textTheme.titleLarge),
                  SaleBadges(sale: sale),
                ],
              ),
              const SizedBox(height: Gaps.sm),
              Text(Formats.dateTime(sale.createdAt), style: theme.textTheme.bodyMedium),
              const SizedBox(height: Gaps.md),
              ResponsiveGrid(
                minItemWidth: 200,
                children: [
                  InfoRow(label: 'Client', value: sale.customer.fullName),
                  InfoRow(label: 'Téléphone', value: sale.customer.phone ?? '—'),
                  InfoRow(label: 'Magasin', value: sale.store.label),
                  InfoRow(label: 'Vendeur', value: sale.user.fullName),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Gaps.lg),
        TwoColumns(
          leftFlex: 3,
          rightFlex: 2,
          left: SectionCard(
            title: 'Articles (${sale.itemCount})',
            icon: Icons.shopping_bag_outlined,
            child: Column(
              children: [
                for (final item in sale.items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(Formats.capitalize(item.name)),
                    subtitle: Text(
                      [
                        '${item.reference.toUpperCase()} · ${item.quantity} × ${Formats.money(item.unitPrice)}',
                        if (item.description != null) Formats.capitalize(item.description),
                      ].join('\n'),
                    ),
                    trailing: Text(Formats.money(item.total), style: theme.textTheme.titleSmall),
                    onTap: () => context.push('/products/${item.productId}'),
                  ),
              ],
            ),
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'Montants',
                icon: Icons.calculate_outlined,
                child: Column(
                  children: [
                    InfoRow(label: 'Sous-total', value: Formats.money(sale.subtotal ?? sale.total)),
                    if (sale.discountAmount > 0)
                      InfoRow(
                        label: sale.discountType == DiscountType.percentage
                            ? 'Remise (${Formats.amount(sale.discountValue)} %)'
                            : 'Remise',
                        value: '- ${Formats.money(sale.discountAmount)}',
                      ),
                    InfoRow(label: 'Total', value: Formats.money(sale.total), emphasis: true),
                    InfoRow(label: 'Payé', value: Formats.money(sale.amountPaid)),
                    if (sale.remainingAmount > 0) ...[
                      InfoRow(
                        label: 'Reste à payer',
                        value: Formats.money(sale.remainingAmount),
                        valueStyle: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                      ),
                      InfoRow(
                        label: sale.installments.isEmpty ? 'Échéance' : 'Prochaine échéance',
                        value: '${Formats.date(sale.paymentDueDate)}${sale.isOverdue ? ' (dépassée)' : ''}',
                        valueStyle: sale.isOverdue ? const TextStyle(color: AppColors.danger) : null,
                      ),
                    ],
                  ],
                ),
              ),
              if (sale.installments.isNotEmpty) ...[
                const SizedBox(height: Gaps.lg),
                SectionCard(
                  title: 'Échéancier',
                  icon: Icons.event_note_outlined,
                  child: InstallmentList(installments: sale.installments),
                ),
              ],
              const SizedBox(height: Gaps.lg),
              SectionCard(
                title: 'Paiements',
                icon: Icons.payments_outlined,
                child: sale.payments.isEmpty
                    ? const Text('Aucun paiement.')
                    : Column(
                        children: [
                          for (final payment in sale.payments)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(Formats.money(payment.amount)),
                              subtitle: Text(
                                [
                                  Formats.dateTime(payment.createdAt),
                                  if (payment.creator != null) payment.creator!.fullName,
                                  if (payment.reference != null) 'réf. ${payment.reference}',
                                ].join(' · '),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gaps.xl),
        Wrap(
          spacing: Gaps.md,
          runSpacing: Gaps.md,
          children: [
            if (canCollect)
              FilledButton.icon(
                onPressed: () => _collect(sale),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Encaisser un paiement'),
              ),
            OutlinedButton.icon(
              onPressed: () => context.push('/sales/${sale.id}/invoice'),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Voir la facture'),
            ),
            AppButton(
              label: 'Partager la facture',
              icon: Icons.share_outlined,
              variant: AppButtonVariant.secondary,
              onPressed: () => shareInvoice(context, sale.id),
            ),
            if (canCancel)
              AppButton(
                label: 'Annuler la vente',
                icon: Icons.cancel_outlined,
                variant: AppButtonVariant.danger,
                onPressed: () => _cancel(sale),
              ),
          ],
        ),
      ],
    );
  }
}
