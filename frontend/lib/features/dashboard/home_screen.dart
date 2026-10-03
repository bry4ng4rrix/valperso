import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/navigation.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/periods.dart';
import '../../shared/widgets/adaptive_page.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/collapsible_grid.dart';
import '../../shared/widgets/period_selector.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/stat_card.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/store_selector.dart';
import '../sales/sale_models.dart';
import '../sales/sale_widgets.dart';
import '../sales/sales_repository.dart';
import '../stock/stock_models.dart';
import '../stock/stock_repository.dart';
import 'bar_chart.dart';
import 'dashboard_repository.dart';
import 'sales_chart.dart';

/// Accueil : tableau de bord si l'utilisateur y a accès, sinon un accueil orienté vente.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().requireUser;
    return user.can(Perm.dashboardView) ? DashboardView(user: user) : SellerHomeView(user: user);
  }
}

/// Actions rapides selon les permissions.
List<Widget> quickActions(BuildContext context, CurrentUser user) => [
  if (user.can(Perm.saleCreate))
    QuickActionCard(label: 'Nouvelle vente', icon: Icons.add_shopping_cart, onTap: () => context.go(Routes.newSale)),
  if (user.can(Perm.saleView))
    QuickActionCard(
      label: 'Historique des ventes',
      icon: Icons.receipt_long,
      onTap: () => context.go(Routes.salesHistory),
    ),
  if (user.can(Perm.productCreate))
    QuickActionCard(label: 'Nouveau produit', icon: Icons.add_box_outlined, onTap: () => context.push('/products/new')),
  if (user.can(Perm.stockEntry))
    QuickActionCard(
      label: 'Entrée de stock',
      icon: Icons.move_to_inbox_outlined,
      onTap: () => context.go(Routes.movements),
    ),
  if (user.canCreateTransfer)
    QuickActionCard(label: 'Nouveau transfert', icon: Icons.swap_horiz, onTap: () => context.push('/transfers/new')),
  if (user.can(Perm.saleView))
    QuickActionCard(
      label: 'Clients avec dette',
      icon: Icons.account_balance_wallet_outlined,
      onTap: () => context.go('${Routes.customers}?debt=1'),
    ),
  if (!user.can(Perm.saleCreate) && user.can(Perm.productView))
    QuickActionCard(label: 'Produits', icon: Icons.inventory_2_outlined, onTap: () => context.go(Routes.products)),
];

// --- Tableau de bord (ADMIN) --------------------------------------------------------------------

class DashboardView extends StatefulWidget {
  const DashboardView({super.key, required this.user});

  final CurrentUser user;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  Period _period = Period.today;
  DateTimeRange? _customRange;
  int? _storeId;
  late Future<DashboardSummary> _summary;
  Future<List<SalesPoint>>? _chart;

