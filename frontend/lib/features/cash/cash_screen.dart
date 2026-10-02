import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/export/excel_export.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/adaptive_page.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/list_period_filter.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/store_selector.dart';
import '../stores/store_models.dart';
import '../stores/stores_repository.dart';
import 'cash_models.dart';
import 'cash_repository.dart';
import 'cash_widgets.dart';

/// Libellés des magasins par identifiant (les caisses ne renvoient que store_id).
Future<Map<int, String>> storeLabels(BuildContext context, CurrentUser user) async {
  if (!user.can(Perm.storeView)) {
    return {if (user.store != null) user.store!.id: user.store!.label};
  }
  final stores = await context.read<StoresRepository>().active();
  return {for (final Store store in stores) store.id: store.label};
}

/// Caisse : caisse ouverte du magasin (ouverture, opérations, fermeture) et historique.
class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> with SingleTickerProviderStateMixin {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late int? _storeId = _user.store?.id;
  late final Future<Map<int, String>> _labels = storeLabels(context, _user);
  late final Future<CashSchedule?> _schedule = context.read<CashRepository>().schedule();
  late Future<(CashRegister?, Map<int, String>)> _current = _loadCurrent();
  late final PagedController<CashRegister> _history = PagedController(
    (query) => context.read<CashRepository>().registers(query),
    filters: const {'sort': '-opened_at'},
  );
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_historyLoaded) {
        _historyLoaded = true;
        _history.load();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _history.dispose();
    super.dispose();
  }

  Future<(CashRegister?, Map<int, String>)> _loadCurrent() async {
    // L'administrateur commence sur le Stock Local : le magasin affiché est toujours celui de la caisse.
    if (_storeId == null && _user.canChooseStore) {
      final stores = await context.read<StoresRepository>().active();
      final central = stores.where((store) => store.isCentral).firstOrNull;
      if (central != null && mounted) setState(() => _storeId = central.id);
    }
    if (!mounted) return (null, const <int, String>{});
    final register = await context.read<CashRepository>().current(storeId: _storeId);
    return (register, await _labels);
  }

  void _reload() {
    setState(() {
      _current = _loadCurrent();
    });
    if (_historyLoaded) _history.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptivePage(
      title: 'Caisse',
      actions: [IconButton(tooltip: 'Actualiser', onPressed: _reload, icon: const Icon(Icons.refresh))],
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Caisse en cours'),
          Tab(text: 'Historique'),
        ],
      ),
      body: TabBarView(controller: _tabs, children: [_currentTab(), _historyTab()]),
    );
  }

  Widget _currentTab() {
    return PageBody(
      onRefresh: () async => _reload(),
      children: [
        const SizedBox(height: Gaps.lg),
        FutureBuilder<CashSchedule?>(
          future: _schedule,
          builder: (context, snapshot) {
            final schedule = snapshot.data;
            if (schedule == null || !schedule.enabled) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: Gaps.lg),
              child: ScheduleBanner(schedule: schedule),
            );
          },
        ),
        if (_user.canChooseStore) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: StoreSelector(
              value: _storeId,
              label: 'Magasin',
              onChanged: (store) {
                _storeId = store?.id;
                _reload();
              },
            ),
          ),
          const SizedBox(height: Gaps.lg),
        ],
        FutureBuilder<(CashRegister?, Map<int, String>)>(
          future: _current,
          builder: (context, snapshot) {
            if (snapshot.hasError) return ErrorState(message: errorMessageOf(snapshot.error), onRetry: _reload);
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(height: 240, child: LoadingState(lines: 3));
            }
            final (register, labels) = snapshot.data!;
            final storeLabel =
                labels[register?.storeId ?? _storeId] ?? (_storeId == null ? 'Magasin par défaut' : 'Magasin');
            return register == null ? _closedView(storeLabel) : _openView(register, storeLabel);
          },
        ),
      ],
    );
  }

  Widget _closedView(String storeLabel) {
    return AppCard(
      padding: const EdgeInsets.all(Gaps.xl),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: Gaps.md),
          Text('Aucune caisse ouverte', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Gaps.xs),
          Text(
            '$storeLabel — les ventes payées en espèces nécessitent une caisse ouverte.',
            textAlign: TextAlign.center,
          ),
          FutureBuilder<CashSchedule?>(
            future: _schedule,
            builder: (context, snapshot) {
              final schedule = snapshot.data;
              if (schedule == null || !schedule.enabled) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: Gaps.sm),
                child: Text(
                  'Elle s\'ouvrira automatiquement à ${schedule.openTime} (${schedule.timezoneLabel}).',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          ),
          if (_user.can(Perm.cashOpen)) ...[
            const SizedBox(height: Gaps.xl),
            FilledButton.icon(
              onPressed: () async {
                final register = await showOpenRegisterDialog(context, storeId: _storeId, storeLabel: storeLabel);
                if (register != null && mounted) _reload();
              },
              icon: const Icon(Icons.lock_open),
              label: const Text('Ouvrir la caisse'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _openView(CashRegister register, String storeLabel) {
    return SectionColumns(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'Caisse ouverte',
              icon: Icons.point_of_sale,
              trailing: cashStatusBadge(register),
              child: RegisterSummary(register: register, storeLabel: storeLabel),
            ),
            const SizedBox(height: Gaps.lg),
            Wrap(
              spacing: Gaps.md,
              runSpacing: Gaps.md,
              children: [
                if (_user.can(Perm.cashTransaction))
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final saved = await showCashTransactionDialog(context, register);
                      if (saved && mounted) _reload();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Opération de caisse'),
                  ),
                if (_user.can(Perm.cashClose))
                  AppButton(
                    label: 'Fermer la caisse',
                    icon: Icons.lock_outline,
                    variant: AppButtonVariant.danger,
                    onPressed: () async {
                      final closed = await showCloseRegisterDialog(context, register);
                      if (closed != null && mounted) _reload();
                    },
                  ),
              ],
            ),
          ],
        ),
        SectionCard(
          title: 'Mouvements de la caisse',
          icon: Icons.receipt_long_outlined,
          child: RegisterTransactions(
            registerId: register.id,
            key: ValueKey('tx-${register.id}-${register.expectedAmount}'),
          ),
        ),
      ],
    );
  }

  Widget _historyTab() {
    return FutureBuilder<Map<int, String>>(
      future: _labels,
      builder: (context, snapshot) {
        final labels = snapshot.data ?? const <int, String>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.md, Gaps.lg, Gaps.sm),
              child: Row(
                children: [
                  Expanded(child: ListPeriodFilter(controller: _history)),
                  ListenableBuilder(
                    listenable: _history,
                    builder: (context, _) => FilterButton(
                      activeCount: _history.activeFilterCount,
                      onPressed: () => showFilterSheet(
                        context,
                        onReset: () => _history.clearFilters(keep: {'sort', 'date_from', 'date_to'}),
                        builder: (context, refresh) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilterDropdown<String>(
                              label: 'Statut',
                              value: _history.filter('status') as String?,
                              options: const {'OPEN': 'Ouvertes', 'CLOSED': 'Fermées'},
                              onChanged: (value) {
                                _history.setFilter('status', value);
                                refresh();
                              },
                            ),
                            if (_user.canChooseStore)
                              StoreSelector(
                                value: _history.filter('store_id') as int?,
                                allLabel: 'Tous les magasins',
                                onChanged: (store) {
                                  _history.setFilter('store_id', store?.id);
                                  refresh();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ExportButton<CashRegister>(
                    controller: _history,
                    fileBaseName: 'caisses',
                    sheetName: 'Caisses',
                    columns: [
                      ExportColumn('Magasin', (register) => labels[register.storeId] ?? '${register.storeId}'),
                      ExportColumn('Ouverture', (register) => register.openedAt),
                      ExportColumn('Fermeture', (register) => register.closedAt),
                      ExportColumn('Fond de caisse (Ar)', (register) => register.openingAmount),
                      ExportColumn('Montant théorique (Ar)', (register) => register.expectedAmount),
                      ExportColumn('Montant compté (Ar)', (register) => register.closingAmount),
                      ExportColumn('Écart (Ar)', (register) => register.difference),
                      ExportColumn('Statut', (register) => register.isOpen ? 'Ouverte' : 'Fermée'),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: PagedListView<CashRegister>(
                controller: _history,
                onTap: (register) => context.push('/cash/${register.id}'),
                emptyTitle: 'Aucune caisse',
                emptyMessage: 'Modifiez la période ou les filtres.',
                columns: [
                  TableColumnDef.text('Magasin', (register) => labels[register.storeId] ?? '—'),
                  TableColumnDef.text('Ouverture', (register) => Formats.dateTime(register.openedAt)),
                  TableColumnDef.text(
                    'Fermeture',
                    (register) =>
                        '${Formats.dateTime(register.closedAt)}${register.closedAutomatically ? ' (auto)' : ''}',
                  ),
                  TableColumnDef.text('Théorique', (register) => Formats.money(register.expectedAmount), numeric: true),
                  TableColumnDef.text('Compté', (register) => Formats.money(register.closingAmount), numeric: true),
                  TableColumnDef(
                    'Écart',
                    (register) => Text(
                      register.difference == null ? '—' : Formats.money(register.difference),
                      style: TextStyle(color: differenceColor(register.difference)),
                    ),
                    numeric: true,
                  ),
                  const TableColumnDef('Statut', cashStatusBadge),
                ],
                cardBuilder: (context, register) => AppCard(
                  onTap: () => context.push('/cash/${register.id}'),
                  padding: const EdgeInsets.all(Gaps.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(labels[register.storeId] ?? 'Caisse', style: Theme.of(context).textTheme.titleSmall),
                            Text(
                              '${Formats.dateTime(register.openedAt)}'
                              '${register.closedAt == null ? '' : ' → ${Formats.dateTime(register.closedAt)}'}'
                              '${register.closedAutomatically ? ' (fermeture automatique)' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: Gaps.xs),
                            cashStatusBadge(register),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Formats.money(register.closingAmount ?? register.expectedAmount),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (register.difference != null && register.difference != 0)
                            Text(
                              'Écart ${Formats.money(register.difference)}',
                              style: TextStyle(color: differenceColor(register.difference)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Mouvements d'une caisse (les 50 plus récents, avec un lien vers la suite).
class RegisterTransactions extends StatefulWidget {
  const RegisterTransactions({super.key, required this.registerId});

  final int registerId;

  @override
  State<RegisterTransactions> createState() => _RegisterTransactionsState();
}

class _RegisterTransactionsState extends State<RegisterTransactions> {
  int _page = 1;
  late Future<Paged<CashTransaction>> _future = _load();

  Future<Paged<CashTransaction>> _load() => context.read<CashRepository>().transactions(
    widget.registerId,
    PageQuery(page: _page, pageSize: 50, filters: const {'sort': '-created_at'}),
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<CashTransaction>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(
            message: errorMessageOf(snapshot.error),
            onRetry: () => setState(() {
              _future = _load();
            }),
          );
        }
        if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(Gaps.lg), child: LinearProgressIndicator());
        final page = snapshot.data!;
        if (page.items.isEmpty) return const Text('Aucun mouvement pour le moment.');
        return Column(
          children: [
            for (final transaction in page.items) TransactionTile(transaction: transaction),
            if (page.pages > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _page > 1 ? () => _goTo(_page - 1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Page $_page / ${page.pages}'),
                  IconButton(
                    onPressed: _page < page.pages ? () => _goTo(_page + 1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  void _goTo(int page) => setState(() {
    _page = page;
    _future = _load();
  });
}

/// Rappel des horaires automatiques de la caisse.
class ScheduleBanner extends StatelessWidget {
  const ScheduleBanner({super.key, required this.schedule});

  final CashSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Gaps.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: Gaps.sm),
          Expanded(
            child: Text(
              'Ouverture automatique à ${schedule.openTime} et fermeture automatique à ${schedule.closeTime} '
              '(${schedule.timezoneLabel}). À la fermeture automatique, le montant compté est le montant '
              'théorique : pour enregistrer un écart, fermez la caisse vous-même avant ${schedule.closeTime}.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
