import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';

/// Grille dont le nombre de colonnes dépend de la largeur disponible.
/// Les éléments gardent leur hauteur naturelle (pas de débordement).
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 200,
    this.maxColumns = 4,
    this.spacing = Gaps.md,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = math.max(1, math.min(maxColumns, ((width + spacing) / (minItemWidth + spacing)).floor()));
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final child in children) SizedBox(width: itemWidth, child: child)],
        );
      },
    );
  }
}

/// Deux colonnes sur grand écran, une seule sur mobile.
class TwoColumns extends StatelessWidget {
  const TwoColumns({
    super.key,
    required this.left,
    required this.right,
    this.breakpoint = 900,
    this.leftFlex = 1,
    this.rightFlex = 1,
  });

  final Widget left;
  final Widget right;
  final double breakpoint;
  final int leftFlex;
  final int rightFlex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: Gaps.lg),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leftFlex, child: left),
            const SizedBox(width: Gaps.lg),
            Expanded(flex: rightFlex, child: right),
          ],
        );
      },
    );
  }
}
