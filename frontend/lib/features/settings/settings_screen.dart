import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app.dart';
import '../../app/navigation.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/auth/settings_controller.dart';
import '../../shared/widgets/adaptive_page.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/status_badge.dart';
import '../auth/logout.dart';
import 'api_url_dialog.dart';

/// Paramètres : profil, apparence, serveur, société, rôles, session.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().requireUser;
    final settings = context.watch<SettingsController>();
    return AdaptivePage(
      title: 'Paramètres',
      body: PageBody(
        children: [
          const SizedBox(height: Gaps.sm),
          SectionColumns(
            children: [
              SectionCard(
                title: 'Mon profil',
                icon: Icons.person_outline,
                trailing: user.can(Perm.userUpdate)
                    ? TextButton(onPressed: () => context.push('/users/${user.id}/edit'), child: const Text('Modifier'))
                    : null,
                child: Column(
                  children: [
                    InfoRow(label: 'Nom', value: user.fullName),
                    InfoRow(label: 'Identifiant', value: user.username.toLowerCase()),
                    InfoRow(label: 'Email', value: user.email ?? '—'),
                    InfoRow(
                      label: 'Magasin',
                      value: user.store?.label ?? (user.isAdmin ? 'Tous les magasins' : 'Aucun'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gaps.xs),
                      child: Row(
                        children: [
                          Expanded(child: Text('Rôle', style: Theme.of(context).textTheme.bodyMedium)),
                          Badges.role(user.role.name),
                        ],
                      ),
                    ),
                    InfoRow(label: 'Permissions', value: '${user.permissions.length}'),
                  ],
                ),
              ),
              SectionCard(
                title: 'Apparence',
                icon: Icons.palette_outlined,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, label: Text('Sombre'), icon: Icon(Icons.dark_mode_outlined)),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Clair'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (selection) => settings.setThemeMode(selection.first),
                  ),
                ),
              ),
              SectionCard(
                title: 'Serveur',
                icon: Icons.dns_outlined,
                trailing: TextButton(onPressed: () => showApiUrlDialog(context), child: const Text('Modifier')),
                child: InfoRow(label: 'Adresse de l\'API', value: settings.apiUrl),
              ),
              if (user.can(Perm.companyView) || user.can(Perm.roleView)) ...[
                SectionCard(
                  title: 'Administration',
                  icon: Icons.admin_panel_settings_outlined,
                  child: Column(
                    children: [
                      if (user.can(Perm.companyView))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.business_outlined),
                          title: const Text('Informations de la société'),
                          subtitle: const Text('Nom, logo et coordonnées affichés sur les factures'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(Routes.company),
                        ),
                      if (user.can(Perm.roleView))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.key_outlined),
                          title: const Text('Rôles et permissions'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(Routes.roles),
                        ),
                    ],
                  ),
                ),
              ],
              SectionCard(
                title: 'Session',
                icon: Icons.security_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Les jetons de connexion sont conservés dans le stockage sécurisé de l\'appareil. '
                      'Le mot de passe n\'est jamais enregistré.',
                    ),
                    const SizedBox(height: Gaps.md),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => confirmLogout(context),
                        icon: const Icon(Icons.logout, color: AppColors.danger),
                        label: const Text('Se déconnecter', style: TextStyle(color: AppColors.danger)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gaps.lg),
          Center(
            child: TextButton(
              onPressed: () => showAboutDialog(
                context: context,
                applicationName: AppInfo.name,
                applicationVersion: '1.0.0',
                children: const [
                  Text('Gestion commerciale multi-magasins (Android et Linux), reliée à l\'API FastAPI.'),
                ],
              ),
              child: const Text('À propos'),
            ),
          ),
        ],
      ),
    );
  }
}
