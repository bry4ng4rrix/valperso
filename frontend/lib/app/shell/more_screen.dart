import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../features/auth/logout.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../navigation.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';

/// Onglet « Plus » (mobile) : tous les écrans qui ne sont pas dans la barre du bas.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().lastUser;
    if (user == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final inBottomBar = {for (final item in bottomNavItemsFor(user)) item.path};
    final items = navItemsFor(user).where((item) => !inBottomBar.contains(item.path)).toList();

    final children = <Widget>[];
    NavSection? section;
    for (final item in items) {
      if (item.section != section) {
        section = item.section;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xs, Gaps.lg, Gaps.xs, Gaps.sm),
            child: Text(section.label, style: theme.textTheme.titleSmall),
          ),
        );
      }
      children.add(
        Card(
          margin: const EdgeInsets.only(bottom: Gaps.sm),
          child: ListTile(
            leading: Icon(item.icon, color: theme.colorScheme.primary),
            title: Text(item.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(item.path),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Plus')),
      body: ListView(
        padding: const EdgeInsets.all(Gaps.lg),
        children: [
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
                    style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontSize: 20),
                  ),
                ),
                const SizedBox(width: Gaps.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: Gaps.xs),
                      Wrap(
                        spacing: Gaps.sm,
                        runSpacing: Gaps.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Badges.role(user.role.name),
                          if (user.store != null) Text(user.store!.label, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: Gaps.lg),
          OutlinedButton.icon(
            onPressed: () => confirmLogout(context),
            icon: const Icon(Icons.logout, color: AppColors.danger),
            label: const Text('Se déconnecter', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Sizes.minTouchTarget)),
          ),
        ],
      ),
    );
  }
}