  bool get _canReport => widget.user.can(Perm.reportView);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repository = context.read<DashboardRepository>();
    final range = rangeFor(_period, custom: _customRange).toQuery();
    _summary = repository.summary(range: range, storeId: _storeId);
    final showChart = _canReport && _period != Period.today && _period != Period.yesterday;
    _chart = showChart
        ? repository.sales(
            range: range,
            storeId: _storeId,
            groupBy: _period == Period.thisYear || _period == Period.all ? 'month' : 'day',
          )
        : null;
  }

  Future<void> _refresh() async {
    setState(_load);
    await _summary;
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return AdaptivePage(
      title: 'Tableau de bord',
      subtitle: 'Bonjour ${user.fullName}',
      actions: [IconButton(tooltip: 'Actualiser', onPressed: _refresh, icon: const Icon(Icons.refresh))],
      body: PageBody(
        onRefresh: _refresh,
        children: [
          PeriodSelector(
            period: _period,
            customRange: _customRange,
            periods: const [
              Period.today,
              Period.yesterday,
              Period.thisWeek,
              Period.thisMonth,
              Period.thisYear,
              Period.custom,
            ],
            onChanged: (period, range) => setState(() {
              _period = period;
              _customRange = range;
              _load();
            }),
          ),
          if (user.canChooseStore) ...[
            const SizedBox(height: Gaps.md),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: StoreSelector(
                  value: _storeId,
                  allLabel: 'Tous les magasins',
                  dense: true,
                  onChanged: (store) => setState(() {
                    _storeId = store?.id;
                    _load();
                  }),
                ),
              ),
            ),
          ],
          const SizedBox(height: Gaps.lg),
          FutureBuilder<DashboardSummary>(
            future: _summary,
            builder: (context, snapshot) {
              if (snapshot.hasError) return ErrorState(message: errorMessageOf(snapshot.error), onRetry: _refresh);
              if (!snapshot.hasData) return const SizedBox(height: 360, child: LoadingState(lines: 4));
              return _SummaryContent(summary: snapshot.data!, user: user, chart: _chart);
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.summary, required this.user, required this.chart});

  final DashboardSummary summary;
  final CurrentUser user;
  final Future<List<SalesPoint>>? chart;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final actions = quickActions(context, user);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 4 indicateurs affichés, les autres derrière le bouton « ⋯ ».
        CollapsibleGrid(
          title: 'Indicateurs',
          visibleCount: 4,
          minItemWidth: 180,
          children: [
            StatCard(label: 'Chiffre d\'affaires', value: Formats.money(s.revenue), icon: Icons.trending_up),
            StatCard(
              label: 'Ventes',
              value: Formats.quantity(s.salesCount),
              icon: Icons.receipt_long,
              onTap: () => context.go(Routes.salesHistory),
            ),
            // Les marges révèlent les prix : réservées à qui peut voir les rapports.
            if (user.can(Perm.reportView)) ...[
              StatCard(
                label: 'Bénéfice estimé',
                value: Formats.money(s.estimatedProfit),
                icon: Icons.savings_outlined,
                tone: s.estimatedProfit < 0 ? AppColors.danger : AppColors.success,
                caption: 'Marge du stock actuel',
              ),
              StatCard(
                label: 'Encaissé',
                value: Formats.money(s.salesMargin),
                icon: Icons.payments_outlined,
                tone: s.salesMargin < 0 ? AppColors.danger : null,
                caption: 'Marge des produits vendus',
              ),
            ],
            StatCard(
              label: 'Reste à encaisser',
              value: Formats.money(s.debtAmount),
              icon: Icons.account_balance_wallet_outlined,
              tone: s.debtAmount > 0 ? AppColors.warning : null,
              caption: 'Ventes de la période',
              onTap: () => context.go('${Routes.customers}?debt=1'),
            ),
            StatCard(
              label: 'Stock faible',
              value: Formats.quantity(s.lowStockCount),
              icon: Icons.trending_down,
              tone: s.lowStockCount > 0 ? AppColors.warning : null,
              onTap: () => context.go('${Routes.products}?state=low'),
            ),
            StatCard(
              label: 'Ruptures (par magasin)',
              value: Formats.quantity(s.outOfStockCount),
              icon: Icons.block,
              tone: s.outOfStockCount > 0 ? AppColors.danger : null,
              onTap: () => context.go('${Routes.products}?state=out'),
            ),
            StatCard(
              label: 'Produits indisponibles partout',
              value: Formats.quantity(s.unavailableProductsCount),
              icon: Icons.remove_shopping_cart_outlined,
              tone: s.unavailableProductsCount > 0 ? AppColors.danger : null,
              caption: '${Formats.quantity(s.productsCount)} produits actifs',
            ),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: Gaps.xl),
          CollapsibleGrid(title: 'Actions rapides', visibleCount: 3, minItemWidth: 220, children: actions),
        ],
        if (chart != null) ...[
          const SizedBox(height: Gaps.xl),
          SectionCard(
            title: 'Évolution des ventes',
            icon: Icons.bar_chart,
            child: FutureBuilder<List<SalesPoint>>(
              future: chart,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('Graphique indisponible.');
                if (!snapshot.hasData) {
                  return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
                }
                return SalesChart(points: snapshot.data!);
              },
            ),
          ),
        ],
        const SizedBox(height: Gaps.xl),
        // Ventes par produit sur la période choisie : même échelle pour comparer les deux graphiques.
        ResponsiveGrid(
          minItemWidth: 340,
          maxColumns: 2,
          children: [
            _ProductsChart(
              title: 'Produits les plus vendus',
              icon: Icons.emoji_events_outlined,
              products: s.topProducts,
              maxQuantity: _maxQuantity(s),
            ),
            _ProductsChart(
              title: 'Produits les moins vendus',
              subtitle: 'Parmi les produits en stock',
              icon: Icons.trending_down,
              products: s.leastSoldProducts,
              maxQuantity: _maxQuantity(s),
              color: AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: Gaps.lg),
        ResponsiveGrid(
          minItemWidth: 340,
          maxColumns: 2,
          children: [
            _StoresPerformance(stores: s.storesPerformance, showMargin: user.can(Perm.reportView)),
            _RecentSales(sales: s.recentSales),
          ],
        ),
      ],
    );
  }
}

