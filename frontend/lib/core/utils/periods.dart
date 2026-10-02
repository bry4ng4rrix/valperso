import 'package:flutter/material.dart';

/// Périodes simples proposées à l'utilisateur à la place de "date de début / date de fin".
enum Period {
  all('Tout'),
  today("Aujourd'hui"),
  yesterday('Hier'),
  thisWeek('Cette semaine'),
  thisMonth('Ce mois'),
  thisYear('Cette année'),
  custom('Personnalisé');

  const Period(this.label);
  final String label;
}

/// Intervalle [start ; end[ en heure locale. `null` = pas de limite.
class PeriodRange {
  const PeriodRange(this.start, this.end);
  final DateTime? start;
  final DateTime? end;

  /// Paramètres `date_from` / `date_to` de l'API (ISO 8601 avec fuseau horaire).
  Map<String, Object?> toQuery() => {
    'date_from': start?.toUtc().toIso8601String(),
    'date_to': end?.toUtc().toIso8601String(),
  };
}

/// Calcule l'intervalle d'une période. Pour [Period.custom], fournir [custom] (jours inclus).
PeriodRange rangeFor(Period period, {DateTime? now, DateTimeRange? custom}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  switch (period) {
    case Period.all:
      return const PeriodRange(null, null);
    case Period.today:
      return PeriodRange(today, today.add(const Duration(days: 1)));
    case Period.yesterday:
      return PeriodRange(today.subtract(const Duration(days: 1)), today);
    case Period.thisWeek:
      final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
      return PeriodRange(monday, monday.add(const Duration(days: 7)));
    case Period.thisMonth:
      return PeriodRange(DateTime(today.year, today.month), DateTime(today.year, today.month + 1));
    case Period.thisYear:
      return PeriodRange(DateTime(today.year), DateTime(today.year + 1));
    case Period.custom:
      if (custom == null) return const PeriodRange(null, null);
      final start = DateTime(custom.start.year, custom.start.month, custom.start.day);
      final lastDay = DateTime(custom.end.year, custom.end.month, custom.end.day);
      return PeriodRange(start, lastDay.add(const Duration(days: 1)));
  }
}
