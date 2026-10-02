import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme/dimensions.dart';
import '../../core/utils/formatters.dart';
import 'dashboard_repository.dart';

/// Histogramme simple du chiffre d'affaires (sans bibliothèque de graphiques).
class SalesChart extends StatelessWidget {
  const SalesChart({super.key, required this.points, this.height = 160});

  final List<SalesPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Padding(padding: EdgeInsets.all(Gaps.md), child: Text('Aucune vente sur la période.'));
    }
    final theme = Theme.of(context);
    final maxRevenue = points.map((point) => point.revenue).fold(0.0, math.max);
    final monthly = points.length > 1 && points[1].period.difference(points[0].period).inDays > 27;
    final labelFormat = DateFormat(monthly ? 'MMM' : 'dd/MM', 'fr');
    return SizedBox(
      height: height + 32,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barSpace = constraints.maxWidth / points.length;
          final showEvery = math.max(1, (48 / barSpace).ceil());
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (index, point) in points.indexed)
                Expanded(
                  child: Tooltip(
                    message:
                        '${labelFormat.format(point.period)} : ${Formats.money(point.revenue)} '
                        '(${point.salesCount} vente${point.salesCount > 1 ? 's' : ''})',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: maxRevenue == 0 ? 2 : math.max(2, height * point.revenue / maxRevenue),
                          margin: EdgeInsets.symmetric(horizontal: math.min(6, barSpace * 0.15)),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: index % showEvery == 0
                              ? Padding(
                                  padding: const EdgeInsets.only(top: Gaps.xs),
                                  child: Text(
                                    labelFormat.format(point.period),
                                    style: theme.textTheme.labelSmall,
                                    maxLines: 1,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
