import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/export/excel_export.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/status_badge.dart';
import 'store_models.dart';
import 'stores_repository.dart';

class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  late final PagedController<Store> _controller = PagedController(
    (query) => context.read<StoresRepository>().list(query),
    filters: const {'is_active': true},
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

  Future<void> _open(Store store) async {
    await context.push('/stores/${store.id}');
    if (mounted) await _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().requireUser;
    return ListPage(
      title: 'Magasins',
      controller: _controller,
      countLabel: (total) => '$total magasin${total > 1 ? 's' : ''}',
      search: AppSearchField(hint: 'Nom du magasin', onChanged: (value) => _controller.setFilter('search', value)),
      quickFilters: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Wrap(
          spacing: Gaps.sm,
          children: [
            for (final (value, label) in const [(true, 'Actifs'), (false, 'Inactifs'), (null, 'Tous')])
              ChoiceChip(
                label: Text(label),
                selected: _controller.filter('is_active') == value,
                onSelected: (_) => _controller.setFilter('is_active', value),
              ),
          ],
        ),
      ),
      actions: [
        ExportButton<Store>(
          controller: _controller,
          fileBaseName: 'magasins',
          sheetName: 'Magasins',
          columns: [
            ExportColumn('Nom', (store) => store.label),
            ExportColumn('Adresse', (store) => Formats.title(store.address)),
            ExportColumn('Téléphone', (store) => store.phone),
            ExportColumn('Stock central', (store) => store.isCentral),
            ExportColumn('Actif', (store) => store.isActive),
          ],
        ),
      ],
      primaryAction: user.can(Perm.storeCreate)
          ? PrimaryAction(
              label: 'Nouveau magasin',
              icon: Icons.add_business_outlined,
              onPressed: () async {
                await context.push('/stores/new');
                if (mounted) await _controller.refresh();
              },
            )
          : null,
      body: PagedListView<Store>(
        controller: _controller,
        onTap: _open,
        emptyTitle: 'Aucun magasin',
        columns: [
          TableColumnDef.text('Nom', (store) => store.label),
          TableColumnDef.text('Adresse', (store) => Formats.title(store.address ?? '—')),
          TableColumnDef.text('Téléphone', (store) => store.phone ?? '—'),
          TableColumnDef(
            'Type',
            (store) => store.isCentral
                ? const StatusBadge('Stock central', tone: BadgeTone.primary)
                : const StatusBadge('Magasin'),
          ),
          TableColumnDef('Statut', (store) => Badges.active(store.isActive)),
        ],
        cardBuilder: (context, store) => AppCard(
          onTap: () => _open(store),
          padding: const EdgeInsets.all(Gaps.md),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  store.isCentral ? Icons.warehouse : Icons.storefront,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.label, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      [
                        if (store.address != null) Formats.title(store.address),
                        if (store.phone != null) store.phone!,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (store.isCentral)
                const StatusBadge('Stock central', tone: BadgeTone.primary)
              else
                Badges.active(store.isActive),
            ],
          ),
        ),
      ),
    );
  }
}
