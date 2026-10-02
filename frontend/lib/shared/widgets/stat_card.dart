import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';
import 'app_card.dart';

/// Indicateur du tableau de bord : libellé, valeur, et couleur seulement si l'état le justifie.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;

  /// Couleur sémantique facultative (orange pour une alerte, rouge pour un problème...).
  final Color? tone;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone ?? theme.colorScheme.primary;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Gaps.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: Gaps.sm),
              Expanded(
                child: Text(label, style: theme.textTheme.labelMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: Gaps.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: theme.textTheme.titleLarge?.copyWith(color: tone ?? theme.colorScheme.onSurface)),
          ),
          if (caption != null) Text(caption!, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Action rapide (ex. « Nouvelle vente ») : grande zone tactile, icône et libellé.
class QuickActionCard extends StatelessWidget {
  const QuickActionCard({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.md),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(Gaps.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 22),
          ),
          const SizedBox(width: Gaps.md),
          Expanded(child: Text(label, style: theme.textTheme.titleSmall, maxLines: 2)),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
