import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/export/excel_export.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/store_selector.dart';
import 'user_models.dart';
import 'users_repository.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final PagedController<AppUser> _controller = PagedController(
    (query) => context.read<UsersRepository>().list(query),
    filters: const {'is_active': true},
    liveEntities: const {'user'},
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

  Future<void> _open(AppUser user) async {
    await context.push('/users/${user.id}');
    if (mounted) await _controller.refresh();
  }

  void _openFilters() {
    showFilterSheet(
      context,
      onReset: () => _controller.clearFilters(keep: {'search'}),
      builder: (context, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterDropdown<String>(
            label: 'Rôle',
            value: _controller.filter('role') as String?,
            options: const {'ADMIN': 'Administrateurs', 'VENDEUR': 'Vendeurs'},
            onChanged: (value) {
              _controller.setFilter('role', value);
              refresh();
            },
          ),
          FilterDropdown<bool>(
            label: 'Statut',
            value: _controller.filter('is_active') as bool?,
            options: const {true: 'Actifs', false: 'Désactivés'},
            onChanged: (value) {
              _controller.setFilter('is_active', value);
              refresh();
            },
          ),
          StoreSelector(
            value: _controller.filter('store_id') as int?,
            allLabel: 'Tous les magasins',
            onChanged: (store) {
              _controller.setFilter('store_id', store?.id);
              refresh();
            },
          ),
          const SizedBox(height: Gaps.md),
          ChoiceChips<String>(
            label: 'Trier par',
            value: (_controller.filter('sort') as String?) ?? 'username',
            options: const {'username': 'Identifiant', 'last_name': 'Nom', '-created_at': 'Plus récents'},
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
    final user = context.watch<SessionController>().requireUser;
    return ListPage(
      title: 'Utilisateurs',
      controller: _controller,
      countLabel: (total) => '$total utilisateur${total > 1 ? 's' : ''}',
      search: AppSearchField(
        hint: 'Nom, identifiant ou email',
        onChanged: (value) => _controller.setFilter('search', value),
      ),
      onOpenFilters: _openFilters,
      actions: [
        ExportButton<AppUser>(
          controller: _controller,
          fileBaseName: 'utilisateurs',
          sheetName: 'Utilisateurs',
          columns: [
            ExportColumn('Nom', (user) => user.fullName),
            ExportColumn('Identifiant', (user) => user.username.toLowerCase()),
            ExportColumn('Email', (user) => user.email),
            ExportColumn('Téléphone', (user) => user.phone),
            ExportColumn('Rôle', (user) => user.role.name),
            ExportColumn('Magasin', (user) => user.storeLabel),
            ExportColumn('Actif', (user) => user.isActive),
          ],
        ),
      ],
      primaryAction: user.can(Perm.userCreate)
          ? PrimaryAction(
              label: 'Nouvel utilisateur',
              icon: Icons.person_add_alt,
              onPressed: () async {
                await context.push('/users/new');
                if (mounted) await _controller.refresh();
              },
            )
          : null,
      body: PagedListView<AppUser>(
        controller: _controller,
        onTap: _open,
        emptyTitle: 'Aucun utilisateur',
        emptyMessage: 'Modifiez la recherche ou les filtres.',
        columns: [
          TableColumnDef.text('Nom', (user) => user.fullName),
          TableColumnDef.text('Identifiant', (user) => user.username.toLowerCase()),
          TableColumnDef.text('Email', (user) => user.email ?? '—'),
          TableColumnDef('Rôle', (user) => Badges.role(user.role.name)),
          TableColumnDef.text('Magasin', (user) => user.storeLabel),
          TableColumnDef('Statut', (user) => Badges.active(user.isActive)),
        ],
        cardBuilder: (context, item) => AppCard(
          onTap: () => _open(item),
          padding: const EdgeInsets.all(Gaps.md),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  item.fullName.isEmpty ? '?' : item.fullName[0].toUpperCase(),
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.fullName, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '${item.username.toLowerCase()} · ${item.storeLabel}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Badges.role(item.role.name),
                  if (!item.isActive) ...[const SizedBox(height: Gaps.xs), Badges.active(false)],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
