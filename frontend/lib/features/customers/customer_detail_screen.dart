import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/realtime/live_refresh.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/models/refs.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/status_badge.dart';
import '../payments/payment_dialog.dart';
import '../sales/sale_models.dart';
import '../sales/sale_widgets.dart';
import 'customer_models.dart';
import 'customers_repository.dart';
import '../../shared/widgets/responsive_grid.dart';

class _CustomerDetail {
  const _CustomerDetail(this.customer, this.debts, this.sales);

  final CustomerRef customer;
  final CustomerDebts debts;
  final Paged<Sale> sales;
}

/// Fiche client : coordonnées, dettes (avec encaissement) et achats.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final int customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Future<_CustomerDetail> _future = _load();

  Future<_CustomerDetail> _load() async {
    final repository = context.read<CustomersRepository>();
    final results = await Future.wait([
      repository.get(widget.customerId),
      repository.debts(widget.customerId),
      repository.sales(widget.customerId, const PageQuery(pageSize: 20, filters: {'sort': '-created_at'})),
    ]);
    return _CustomerDetail(results[0] as CustomerRef, results[1] as CustomerDebts, results[2] as Paged<Sale>);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _collect(DebtSale sale, CustomerRef customer) async {
    final payment = await showPaymentDialog(
      context,
      saleId: sale.id,
      saleNumber: sale.number,
      remaining: sale.remainingAmount,
      customerName: customer.fullName,
    );
    if (payment != null && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return LiveRefresh(
      // Le client lui-même, ou ses ventes et paiements (dette).
      entities: const {'customer', 'sale', 'payment'},
      when: (change) => change.entity != 'customer' || change.id == widget.customerId,
      onChange: _reload,
      child: FutureBuilder<_CustomerDetail>(
        future: _future,
        builder: (context, snapshot) {
          final detail = snapshot.data;
          return DetailPage(
            title: detail?.customer.fullName ?? 'Client',
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
      ),
    );
  }

  Widget _content(_CustomerDetail detail) {
    final user = context.read<SessionController>().requireUser;
    final theme = Theme.of(context);
    final customer = detail.customer;
    final debts = detail.debts;
    return ListView(
      padding: const EdgeInsets.all(Gaps.lg),
      children: [
        AppCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  customer.fullName.isEmpty ? '?' : customer.fullName[0].toUpperCase(),
                  style: TextStyle(fontSize: 20, color: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: Gaps.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.fullName, style: theme.textTheme.titleLarge),
                    const SizedBox(height: Gaps.xs),
                    Text(customer.phone ?? 'Pas de téléphone enregistré', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              if (customer.phone != null)
                IconButton(
                  tooltip: 'Copier le numéro',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: customer.phone!));
                    if (mounted) Notify.info(context, 'Numéro copié.');
                  },
                  icon: const Icon(Icons.copy),
                ),
            ],
          ),
        ),
        const SizedBox(height: Gaps.lg),
        SectionColumns(
          children: [
            SectionCard(
              title: 'Dettes',
              icon: Icons.account_balance_wallet_outlined,
              trailing: Text(
                Formats.money(debts.totalDebt),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: debts.totalDebt > 0 ? AppColors.danger : AppColors.success,
                ),
              ),
              child: debts.sales.isEmpty
                  ? const Text('Aucune dette : toutes les ventes sont soldées.')
                  : Column(
                      children: [
                        for (final sale in debts.sales)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Gaps.sm),
                            child: AppCard(
                              padding: const EdgeInsets.all(Gaps.md),
                              onTap: () => context.push('/sales/${sale.id}'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(sale.number, style: theme.textTheme.titleSmall)),
                                      Badges.paymentStatus(sale.paymentStatus.code),
                                    ],
                                  ),
                                  const SizedBox(height: Gaps.xs),
                                  Text(
                                    '${Formats.date(sale.createdAt)} · ${sale.store.label} · total ${Formats.money(sale.total)}'
                                    ' · payé ${Formats.money(sale.amountPaid)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: Gaps.sm),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Reste ${Formats.money(sale.remainingAmount)}',
                                              style: theme.textTheme.titleSmall?.copyWith(color: AppColors.danger),
                                            ),
                                            if (sale.dueDate != null)
                                              Text(
                                                'Prochaine échéance ${Formats.date(sale.dueDate)}${sale.isOverdue ? ' (dépassée)' : ''}',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: sale.isOverdue ? AppColors.danger : null,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (user.can(Perm.paymentCreate))
                                        FilledButton.tonalIcon(
                                          onPressed: () => _collect(sale, customer),
                                          icon: const Icon(Icons.payments_outlined, size: 18),
                                          label: const Text('Encaisser'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            SectionCard(
              title: 'Achats (${detail.sales.total})',
              icon: Icons.receipt_long_outlined,
              trailing: detail.sales.total > detail.sales.items.length
                  ? TextButton(
                      onPressed: () => context.go('/sales?customer_id=${customer.id}'),
                      child: const Text('Tout voir'),
                    )
                  : null,
              child: detail.sales.items.isEmpty
                  ? const Text('Aucun achat.')
                  : Column(
                      children: [
                        for (final sale in detail.sales.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Gaps.sm),
                            child: SaleCard(sale: sale, onTap: () => context.push('/sales/${sale.id}')),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
