import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
import '../../shared/widgets/list_period_filter.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/store_selector.dart';
import '../sales/sale_models.dart';
import '../sales/sale_widgets.dart';
import '../sales/sales_repository.dart';
import 'payment_dialog.dart';
import 'payment_models.dart';
import 'payments_repository.dart';

/// Paiements reçus et ventes avec un reste à payer (dettes).
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> with SingleTickerProviderStateMixin {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late final bool _canSeeDebts = _user.can(Perm.saleView);
  late final TabController _tabs = TabController(length: _canSeeDebts ? 2 : 1, vsync: this);
  late final PagedController<Payment> _payments = PagedController(
    (query) => context.read<PaymentsRepository>().list(query),
    filters: const {'sort': '-created_at'},
  );
  late final PagedController<Sale> _debts = PagedController(
    (query) => context.read<SalesRepository>().history(query),
    filters: const {'has_debt': true, 'status': 'COMPLETED', 'sort': 'created_at'},
    fixedKeys: const {'has_debt', 'status'},
  );

  @override
  void initState() {
    super.initState();
    _payments.load();
    if (_canSeeDebts) _debts.load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _payments.dispose();
    _debts.dispose();
    super.dispose();
  }

  Future<void> _collect(Sale sale) async {
    final payment = await showPaymentDialog(
      context,
      saleId: sale.id,
      saleNumber: sale.number,
      remaining: sale.remainingAmount,
      customerName: sale.customer.fullName,
    );
    if (payment != null && mounted) {
      await _debts.refresh();
      await _payments.refresh();
    }
  }

  void _paymentFilters() {
    showFilterSheet(
      context,
      onReset: () => _payments.clearFilters(keep: {'date_from', 'date_to', 'sort'}),
      builder: (context, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterDropdown<String>(
            label: 'Mode de paiement',
            value: _payments.filter('method') as String?,
            options: {for (final method in PaymentMethod.collected) method.code: method.label},
            onChanged: (value) {
              _payments.setFilter('method', value);
              refresh();
            },
          ),
          if (_user.canChooseStore)
            StoreSelector(
              value: _payments.filter('store_id') as int?,
              allLabel: 'Tous les magasins',
              onChanged: (store) {
                _payments.setFilter('store_id', store?.id);
                refresh();
              },
            ),
          const SizedBox(height: Gaps.md),
          ChoiceChips<String>(
            label: 'Trier par',
            value: (_payments.filter('sort') as String?) ?? '-created_at',
            options: const {'-created_at': 'Plus récents', '-amount': 'Montant ↓', 'amount': 'Montant ↑'},
            onChanged: (value) {
              _payments.setFilter('sort', value);
              refresh();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptivePage(
      title: 'Paiements et dettes',
      bottom: TabBar(
        controller: _tabs,
        tabs: [
          const Tab(text: 'Paiements reçus'),
          if (_canSeeDebts) const Tab(text: 'Dettes en cours'),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _Tab(
            controller: _payments,
            onOpenFilters: _paymentFilters,
            quickFilters: ListPeriodFilter(controller: _payments),
            export: ExportButton<Payment>(
              controller: _payments,
              fileBaseName: 'paiements',
              sheetName: 'Paiements',
              columns: [
                ExportColumn('Date', (payment) => payment.createdAt),
                ExportColumn('Vente', (payment) => payment.saleId),
                ExportColumn('Mode', (payment) => payment.method.label),
                ExportColumn('Montant (Ar)', (payment) => payment.amount),
                ExportColumn('Référence', (payment) => payment.reference),
                ExportColumn('Encaissé par', (payment) => payment.creator?.fullName),
              ],
            ),
            list: PagedListView<Payment>(
              controller: _payments,
              onTap: (payment) => context.push('/sales/${payment.saleId}'),
              emptyTitle: 'Aucun paiement',
              emptyMessage: 'Modifiez la période ou les filtres.',
              columns: [
                TableColumnDef.text('Date', (payment) => Formats.dateTime(payment.createdAt)),
                TableColumnDef.text('Mode', (payment) => payment.method.label),
                TableColumnDef.text('Montant', (payment) => Formats.money(payment.amount), numeric: true),
                TableColumnDef.text('Référence', (payment) => payment.reference ?? '—'),
                TableColumnDef.text('Encaissé par', (payment) => payment.creator?.fullName ?? '—'),
              ],
              cardBuilder: (context, payment) => AppCard(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.md),
                onTap: () => context.push('/sales/${payment.saleId}'),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text('${payment.method.label} — ${Formats.money(payment.amount)}'),
                  subtitle: Text(
                    [
                      Formats.dateTime(payment.createdAt),
                      if (payment.creator != null) payment.creator!.fullName,
                      if (payment.reference != null) 'réf. ${payment.reference}',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ),
          ),
          if (_canSeeDebts)
            _Tab(
              controller: _debts,
              search: AppSearchField(
                hint: 'Client, téléphone ou n° de facture',
                onChanged: (value) => _debts.setFilter('search', value),
              ),
              onOpenFilters: _user.canChooseStore
                  ? () => showFilterSheet(
                      context,
                      onReset: () => _debts.clearFilters(keep: {'sort', 'search'}),
                      builder: (context, refresh) => StoreSelector(
                        value: _debts.filter('store_id') as int?,
                        allLabel: 'Tous les magasins',
                        onChanged: (store) {
                          _debts.setFilter('store_id', store?.id);
                          refresh();
                        },
                      ),
                    )
                  : null,
              export: ExportButton<Sale>(
                controller: _debts,
                fileBaseName: 'dettes',
                sheetName: 'Dettes',
                columns: saleExportColumns,
              ),
              list: PagedListView<Sale>(
                controller: _debts,
                onTap: (sale) => context.push('/sales/${sale.id}'),
                emptyTitle: 'Aucune dette en cours',
                emptyMessage: 'Toutes les ventes sont soldées.',
                cardBuilder: (context, sale) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SaleCard(sale: sale, onTap: () => context.push('/sales/${sale.id}')),
                    if (_user.can(Perm.paymentCreate))
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _collect(sale),
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          label: const Text('Encaisser'),
                        ),
                      ),
                  ],
                ),
                columns: [
                  ...saleTableColumns(showStore: _user.canChooseStore),
                  if (_user.can(Perm.paymentCreate))
                    TableColumnDef(
                      '',
                      (sale) => TextButton(onPressed: () => _collect(sale), child: const Text('Encaisser')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.controller,
    required this.list,
    required this.export,
    this.search,
    this.onOpenFilters,
    this.quickFilters,
  });

  final PagedController<dynamic> controller;
  final Widget list;
  final Widget export;
  final Widget? search;
  final VoidCallback? onOpenFilters;
  final Widget? quickFilters;

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
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: search ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  if (onOpenFilters != null)
                    ListenableBuilder(
                      listenable: controller,
                      builder: (_, _) =>
                          FilterButton(activeCount: controller.activeFilterCount, onPressed: onOpenFilters!),
                    ),
                  export,
                ],
              ),
              if (quickFilters != null) ...[const SizedBox(height: Gaps.sm), quickFilters!],
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
