import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/core/utils/formatters.dart';
import 'package:valmag/core/utils/periods.dart';
import 'package:valmag/shared/utils/validators.dart';

import '../support/test_app.dart';

void main() {
  setUpAll(initFrenchDates);

  group('Formats', () {
    test('montants en Ariary avec espace insécable classique (compatible PDF)', () {
      final text = Formats.money(45000);
      expect(text, '45 000 Ar');
      expect(text.contains(' '), isFalse);
      expect(Formats.money(1234.5), '1 234,5 Ar');
      expect(Formats.money(null), '—');
    });

    test('lecture des montants saisis', () {
      expect(parseAmount('45 000'), 45000);
      expect(parseAmount('45 000,50'), 45000.5);
      expect(parseAmount(Formats.amount(12500)), 12500);
      expect(parseAmount(''), isNull);
      expect(parseAmount('abc'), isNull);
    });

    test('majuscules à l\'affichage (les textes arrivent en minuscules)', () {
      expect(Formats.capitalize('stylo bleu'), 'Stylo bleu');
      expect(Formats.title('la city behoririka'), 'La City Behoririka');
      expect(Formats.capitalize(null), '');
      expect(Formats.text('paiement fac-2026-000001'), 'Paiement FAC-2026-000001');
      expect(Formats.text('annulation trf-2026-000012'), 'Annulation TRF-2026-000012');
    });

    test('dates', () {
      expect(Formats.date(DateTime(2026, 10, 2)), '02/10/2026');
      expect(Formats.apiDate(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('Périodes', () {
    final now = DateTime(2026, 10, 2, 15, 30); // vendredi

    test('Aujourd\'hui et Hier', () {
      final today = rangeFor(Period.today, now: now);
      expect(today.start, DateTime(2026, 10, 2));
      expect(today.end, DateTime(2026, 10, 3));
      final yesterday = rangeFor(Period.yesterday, now: now);
      expect(yesterday.start, DateTime(2026, 10, 1));
      expect(yesterday.end, DateTime(2026, 10, 2));
    });

    test('Cette semaine commence le lundi', () {
      final week = rangeFor(Period.thisWeek, now: now);
      expect(week.start, DateTime(2026, 9, 28));
      expect(week.end, DateTime(2026, 10, 5));
    });

    test('Ce mois, cette année, tout', () {
      expect(rangeFor(Period.thisMonth, now: now).start, DateTime(2026, 10));
      expect(rangeFor(Period.thisMonth, now: now).end, DateTime(2026, 11));
      expect(rangeFor(Period.thisYear, now: now).end, DateTime(2027));
      final all = rangeFor(Period.all, now: now);
      expect(all.start, isNull);
      expect(all.toQuery(), {'date_from': null, 'date_to': null});
    });

    test('Personnalisé : le dernier jour est inclus', () {
      final range = rangeFor(
        Period.custom,
        now: now,
        custom: DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 15)),
      );
      expect(range.start, DateTime(2026, 9, 1));
      expect(range.end, DateTime(2026, 9, 16));
      expect(range.toQuery()['date_from'], DateTime(2026, 9, 1).toUtc().toIso8601String());
    });
  });

  group('Validators (mêmes règles que l\'API)', () {
    test('téléphone', () {
      expect(Validators.phone('034 12 345 67'), isNull);
      expect(Validators.phone('+261 34 12 345 67'), isNull);
      expect(Validators.phone('abc'), isNotNull);
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('', required: true), isNotNull);
    });

    test('référence, identifiant, mot de passe, logo', () {
      expect(Validators.reference('P-001'), isNull);
      expect(Validators.reference('P 001'), isNotNull);
      expect(Validators.username('vendeur.1'), isNull);
      expect(Validators.username('ab'), isNotNull);
      expect(Validators.password('1234567'), isNotNull);
      expect(Validators.password('', required: false), isNull);
      expect(Validators.logoUrl('https://exemple.mg/logo.png'), isNull);
      expect(Validators.logoUrl('/media/logo.png'), isNull);
      expect(Validators.logoUrl('logo.png'), isNotNull);
    });
  });
}
