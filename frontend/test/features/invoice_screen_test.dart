import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:valmag/features/invoices/invoice_actions.dart';

import '../support/demo_data.dart';
import '../support/fake_api.dart';
import '../support/test_app.dart';

void main() {
  setUpAll(initFrenchDates);

  testWidgets('facture : « Imprimer » ouvre l\'impression avec le PDF de la facture', (tester) async {
    setScreenSize(tester, mobileSize);
    final api = FakeApi();
    stubDemoApi(api);
    await pumpApp(tester, api, loggedIn: demoMe());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/sales/500/invoice');
    await settle(tester);

    final original = printPdf;
    addTearDown(() => printPdf = original);
    Uint8List? printed;
    String? fileName;
    printPdf = (pdf, name) async {
      printed = pdf;
      fileName = name;
      return true;
    };

    expect(find.text('Imprimer'), findsOneWidget);
    expect(find.text('Partager en PDF'), findsOneWidget, reason: 'Android : menu de partage');
    await tester.tap(find.text('Imprimer'));
    await settle(tester);

    expect(printed, isNotNull);
    expect(String.fromCharCodes(printed!.sublist(0, 5)), '%PDF-');
    expect(fileName, 'facture_FAC-2026-000500.pdf');
  });
}
