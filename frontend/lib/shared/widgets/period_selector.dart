import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/periods.dart';

/// Choix de période par puces : [Aujourd'hui] [Cette semaine] [Ce mois] ...
/// « Personnalisé » ouvre un sélecteur de dates (second niveau).
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.period,
    required this.onChanged,
    this.customRange,
    this.periods = const [Period.all, Period.today, Period.yesterday, Period.thisWeek, Period.thisMonth, Period.custom],
  });

  final Period period;
  final DateTimeRange? customRange;
  final List<Period> periods;

  /// Reçoit la période choisie et, pour « Personnalisé », l'intervalle sélectionné.
  final void Function(Period period, DateTimeRange? range) onChanged;

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: customRange,
      helpText: 'Choisir une période',
      saveText: 'Valider',
    );
    if (range != null) onChanged(Period.custom, range);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in periods)
            Padding(
              padding: const EdgeInsets.only(right: Gaps.sm),
              child: ChoiceChip(
                label: Text(
                  item == Period.custom && period == Period.custom && customRange != null
                      ? '${Formats.date(customRange!.start)} → ${Formats.date(customRange!.end)}'
                      : item.label,
                ),
                avatar: item == Period.custom ? const Icon(Icons.date_range, size: 18) : null,
                selected: item == period,
                onSelected: (_) => item == Period.custom ? _pickCustom(context) : onChanged(item, null),
              ),
            ),
        ],
      ),
    );
  }
}
