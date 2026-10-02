import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';

enum BadgeTone { neutral, primary, success, warning, danger }

/// Petit badge d'état. Le texte porte toujours l'information (jamais la couleur seule).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = BadgeTone.neutral, this.icon});

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      BadgeTone.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
      BadgeTone.primary => Theme.of(context).colorScheme.primary,
      BadgeTone.success => AppColors.success,
      BadgeTone.warning => AppColors.warning,
      BadgeTone.danger => AppColors.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Badges métier réutilisés dans plusieurs écrans.
abstract final class Badges {
  static StatusBadge paymentStatus(String status) => switch (status) {
    'PAID' => const StatusBadge('Payé', tone: BadgeTone.success, icon: Icons.check),
    'PARTIAL' => const StatusBadge('Partiel', tone: BadgeTone.warning, icon: Icons.timelapse),
    _ => const StatusBadge('Non payé', tone: BadgeTone.danger, icon: Icons.priority_high),
  };

  static StatusBadge stock({required bool outOfStock, required bool lowStock}) {
    if (outOfStock) return const StatusBadge('Épuisé', tone: BadgeTone.danger, icon: Icons.block);
    if (lowStock) return const StatusBadge('Stock faible', tone: BadgeTone.warning, icon: Icons.trending_down);
    return const StatusBadge('Disponible', tone: BadgeTone.success, icon: Icons.check);
  }

  static StatusBadge active(bool isActive) => isActive
      ? const StatusBadge('Actif', tone: BadgeTone.success)
      : const StatusBadge('Inactif', tone: BadgeTone.neutral);

  static StatusBadge saleStatus(String status) => status == 'CANCELLED'
      ? const StatusBadge('Annulée', tone: BadgeTone.danger, icon: Icons.cancel_outlined)
      : const StatusBadge('Validée', tone: BadgeTone.primary);

  static StatusBadge role(String role) => role == 'ADMIN'
      ? const StatusBadge('ADMIN', tone: BadgeTone.primary, icon: Icons.shield_outlined)
      : const StatusBadge('VENDEUR', tone: BadgeTone.neutral, icon: Icons.person_outline);

  static StatusBadge transferStatus(String status) => status == 'CANCELLED'
      ? const StatusBadge('Annulé', tone: BadgeTone.danger)
      : const StatusBadge('Effectué', tone: BadgeTone.success);
}
