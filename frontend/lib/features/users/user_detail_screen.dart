import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/status_badge.dart';
import '../stores/store_models.dart';
import '../stores/stores_repository.dart';
import 'user_models.dart';
import 'users_repository.dart';

/// Fiche utilisateur : informations, rôle, magasin et statut (chaque changement est confirmé).
class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({super.key, required this.userId});

  final int userId;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  late Future<AppUser> _future = context.read<UsersRepository>().get(widget.userId);

  void _reload() => setState(() {
    _future = context.read<UsersRepository>().get(widget.userId);
  });

  Future<void> _afterChange(bool done, AppUser user) async {
    if (!done || !mounted) return;
    _reload();
    // Ses propres informations ont changé : on recharge le profil (permissions, magasin).
    final session = context.read<SessionController>();
    if (session.user?.id == user.id) await session.reloadProfile();
  }

  Future<void> _changeRole(AppUser user) async {
    final newRole = user.role.isAdmin ? 'VENDEUR' : 'ADMIN';
    final confirmed = await showConfirmation(
      context,
      title: 'Changer le rôle de ${user.fullName} ?',
      message: newRole == 'ADMIN'
          ? 'Un administrateur a accès à tous les magasins et à toute la gestion.'
          : 'Un vendeur ne voit que son magasin. Pensez à lui affecter un magasin.',
      changes: [FieldChange('Rôle', user.role.name, newRole)],
      confirmLabel: 'Changer le rôle',
      type: ConfirmationType.warning,
      doubleCheck: newRole == 'ADMIN',
    );
    if (!confirmed || !mounted) return;
    final done = await runApiAction(
      context,
      () => context.read<UsersRepository>().changeRole(user.id, newRole),
      success: 'Rôle modifié.',
    );
    await _afterChange(done, user);
  }

  Future<void> _changeStore(AppUser user) async {
    final stores = await context.read<StoresRepository>().active();
    if (!mounted) return;
    final choice = await showDialog<(Store?,)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Affecter à un magasin'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.of(context).pop((null,)), child: const Text('Aucun magasin')),
          for (final store in stores)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop((store,)),
              child: Row(
                children: [
                  Expanded(child: Text(store.label)),
                  if (store.id == user.store?.id) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final store = choice.$1;
    if (store?.id == user.store?.id) return;
    final confirmed = await showConfirmation(
      context,
      title: 'Changer le magasin de ${user.fullName} ?',
      message: user.role.isAdmin ? null : 'Le vendeur ne verra plus que les ventes et le stock du nouveau magasin.',
      changes: [FieldChange('Magasin', user.store?.label ?? 'Aucun', store?.label ?? 'Aucun')],
      confirmLabel: 'Changer',
      type: ConfirmationType.warning,
    );
    if (!confirmed || !mounted) return;
    final done = await runApiAction(
      context,
      () => context.read<UsersRepository>().changeStore(user.id, store?.id),
      success: 'Magasin modifié.',
    );
    await _afterChange(done, user);
  }

  Future<void> _changeStatus(AppUser user) async {
    final activate = !user.isActive;
    final confirmed = await showConfirmation(
      context,
      title: activate ? 'Réactiver ${user.fullName} ?' : 'Désactiver ${user.fullName} ?',
      message: activate
          ? 'L\'utilisateur pourra de nouveau se connecter.'
          : 'L\'utilisateur ne pourra plus se connecter. Ses sessions en cours sont fermées. Son historique est conservé.',
      changes: [FieldChange('Statut', activate ? 'Désactivé' : 'Actif', activate ? 'Actif' : 'Désactivé')],
      confirmLabel: activate ? 'Réactiver' : 'Désactiver',
      type: activate ? ConfirmationType.normal : ConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;
    final done = await runApiAction(
      context,
      () => context.read<UsersRepository>().changeStatus(user.id, isActive: activate),
      success: activate ? 'Utilisateur réactivé.' : 'Utilisateur désactivé.',
    );
    await _afterChange(done, user);
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionController>().requireUser;
    return FutureBuilder<AppUser>(
      future: _future,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final canUpdate = me.can(Perm.userUpdate);
        final isMe = user?.id == me.id;
        return DetailPage(
          title: user?.fullName ?? 'Utilisateur',
          maxWidth: 760,
          actions: [
            if (user != null && canUpdate)
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  await context.push('/users/${user.id}/edit');
                  if (mounted) await _afterChange(true, user);
                },
              ),
          ],
          child: snapshot.hasError
              ? ErrorState(message: errorMessageOf(snapshot.error), onRetry: _reload)
              : user == null
              ? const LoadingState(lines: 3)
              : ListView(
                  padding: const EdgeInsets.all(Gaps.lg),
                  children: [
                    SectionCard(
                      title: 'Informations',
                      icon: Icons.person_outline,
                      trailing: Badges.active(user.isActive),
                      child: Column(
                        children: [
                          InfoRow(label: 'Nom', value: user.fullName),
                          InfoRow(label: 'Identifiant', value: user.username.toLowerCase()),
                          InfoRow(label: 'Email', value: user.email ?? '—'),
                          InfoRow(label: 'Téléphone', value: user.phone ?? '—'),
                          InfoRow(label: 'Créé le', value: Formats.date(user.createdAt)),
                        ],
                      ),
                    ),
                    const SizedBox(height: Gaps.lg),
                    SectionCard(
                      title: 'Accès',
                      icon: Icons.admin_panel_settings_outlined,
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Rôle'),
                            subtitle: Align(alignment: Alignment.centerLeft, child: Badges.role(user.role.name)),
                            trailing: canUpdate && !isMe
                                ? TextButton(onPressed: () => _changeRole(user), child: const Text('Changer'))
                                : null,
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Magasin'),
                            subtitle: Text(user.storeLabel),
                            trailing: canUpdate && me.can(Perm.storeView)
                                ? TextButton(onPressed: () => _changeStore(user), child: const Text('Changer'))
                                : null,
                          ),
                          if (isMe)
                            Padding(
                              padding: const EdgeInsets.only(top: Gaps.sm),
                              child: Text(
                                'Vous ne pouvez pas changer votre propre rôle ni désactiver votre compte.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (canUpdate && !isMe) ...[
                      const SizedBox(height: Gaps.xl),
                      OutlinedButton.icon(
                        onPressed: () => _changeStatus(user),
                        icon: Icon(
                          user.isActive ? Icons.block : Icons.check_circle_outline,
                          color: user.isActive ? AppColors.danger : AppColors.success,
                        ),
                        label: Text(
                          user.isActive ? 'Désactiver le compte' : 'Réactiver le compte',
                          style: TextStyle(color: user.isActive ? AppColors.danger : AppColors.success),
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}