class _RecentSales extends StatelessWidget {
  const _RecentSales({required this.sales});

  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Dernières ventes',
      icon: Icons.receipt_long_outlined,
      trailing: TextButton(onPressed: () => context.go(Routes.salesHistory), child: const Text('Tout voir')),
      child: sales.isEmpty
          ? const Padding(padding: EdgeInsets.all(Gaps.md), child: Text('Aucune vente sur la période.'))
          : Column(
              children: [
                for (final sale in sales.take(6))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(sale.customer.fullName, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${sale.number} · ${Formats.time(sale.createdAt)}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(Formats.money(sale.total), style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Badges.paymentStatus(sale.paymentStatus.code),
                      ],
                    ),
                    onTap: () => context.push('/sales/${sale.id}'),
                  ),
              ],
            ),
    );
  }
}

double _maxQuantity(DashboardSummary summary) => [
  ...summary.topProducts,
  ...summary.leastSoldProducts,
].fold(0.0, (max, product) => product.quantitySold > max ? product.quantitySold.toDouble() : max);

/// Graphique des ventes par produit (quantités vendues sur la période).
class _ProductsChart extends StatelessWidget {
  const _ProductsChart({
    required this.title,
    required this.icon,
    required this.products,
    required this.maxQuantity,
    this.subtitle,
    this.color,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<TopProduct> products;
  final double maxQuantity;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          HorizontalBarChart(
            color: color,
            maxValue: maxQuantity,
            emptyText: 'Aucune vente sur la période.',
            entries: [
              for (final product in products)
                BarEntry(
                  label: Formats.capitalize(product.name),
                  value: product.quantitySold.toDouble(),
                  valueText: '${Formats.quantity(product.quantitySold)} vendu${product.quantitySold > 1 ? 's' : ''}',
                  detail: [
                    product.reference.toUpperCase(),
                    if (product.quantitySold > 0) Formats.money(product.revenue),
                    if (product.stockQuantity != null) '${Formats.quantity(product.stockQuantity!)} en stock',
                  ].join(' · '),
                  onTap: () => context.push('/products/${product.productId}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Performance de chaque magasin sur la période : chiffre d'affaires (barre), ventes, marge, reste à payer.
class _StoresPerformance extends StatelessWidget {
  const _StoresPerformance({required this.stores, required this.showMargin});

  final List<StorePerformance> stores;

  /// La marge révèle les prix : seulement pour qui peut voir les rapports.
  final bool showMargin;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Performance des magasins',
      icon: Icons.storefront_outlined,
      child: HorizontalBarChart(
        color: AppColors.success,
        emptyText: 'Aucun magasin.',
        entries: [
          for (final performance in stores)
            BarEntry(
              label: performance.store.label,
              value: performance.revenue,
              valueText: Formats.money(performance.revenue),
              detail: [
                '${Formats.quantity(performance.salesCount)} vente${performance.salesCount > 1 ? 's' : ''}',
                if (showMargin) 'marge ${Formats.money(performance.salesMargin)}',
                if (performance.debtAmount > 0) 'reste ${Formats.money(performance.debtAmount)}',
                '${Formats.quantity(performance.stockQuantity)} en stock',
              ].join(' · '),
              onTap: () => context.push('/stores/${performance.store.id}'),
            ),
        ],
      ),
    );
  }
}

/// Stocks à surveiller (accueil vendeur : stock faible ou rupture dans son magasin).
class _LowStockSection extends StatelessWidget {
  const _LowStockSection({required this.future});

  final Future<Paged<StockLine>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<StockLine>>(
      future: future,
      builder: (context, snapshot) {
        final page = snapshot.data;
        if (page == null || page.items.isEmpty) return const SizedBox.shrink();
        return SectionCard(
          title: 'Stocks à surveiller (${page.total})',
          icon: Icons.warning_amber_rounded,
          trailing: TextButton(
            onPressed: () => context.go('${Routes.products}?state=low'),
            child: const Text('Tout voir'),
          ),
          child: Column(children: [for (final line in page.items) LowStockTile(line: line)]),
        );
      },
    );
  }
}

/// Ligne d'alerte de stock.
class LowStockTile extends StatelessWidget {
  const LowStockTile({super.key, required this.line});

  final StockLine line;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(line.product.label, overflow: TextOverflow.ellipsis),
      subtitle: Text('${line.store.label} · seuil ${line.alertThreshold}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Formats.quantity(line.quantity), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: Gaps.sm),
          Badges.stock(outOfStock: line.outOfStock, lowStock: line.lowStock),
        ],
      ),
      onTap: () => context.push('/products/${line.product.id}'),
    );
  }
}

// --- Accueil vendeur ------------------------------------------------------------------------------

class SellerHomeView extends StatefulWidget {
  const SellerHomeView({super.key, required this.user});

