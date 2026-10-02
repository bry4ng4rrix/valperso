import 'package:intl/intl.dart';

/// Mise en forme des montants, quantités et dates (format malgache / français).
abstract final class Formats {
  static final _amount = NumberFormat('#,##0.##', 'fr');
  static final _integer = NumberFormat('#,##0', 'fr');
  static final _date = DateFormat('dd/MM/yyyy', 'fr');
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'fr');
  static final _time = DateFormat('HH:mm', 'fr');
  static final _shortDate = DateFormat('d MMM yyyy', 'fr');

  /// 45000 -> "45 000 Ar". Espace insécable classique (compatible PDF et Excel).
  static String money(num? value) => value == null ? '—' : '${_clean(_amount.format(value))} Ar';

  /// Montant sans l'unité, pour les champs de saisie et les tableaux.
  static String amount(num? value) => value == null ? '' : _clean(_amount.format(value));

  static String quantity(num? value) => value == null ? '—' : _clean(_integer.format(value));

  static String date(DateTime? value) => value == null ? '—' : _date.format(value.toLocal());

  static String shortDate(DateTime? value) => value == null ? '—' : _shortDate.format(value.toLocal());

  static String dateTime(DateTime? value) => value == null ? '—' : _dateTime.format(value.toLocal());

  static String time(DateTime? value) => value == null ? '—' : _time.format(value.toLocal());

  /// Date au format attendu par l'API (AAAA-MM-JJ), par exemple pour une échéance.
  static String apiDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  /// Met une majuscule au début : l'API renvoie les textes en minuscules.
  static String capitalize(String? value) {
    if (value == null || value.isEmpty) return value ?? '';
    return value[0].toUpperCase() + value.substring(1);
  }

  /// Le format français utilise l'espace fine insécable (U+202F), absente des polices PDF standard.
  static String _clean(String value) => value.replaceAll(' ', ' ');
}

/// Lecture tolérante d'un montant saisi par l'utilisateur ("45 000", "45000,50").
double? parseAmount(String? input) {
  if (input == null) return null;
  final normalized = input.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}
