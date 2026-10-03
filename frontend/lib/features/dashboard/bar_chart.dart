import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';

/// Une barre du graphique : libellé, valeur (longueur de la barre) et textes affichés.
class BarEntry {
  const BarEntry({required this.label, required this.value, required this.valueText, this.detail, this.onTap});

  final String label;
  final double value;
  final String valueText;
  final String? detail;
  final VoidCallback? onTap;
}

/// Graphique en barres horizontales (sans bibliothèque de graphiques) : lisible sur téléphone
/// comme sur ordinateur, chaque barre garde son libellé et sa valeur en clair.
class HorizontalBarChart extends StatelessWidget {
  const HorizontalBarChart({super.key, required this.entries, this.color, this.maxValue, this.emptyText});

  final List<BarEntry> entries;
  final Color? color;

  /// Valeur d'une barre pleine (par défaut la plus grande valeur) : permet de comparer deux graphiques.
  final double? maxValue;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(padding: const EdgeInsets.all(Gaps.md), child: Text(emptyText ?? 'Aucune donnée.'));
    }
    final theme = Theme.of(context);
    final barColor = color ?? theme.colorScheme.primary;
    final double max = maxValue ?? entries.map((entry) => entry.value).fold<double>(0, math.max);
    return Column(
      children: [
        for (final entry in entries)
          InkWell(
            onTap: entry.onTap,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Gaps.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.label,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: Gaps.sm),
                      Text(entry.valueText, style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: Gaps.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(height: 8, color: theme.colorScheme.surfaceContainerHighest),
                        FractionallySizedBox(
                          widthFactor: max <= 0 ? 0 : (entry.value / max).clamp(0, 1),
                          child: Container(height: 8, color: barColor),
                        ),
                      ],
                    ),
                  ),
                  if (entry.detail != null) ...[
                    const SizedBox(height: Gaps.xs),
                    Text(entry.detail!, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
