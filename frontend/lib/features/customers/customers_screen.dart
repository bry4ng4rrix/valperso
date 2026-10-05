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
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/store_selector.dart';
import 'customer_models.dart';
import 'customers_repository.dart';

/// Clients et contacts, avec un onglet « Avec dette ».
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, this.debtOnly = false});

  final bool debtOnly;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> with SingleTickerProviderStateMixin {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.debtOnly ? 1 : 0);
  late final PagedController<CustomerContact> _controller = PagedController(
    (query) => context.read<CustomersRepository>().contacts(query),
    filters: widget.debtOnly ? {'has_debt': true, 'sort': '-remaining_amount'} : const {},
    fixedKeys: const {'has_debt'},
    liveEntities: const {'customer', 'sale', 'payment'},
  );

  @override
  void initState() {
    super.initState();
    _controller.load();
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      final debt = _tabs.index == 1;
      _controller.updateFilters({'has_debt': debt ? true : null, 'sort': debt ? '-remaining_amount' : null});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(CustomerContact contact) async {
    await context.push('/customers/${contact.id}');
    if (mounted) await _controller.refresh();
  }

  void _openFilters() {
    showFilterSheet(
      context,
      onReset: () => _controller.clearFilters(keep: {'search'}),
      builder: (context, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_user.canChooseStore)
            Padding(
              padding: const EdgeInsets.only(bottom: Gaps.md),
              child: StoreSelector(
                label: 'A acheté dans le magasin',
                value: _controller.filter('store_id') as int?,
                allLabel: 'Tous les magasins',
                onChanged: (store) {
                  _controller.setFilter('store_id', store?.id);
                  refresh();
                },
              ),
            ),
          ChoiceChips<String>(
            label: 'Trier par',
            value: (_controller.filter('sort') as String?) ?? 'name',
            options: const {
              'name': 'Nom',
              '-remaining_amount': 'Plus grosse dette',
              '-total_amount': 'Plus gros acheteurs',
              '-last_sale_date': 'Achat le plus récent',
              '-created_at': 'Nouveaux clients',
            },
            onChanged: (value) {
              _controller.setFilter('sort', value);
              refresh();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListPage(
      title: 'Clients',
      controller: _controller,
      countLabel: (total) => '$total client${total > 1 ? 's' : ''}',
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Tous'),
          Tab(text: 'Avec dette'),
        ],
      ),
      search: AppSearchField(hint: 'Nom ou téléphone', onChanged: (value) => _controller.setFilter('search', value)),
      onOpenFilters: _openFilters,
      actions: [
        ExportButton<CustomerContact>(
          controller: _controller,
          fileBaseName: 'clients',
          sheetName: 'Clients',
          columns: [
            ExportColumn('Nom', (contact) => contact.fullName),
            ExportColumn('Téléphone', (contact) => contact.phone),
            ExportColumn('Achats', (contact) => contact.totalPurchases),
            ExportColumn('Montant total (Ar)', (contact) => contact.totalAmount),
            ExportColumn('Payé (Ar)', (contact) => contact.totalPaid),
            ExportColumn('Reste à payer (Ar)', (contact) => contact.remainingAmount),
            ExportColumn('Dernier achat', (contact) => contact.lastSaleDate),
          ],
        ),
      ],
      primaryAction: _user.can(Perm.saleCreate)
          ? PrimaryAction(
              label: 'Nouveau client',
              icon: Icons.person_add_alt,
              onPressed: () async {
                await context.push('/customers/new');
                if (mounted) await _controller.refresh();
              },
            )
          : null,
      body: PagedListView<CustomerContact>(
        controller: _controller,
        onTap: _open,
        emptyTitle: 'Aucun client',
        emptyMessage: 'Les clients sont créés au moment de la vente ou depuis le bouton « Nouveau client ».',
        columns: [
          TableColumnDef.text('Client', (contact) => contact.fullName),
          TableColumnDef.text('Téléphone', (contact) => contact.phone ?? '—'),
          TableColumnDef.text('Achats', (contact) => '${contact.totalPurchases}', numeric: true),
          TableColumnDef.text('Total', (contact) => Formats.money(contact.totalAmount), numeric: true),
          TableColumnDef(
            'Reste à payer',
            (contact) => Text(
              Formats.money(contact.remainingAmount),
              style: contact.hasDebt ? const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600) : null,
            ),
            numeric: true,
          ),
          TableColumnDef.text('Dernier achat', (contact) => Formats.date(contact.lastSaleDate)),
        ],
        cardBuilder: (context, contact) => CustomerCard(contact: contact, onTap: () => _open(contact)),
      ),
    );
  }
}

class CustomerCard extends StatelessWidget {
  const CustomerCard({super.key, required this.contact, this.onTap});

  final CustomerContact contact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Gaps.md),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              contact.fullName.isEmpty ? '?' : contact.fullName[0].toUpperCase(),
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
          const SizedBox(width: Gaps.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.fullName, style: theme.textTheme.titleSmall),
                Text(contact.phone ?? 'Pas de téléphone', style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  '${contact.totalPurchases} achat${contact.totalPurchases > 1 ? 's' : ''} · ${Formats.money(contact.totalAmount)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (contact.hasDebt)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const StatusBadge('Dette', tone: BadgeTone.danger),
                const SizedBox(height: Gaps.xs),
                Text(
                  Formats.money(contact.remainingAmount),
                  style: theme.textTheme.titleSmall?.copyWith(color: AppColors.danger),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
