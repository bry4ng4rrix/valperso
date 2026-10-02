import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/status_badge.dart';
import 'roles_repository.dart';

/// Libellés des modules de permissions.
const _moduleLabels = {
  'dashboard': 'Tableau de bord',
  'report': 'Rapports',
  'user': 'Utilisateurs',
  'role': 'Rôles',
  'permission': 'Permissions',
  'store': 'Magasins et transferts',
  'product': 'Produits et catégories',
  'stock': 'Stock',
  'sale': 'Ventes',
  'payment': 'Paiements',
  'cash': 'Caisse',
  'audit': 'Audit',
  'company': 'Société',
  'chat': 'Messages',
};

/// Rôles et permissions. La modification (permission.assign) est confirmée avec la liste
/// des permissions ajoutées et retirées.
class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  late Future<(List<Role>, List<PermissionItem>)> _future = _load();

  Future<(List<Role>, List<PermissionItem>)> _load() async {
    final repository = context.read<RolesRepository>();
    final user = context.read<SessionController>().requireUser;
    final roles = repository.list();
    final permissions = user.can(Perm.permissionView) ? repository.permissions() : Future.value(<PermissionItem>[]);
    return (await roles, await permissions);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().requireUser;
    return DetailPage(
      title: 'Rôles et permissions',
      maxWidth: 900,
      child: FutureBuilder<(List<Role>, List<PermissionItem>)>(
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
          if (!snapshot.hasData) return const LoadingState(lines: 3);
          final (roles, permissions) = snapshot.data!;
          final all = permissions.isEmpty
              ? {
                  for (final role in roles)
                    for (final permission in role.permissions) permission.id: permission,
                }.values.toList()
              : permissions;
          return ListView(
            padding: const EdgeInsets.all(Gaps.lg),
            children: [
              for (final role in roles)
                Card(
                  margin: const EdgeInsets.only(bottom: Gaps.lg),
                  child: ExpansionTile(
                    leading: Badges.role(role.name),
                    title: Text(Formats.capitalize(role.description ?? role.name)),
                    subtitle: Text('${role.permissions.length} permission${role.permissions.length > 1 ? 's' : ''}'),
                    childrenPadding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
                    children: [
                      _RoleEditor(
                        role: role,
                        allPermissions: all,
                        canEdit: user.can(Perm.permissionAssign) && permissions.isNotEmpty,
                        onSaved: () => setState(() {
                          _future = _load();
                        }),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RoleEditor extends StatefulWidget {
  const _RoleEditor({required this.role, required this.allPermissions, required this.canEdit, required this.onSaved});

  final Role role;
  final List<PermissionItem> allPermissions;
  final bool canEdit;
  final VoidCallback onSaved;

  @override
  State<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends State<_RoleEditor> {
  late Set<int> _selected = {for (final permission in widget.role.permissions) permission.id};

  Set<int> get _initial => {for (final permission in widget.role.permissions) permission.id};

  Future<void> _save() async {
    final added = widget.allPermissions.where((p) => _selected.contains(p.id) && !_initial.contains(p.id)).toList();
    final removed = widget.allPermissions.where((p) => !_selected.contains(p.id) && _initial.contains(p.id)).toList();
    if (added.isEmpty && removed.isEmpty) return;
    final confirmed = await showConfirmation(
      context,
      title: 'Modifier les permissions du rôle ${widget.role.name} ?',
      message: 'Tous les utilisateurs ayant ce rôle sont concernés immédiatement.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final permission in added)
            Text('+ ${permission.name}', style: const TextStyle(color: AppColors.success)),
          for (final permission in removed)
            Text('− ${permission.name}', style: const TextStyle(color: AppColors.danger)),
        ],
      ),
      confirmLabel: 'Enregistrer',
      type: ConfirmationType.warning,
      doubleCheck: widget.role.isAdmin && removed.isNotEmpty,
    );
    if (!confirmed || !mounted) return;
    final done = await runApiAction(
      context,
      () => context.read<RolesRepository>().setPermissions(widget.role.id, _selected),
      success: 'Permissions enregistrées.',
    );
    if (!done || !mounted) return;
    await context.read<SessionController>().reloadProfile();
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byModule = <String, List<PermissionItem>>{};
    for (final permission in widget.allPermissions) {
      byModule.putIfAbsent(permission.module, () => []).add(permission);
    }
    final changed = _selected.length != _initial.length || !_selected.containsAll(_initial);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in byModule.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: Gaps.md, bottom: Gaps.xs),
            child: Text(_moduleLabels[entry.key] ?? entry.key, style: theme.textTheme.titleSmall),
          ),
          for (final permission in entry.value)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _selected.contains(permission.id),
              onChanged: widget.canEdit
                  ? (checked) => setState(() {
                      _selected = {..._selected};
                      checked == true ? _selected.add(permission.id) : _selected.remove(permission.id);
                    })
                  : null,
              title: Text(permission.name),
              subtitle: permission.description == null ? null : Text(Formats.capitalize(permission.description)),
            ),
        ],
        if (widget.canEdit) ...[
          const SizedBox(height: Gaps.md),
          Row(
            children: [
              if (changed)
                TextButton(
                  onPressed: () => setState(() => _selected = _initial),
                  child: const Text('Annuler les changements'),
                ),
              const Spacer(),
              AppButton(label: 'Enregistrer', icon: Icons.check, onPressed: changed ? _save : null),
            ],
          ),
        ],
      ],
    );
  }
}
