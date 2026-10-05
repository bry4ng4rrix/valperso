import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/current_user.dart';
import '../../core/auth/session_controller.dart';
import '../../core/realtime/realtime_notices.dart';
import '../../core/utils/responsive.dart';
import '../../features/auth/logout.dart';
import '../../shared/widgets/status_badge.dart';
import '../app.dart';
import '../navigation.dart';
import '../theme/dimensions.dart';

/// Cadre commun des écrans connectés.
///
/// - mobile : barre de navigation en bas (sur les écrans principaux seulement) ;
/// - tablette : menu latéral compact (icônes) ;
/// - bureau : menu latéral complet avec l'utilisateur connecté.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().lastUser;
    if (user == null) return child;

    return RealtimeNotices(
      userId: user.id,
      child: switch (context.screenSize) {
        ScreenSize.mobile => _MobileShell(user: user, location: location, child: child),
        ScreenSize.tablet => _SideShell(user: user, location: location, compact: true, child: child),
        ScreenSize.desktop => _SideShell(user: user, location: location, compact: false, child: child),
      },
    );
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({required this.user, required this.location, required this.child});

  final CurrentUser user;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final items = bottomNavItemsFor(user);
    final showBar = isTopLevelLocation(location, allNavItems);
    final selected = navItemForLocation(location, items) ?? items.last; // sinon : « Plus »
    return Scaffold(
      body: child,
      bottomNavigationBar: showBar
          ? NavigationBar(
              selectedIndex: items.indexOf(selected),
              onDestinationSelected: (index) => context.go(items[index].path),
              destinations: [
                for (final item in items)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ),
              ],
            )
          : null,
    );
  }
}

class _SideShell extends StatelessWidget {
  const _SideShell({required this.user, required this.location, required this.compact, required this.child});

  final CurrentUser user;
  final String location;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(user: user, location: location, compact: compact),
          VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).dividerColor),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.user, required this.location, required this.compact});

  final CurrentUser user;
  final String location;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = navItemsFor(user);
    final selected = navItemForLocation(location, items);
    final children = <Widget>[];
    NavSection? section;
    for (final item in items) {
      if (item.section != section) {
        section = item.section;
        children.add(
          compact
              ? const Divider(height: Gaps.lg, indent: Gaps.md, endIndent: Gaps.md)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.lg, Gaps.lg, Gaps.xs),
                  child: Text(
                    section.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1),
                  ),
                ),
        );
      }
      children.add(_SidebarTile(item: item, selected: item == selected, compact: compact));
    }

    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: compact ? Sizes.sidebarCompactWidth : Sizes.sidebarWidth,
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SidebarHeader(compact: compact),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: Gaps.md),
                  children: children,
                ),
              ),
              const Divider(height: 1),
              _UserPanel(user: user, compact: compact),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Icon(Icons.storefront, color: Theme.of(context).colorScheme.onPrimary),
    );
    return Padding(
      padding: EdgeInsets.all(compact ? Gaps.md : Gaps.lg),
      child: compact
          ? Center(child: logo)
          : Row(
              children: [
                logo,
                const SizedBox(width: Gaps.md),
                Expanded(
                  child: Text(
                    AppInfo.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({required this.item, required this.selected, required this.compact});

  final NavItem item;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: 2),
      child: Material(
        color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: () => context.go(item.path),
          child: SizedBox(
            height: Sizes.minTouchTarget,
            child: compact
                ? Icon(selected ? item.selectedIcon : item.icon, color: color)
                : Row(
                    children: [
                      const SizedBox(width: Gaps.md),
                      Icon(selected ? item.selectedIcon : item.icon, color: color, size: 22),
                      const SizedBox(width: Gaps.md),
                      Expanded(
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: selected ? theme.colorScheme.onPrimaryContainer : null,
                            fontWeight: selected ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: item.label, child: tile) : tile;
  }
}

class _UserPanel extends StatelessWidget {
  const _UserPanel({required this.user, required this.compact});

  final CurrentUser user;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logout = IconButton(
      tooltip: 'Se déconnecter',
      onPressed: () => confirmLogout(context),
      icon: const Icon(Icons.logout),
    );
    if (compact) return Padding(padding: const EdgeInsets.all(Gaps.sm), child: logout);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.md, Gaps.sm, Gaps.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: Gaps.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Badges.role(user.role.name),
                    const SizedBox(width: Gaps.xs),
                    Flexible(
                      child: Text(
                        user.store?.label ?? '',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          logout,
        ],
      ),
    );
  }
}