  final CurrentUser user;

  @override
  State<SellerHomeView> createState() => _SellerHomeViewState();
}

class _SellerHomeViewState extends State<SellerHomeView> {
  Future<Paged<Sale>>? _todaySales;
  Future<Paged<StockLine>>? _alerts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final user = widget.user;
    if (user.can(Perm.saleView)) {
      _todaySales = context.read<SalesRepository>().history(
        PageQuery(pageSize: PageQuery.maxPageSize, filters: rangeFor(Period.today).toQuery()),
      );
    }
    if (user.can(Perm.stockView)) {
      _alerts = context.read<StockRepository>().lowStock(PageQuery(pageSize: 5, filters: {'store_id': user.store?.id}));
    }
  }

  Future<void> _refresh() async {
    setState(_load);
    await _todaySales;
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final actions = quickActions(context, user);
    return AdaptivePage(
      title: 'Accueil',
      subtitle: user.store?.label,
      actions: [IconButton(tooltip: 'Actualiser', onPressed: _refresh, icon: const Icon(Icons.refresh))],
      body: PageBody(
        onRefresh: _refresh,
        children: [
          Text('Bonjour ${user.fullName}', style: Theme.of(context).textTheme.headlineSmall),
          if (user.store != null)
            Padding(
              padding: const EdgeInsets.only(top: Gaps.xs),
              child: Text('Magasin : ${user.store!.label}', style: Theme.of(context).textTheme.bodyMedium),
            ),
          const SizedBox(height: Gaps.lg),
          if (_todaySales != null) _TodaySummary(future: _todaySales!),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: Gaps.xl),
            CollapsibleGrid(title: 'Actions rapides', visibleCount: 3, minItemWidth: 220, children: actions),
          ],
          if (_alerts != null) ...[const SizedBox(height: Gaps.xl), _LowStockSection(future: _alerts!)],
        ],
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.future});

  final Future<Paged<Sale>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Sale>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        if (!snapshot.hasData) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
        final page = snapshot.data!;
        final valid = page.items.where((sale) => !sale.isCancelled).toList();
        final revenue = valid.fold(0.0, (sum, sale) => sum + sale.total);
        final collected = valid.fold(0.0, (sum, sale) => sum + sale.amountPaid);
        final partial = page.total > page.items.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ResponsiveGrid(
              minItemWidth: 160,
              children: [
                StatCard(label: 'Ventes du jour', value: Formats.quantity(valid.length), icon: Icons.receipt_long),
                StatCard(
                  label: 'Montant du jour',
                  value: Formats.money(revenue),
                  icon: Icons.trending_up,
                  caption: partial ? '100 dernières ventes' : null,
                ),
                StatCard(label: 'Encaissé', value: Formats.money(collected), icon: Icons.payments_outlined),
              ],
            ),
            if (page.items.isNotEmpty) ...[
              const SizedBox(height: Gaps.lg),
              SectionCard(
                title: 'Dernières ventes',
                icon: Icons.receipt_long_outlined,
                trailing: TextButton(onPressed: () => context.go(Routes.salesHistory), child: const Text('Historique')),
                child: Column(
                  children: [
                    for (final sale in page.items.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gaps.sm),
                        child: SaleCard(sale: sale, showStore: false, onTap: () => context.push('/sales/${sale.id}')),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
