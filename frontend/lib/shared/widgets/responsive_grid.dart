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

/// Sections d'un écran : empilées sur mobile, réparties en colonnes sur grand écran
/// (chaque section garde sa hauteur naturelle ; l'ordre de lecture est gauche → droite).
class SectionColumns extends StatelessWidget {
  const SectionColumns({
    super.key,
    required this.children,
    this.minColumnWidth = 440,
    this.maxColumns = 2,
    this.spacing = Gaps.lg,
  });

  final List<Widget> children;
  final double minColumnWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = ((constraints.maxWidth + spacing) / (minColumnWidth + spacing)).floor();
        final columns = math.max(1, math.min(math.min(maxColumns, fit), children.length));
        Widget column(Iterable<Widget> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, item) in items.indexed) ...[if (index > 0) SizedBox(height: spacing), item],
          ],
        );
        if (columns == 1) return column(children);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) SizedBox(width: spacing),
              Expanded(child: column([for (var i = c; i < children.length; i += columns) children[i]])),
            ],
          ],
        );
      },
    );
  }
}
