import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/export/excel_export.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/list_period_filter.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../users/user_models.dart';
import '../users/users_repository.dart';
import 'audit_repository.dart';
import '../../core/widgets/app_dialog.dart';

const _entityLabels = {
  'user': 'Utilisateur',
  'role': 'Rôle',
  'store': 'Magasin',
  'category': 'Catégorie',
  'product': 'Produit',
  'stock': 'Stock',
  'stock_transfer': 'Transfert',
  'customer': 'Client',
  'sale': 'Vente',
  'payment': 'Paiement',
  'company': 'Société',
};

/// Journal d'audit : qui a fait quoi, quand, avec l'état avant / après.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  late final PagedController<AuditLog> _controller = PagedController(
    (query) => context.read<AuditRepository>().list(query),
    pageSize: 30,
  );
  late final Future<Map<int, String>> _users = _loadUsers();

  Future<Map<int, String>> _loadUsers() async {
    final user = context.read<SessionController>().requireUser;
    if (!user.can(Perm.userView)) return const {};
    final page = await context.read<UsersRepository>().list(const PageQuery(pageSize: PageQuery.maxPageSize));
    return {for (final AppUser item in page.items) item.id: item.fullName};
  }

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

  void _openFilters(Map<int, String> users) {
    showFilterSheet(
      context,
      onReset: () => _controller.clearFilters(keep: {'action', 'date_from', 'date_to'}),
      builder: (context, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterDropdown<String>(
            label: 'Élément',
            value: _controller.filter('entity_type') as String?,
            options: _entityLabels,
            onChanged: (value) {
              _controller.setFilter('entity_type', value);
              refresh();
            },
          ),
          if (users.isNotEmpty)
            FilterDropdown<int>(
              label: 'Utilisateur',
              value: _controller.filter('user_id') as int?,
              options: users,
              onChanged: (value) {
                _controller.setFilter('user_id', value);
                refresh();
              },
            ),
        ],
      ),
    );
  }

  void _showDetail(AuditLog log, Map<int, String> users) {
    showDialog<void>(
      context: context,
      builder: (_) => _AuditDetailDialog(log: log, userName: users[log.userId]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<int, String>>(
      future: _users,
      builder: (context, snapshot) {
        final users = snapshot.data ?? const <int, String>{};
        String who(AuditLog log) => log.userId == null ? 'Système' : users[log.userId] ?? 'Utilisateur #${log.userId}';
        String what(AuditLog log) =>
            '${_entityLabels[log.entityType] ?? log.entityType}${log.entityId == null ? '' : ' #${log.entityId}'}';
        return ListPage(
          title: 'Journal d\'audit',
          controller: _controller,
          countLabel: (total) => '$total entrée${total > 1 ? 's' : ''}',
          search: AppSearchField(
            hint: 'Action (ex. sale.create)',
            onChanged: (value) => _controller.setFilter('action', value),
          ),
          onOpenFilters: () => _openFilters(users),
          quickFilters: ListPeriodFilter(controller: _controller),
          actions: [
            ExportButton<AuditLog>(
              controller: _controller,
              fileBaseName: 'audit',
              sheetName: 'Audit',
              columns: [
                ExportColumn('Date', (log) => log.createdAt),
                ExportColumn('Utilisateur', who),
                ExportColumn('Action', (log) => log.action),
                ExportColumn('Élément', what),
                ExportColumn('Adresse IP', (log) => log.ipAddress),
                ExportColumn('Avant', (log) => log.oldData == null ? null : jsonEncode(log.oldData)),
                ExportColumn('Après', (log) => log.newData == null ? null : jsonEncode(log.newData)),
              ],
            ),
          ],
          body: PagedListView<AuditLog>(
            controller: _controller,
            onTap: (log) => _showDetail(log, users),
            emptyTitle: 'Aucune entrée',
            emptyMessage: 'Modifiez la période ou les filtres.',
            columns: [
              TableColumnDef.text('Date', (log) => Formats.dateTime(log.createdAt)),
              TableColumnDef.text('Utilisateur', who),
              TableColumnDef.text('Action', (log) => log.action),
              TableColumnDef.text('Élément', what),
              TableColumnDef.text('IP', (log) => log.ipAddress ?? '—'),
            ],
            cardBuilder: (context, log) => AppCard(
              onTap: () => _showDetail(log, users),
              padding: const EdgeInsets.all(Gaps.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(log.action, style: Theme.of(context).textTheme.titleSmall)),
                      Text(Formats.dateTime(log.createdAt), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${who(log)} · ${what(log)}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AuditDetailDialog extends StatelessWidget {
  const _AuditDetailDialog({required this.log, this.userName});

  final AuditLog log;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = {...?log.oldData?.keys, ...?log.newData?.keys}.toList()..sort();
    String show(Object? value) => value == null ? '—' : (value is String ? value : jsonEncode(value));
    return AppDialog(
      title: log.action,
      size: DialogSize.large,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(label: 'Date', value: Formats.dateTime(log.createdAt)),
          InfoRow(label: 'Utilisateur', value: userName ?? (log.userId == null ? 'Système' : '#${log.userId}')),
          InfoRow(label: 'Élément', value: '${log.entityType}${log.entityId == null ? '' : ' #${log.entityId}'}'),
          if (log.ipAddress != null) InfoRow(label: 'Adresse IP', value: log.ipAddress!),
          if (keys.isNotEmpty) ...[
            const Divider(),
            Text('Changements', style: theme.textTheme.titleSmall),
            const SizedBox(height: Gaps.sm),
            for (final key in keys)
              _ChangeLine(
                field: key,
                before: log.oldData == null ? null : show(log.oldData![key]),
                after: log.newData == null ? null : show(log.newData![key]),
              ),
          ],
        ],
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer'))],
    );
  }
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.field, this.before, this.after});

  final String field;
  final String? before;
  final String? after;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = before != null && after != null && before != after;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field, style: theme.textTheme.labelMedium),
          if (before != null && (changed || after == null))
            Text(
              before!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.danger,
                decoration: changed ? TextDecoration.lineThrough : null,
              ),
            ),
          if (after != null)
            Text(after!, style: theme.textTheme.bodySmall?.copyWith(color: changed ? AppColors.success : null)),
        ],
      ),
    );
  }
}
