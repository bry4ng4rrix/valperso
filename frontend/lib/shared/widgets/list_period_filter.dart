import 'package:flutter/material.dart';

import '../../core/api/paged_controller.dart';
import '../../core/utils/periods.dart';
import 'period_selector.dart';

/// Applique une période (Aujourd'hui, Ce mois...) aux filtres date_from / date_to d'une liste.
/// La période choisie est gardée dans des clés internes (non envoyées à l'API).
Future<void> applyPeriod(PagedController<dynamic> controller, Period period, [DateTimeRange? range]) {
  return controller.updateFilters({'_period': period, '_range': range, ...rangeFor(period, custom: range).toQuery()});
}

/// Filtres de départ d'une liste pour une période donnée.
Map<String, Object?> periodFilters(Period period) => {'_period': period, ...rangeFor(period).toQuery()};

/// Puces de période reliées à une liste paginée.
class ListPeriodFilter extends StatelessWidget {
  const ListPeriodFilter({super.key, required this.controller, this.periods});

  final PagedController<dynamic> controller;
  final List<Period>? periods;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PeriodSelector(
        period: controller.filter('_period') as Period? ?? Period.all,
        customRange: controller.filter('_range') as DateTimeRange?,
        periods:
            periods ??
            const [
              Period.all,
              Period.today,
              Period.yesterday,
              Period.thisWeek,
              Period.thisMonth,
              Period.thisYear,
              Period.custom,
            ],
        onChanged: (period, range) => applyPeriod(controller, period, range),
      ),
    );
  }
}
