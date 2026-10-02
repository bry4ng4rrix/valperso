import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';
import 'responsive_grid.dart';

/// Section en grille qui n'affiche que les [visibleCount] premiers éléments.
/// Le bouton « ⋯ » à droite du titre affiche les autres (puis « Réduire »).
class CollapsibleGrid extends StatefulWidget {
  const CollapsibleGrid({
    super.key,
    required this.title,
    required this.children,
    required this.visibleCount,
    this.minItemWidth = 200,
    this.maxColumns = 4,
  });

  final String title;
  final List<Widget> children;
  final int visibleCount;
  final double minItemWidth;
  final int maxColumns;

  @override
  State<CollapsibleGrid> createState() => _CollapsibleGridState();
}

class _CollapsibleGridState extends State<CollapsibleGrid> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hidden = widget.children.length - widget.visibleCount;
    final shown = _expanded || hidden <= 0 ? widget.children : widget.children.take(widget.visibleCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
            if (hidden > 0)
              IconButton(
                tooltip: _expanded ? 'Réduire' : 'Afficher $hidden de plus',
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.more_horiz),
              ),
          ],
        ),
        const SizedBox(height: Gaps.sm),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: ResponsiveGrid(minItemWidth: widget.minItemWidth, maxColumns: widget.maxColumns, children: shown),
        ),
      ],
    );
  }
}
