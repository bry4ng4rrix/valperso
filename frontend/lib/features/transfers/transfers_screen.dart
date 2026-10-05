import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/session_controller.dart';
import '../../core/export/excel_export.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/list_period_filter.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/store_selector.dart';
import 'transfer_models.dart';
import 'transfers_repository.dart';

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late final PagedController<StockTransfer> _controller = PagedController(
    (query) => context.read<TransfersRepository>().list(query),
    liveEntities: const {'transfer'},
  );

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(StockTransfer transfer) async {
    await context.push('/transfers/${transfer.id}');
    if (mounted) await _controller.refresh();
  }

  void _openFilters() {
    showFilterSheet(
      context,
      onReset: () => _controller.clearFilters(keep: {'date_from', 'date_to'}),
      builder: (context, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_user.canChooseStore) ...[
            StoreSelector(
              label: 'Magasin source',
              value: _controller.filter('source_store_id') as int?,
              allLabel: 'Tous',
              onChanged: (store) {
                _controller.setFilter('source_store_id', store?.id);
                refresh();
              },
            ),
            const SizedBox(height: Gaps.md),
            StoreSelector(
              label: 'Magasin de destination',
              value: _controller.filter('destination_store_id') as int?,
              allLabel: 'Tous',
              onChanged: (store) {
                _controller.setFilter('destination_store_id', store?.id);
                refresh();
              },
            ),
            const SizedBox(height: Gaps.md),
          ],
          FilterDropdown<String>(
            label: 'Statut',
            value: _controller.filter('status') as String?,
            options: const {'COMPLETED': 'Effectués', 'CANCELLED': 'Annulés'},
            onChanged: (value) {
              _controller.setFilter('status', value);
              refresh();
            },
          ),
          ChoiceChips<String>(
            label: 'Trier par',
            value: (_controller.filter('sort') as String?) ?? '-created_at',
            options: const {'-created_at': 'Plus récents', 'created_at': 'Plus anciens', 'reference': 'Référence'},
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
      title: 'Transferts',
      controller: _controller,
      countLabel: (total) => '$total transfert${total > 1 ? 's' : ''}',
      onOpenFilters: _openFilters,
      quickFilters: ListPeriodFilter(controller: _controller),
      actions: [
        ExportButton<StockTransfer>(
          controller: _controller,
          fileBaseName: 'transferts',
          sheetName: 'Transferts',
          columns: [
            ExportColumn('Référence', (transfer) => transfer.reference),
            ExportColumn('Date', (transfer) => transfer.createdAt),
            ExportColumn('Source', (transfer) => transfer.source.label),
            ExportColumn('Destination', (transfer) => transfer.destination.label),
            ExportColumn('Produits', (transfer) => transfer.items.length),
            ExportColumn('Quantité totale', (transfer) => transfer.totalQuantity),
            ExportColumn(
              'Détail',
              (transfer) =>
                  transfer.items.map((item) => '${Formats.capitalize(item.product.name)} x${item.quantity}').join(', '),
            ),
            ExportColumn('Statut', (transfer) => transfer.isCancelled ? 'Annulé' : 'Effectué'),
            ExportColumn('Créé par', (transfer) => transfer.creator.fullName),
          ],
        ),
      ],
      primaryAction: _user.canCreateTransfer
          ? PrimaryAction(
              label: 'Nouveau transfert',
              icon: Icons.add,
              onPressed: () async {
                await context.push('/transfers/new');
                if (mounted) await _controller.refresh();
              },
            )
          : null,
      body: PagedListView<StockTransfer>(
        controller: _controller,
        onTap: _open,
        emptyTitle: 'Aucun transfert',
        emptyMessage: 'Modifiez la période ou les filtres.',
        columns: [
          TableColumnDef.text('Référence', (transfer) => transfer.reference),
          TableColumnDef.text('Date', (transfer) => Formats.dateTime(transfer.createdAt)),
          TableColumnDef.text('Source', (transfer) => transfer.source.label),
          TableColumnDef.text('Destination', (transfer) => transfer.destination.label),
          TableColumnDef.text('Produits', (transfer) => '${transfer.items.length}', numeric: true),
          TableColumnDef.text('Quantité', (transfer) => Formats.quantity(transfer.totalQuantity), numeric: true),
          TableColumnDef('Statut', (transfer) => Badges.transferStatus(transfer.status)),
          TableColumnDef.text('Par', (transfer) => transfer.creator.fullName),
        ],
        cardBuilder: (context, transfer) => TransferCard(transfer: transfer, onTap: () => _open(transfer)),
      ),
    );
  }
}

class TransferCard extends StatelessWidget {
  const TransferCard({super.key, required this.transfer, this.onTap});

  final StockTransfer transfer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Gaps.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(transfer.reference, style: theme.textTheme.titleSmall)),
              Badges.transferStatus(transfer.status),
            ],
          ),
          const SizedBox(height: Gaps.sm),
          Row(
            children: [
              Flexible(child: Text(transfer.source.label, overflow: TextOverflow.ellipsis)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: Gaps.sm),
                child: Icon(Icons.arrow_forward, size: 18),
              ),
              Flexible(child: Text(transfer.destination.label, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: Gaps.xs),
          Text(
            '${transfer.items.length} produit${transfer.items.length > 1 ? 's' : ''} · '
            '${Formats.quantity(transfer.totalQuantity)} unités · ${Formats.dateTime(transfer.createdAt)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
