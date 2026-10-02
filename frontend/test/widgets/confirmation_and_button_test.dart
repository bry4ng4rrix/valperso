import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/app/theme/theme.dart';
import 'package:valmag/core/widgets/app_dialog.dart';
import 'package:valmag/core/widgets/confirmation_dialog.dart';
import 'package:valmag/shared/widgets/app_button.dart';

/// Monte un bouton qui ouvre une boîte de dialogue et mémorise le résultat.
Future<void> _pumpLauncher(
  WidgetTester tester,
  Future<Object?> Function(BuildContext context) open,
  void Function(Object?) onResult,
) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) =>
              TextButton(onPressed: () async => onResult(await open(context)), child: const Text('ouvrir')),
        ),
      ),
    ),
  );
}

void main() {
  group('ConfirmationDialog', () {
    testWidgets('Confirmer renvoie true, avec la liste avant → après', (tester) async {
      Object? result;
      await _pumpLauncher(
        tester,
        (context) => showConfirmation(
          context,
          title: 'Changer le rôle ?',
          changes: const [FieldChange('Rôle', 'VENDEUR', 'ADMIN')],
          confirmLabel: 'Changer',
          type: ConfirmationType.warning,
        ),
        (value) => result = value,
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Changer le rôle ?'), findsOneWidget);
      expect(find.text('VENDEUR'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
      await tester.tap(find.text('Changer'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('Annuler (ou fermer) renvoie false', (tester) async {
      Object? result;
      await _pumpLauncher(
        tester,
        (context) => showConfirmation(context, title: 'Supprimer ?', type: ConfirmationType.danger),
        (value) => result = value,
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('double confirmation pour une action sensible', (tester) async {
      Object? result;
      await _pumpLauncher(
        tester,
        (context) => showConfirmation(context, title: 'Action sensible', confirmLabel: 'Oui', doubleCheck: true),
        (value) => result = value,
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oui'));
      await tester.pumpAndSettle();
      expect(find.text('Êtes-vous vraiment sûr ?'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text('Oui'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('motif obligatoire (3 caractères minimum)', (tester) async {
      Object? result = 'pas encore';
      await _pumpLauncher(
        tester,
        (context) => showReasonConfirmation(
          context,
          title: 'Annuler la vente ?',
          message: 'Action définitive.',
          fieldLabel: 'Motif',
          confirmLabel: 'Annuler la vente',
        ),
        (value) => result = value,
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'ab');
      await tester.tap(find.text('Annuler la vente').last);
      await tester.pumpAndSettle();
      expect(result, 'pas encore', reason: 'motif trop court : la boîte reste ouverte');
      await tester.enterText(find.byType(TextFormField), 'Erreur de saisie');
      await tester.tap(find.text('Annuler la vente').last);
      await tester.pumpAndSettle();
      expect(result, 'Erreur de saisie');
    });
  });

  group('Largeur adaptée à l\'écran', () {
    Future<double> dialogWidthOn(WidgetTester tester, Size screen, {Widget? content}) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpLauncher(
        tester,
        (context) => showConfirmation(context, title: 'Valider la vente ?', content: content),
        (_) {},
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(AppDialog.panelKey)).width;
    }

    testWidgets('mobile : toute la largeur moins une petite marge', (tester) async {
      expect(await dialogWidthOn(tester, const Size(360, 740)), 360 - 24);
      expect(find.byType(Expanded), findsWidgets, reason: 'boutons sur toute la largeur');
    });

    testWidgets('mobile large : suit la largeur de l\'écran', (tester) async {
      expect(await dialogWidthOn(tester, const Size(430, 900)), 430 - 24);
    });

    testWidgets('tablette : largeur fixe (pas une boîte étroite)', (tester) async {
      expect(await dialogWidthOn(tester, const Size(800, 1000)), DialogSize.medium.width);
    });

    testWidgets('ordinateur : plus large avec un récapitulatif (vente)', (tester) async {
      expect(
        await dialogWidthOn(tester, const Size(1440, 1000), content: const Text('récapitulatif')),
        DialogSize.large.width,
      );
    });

    testWidgets('contenu long : défile, les boutons restent visibles', (tester) async {
      await dialogWidthOn(
        tester,
        const Size(360, 640),
        content: Column(children: [for (var i = 0; i < 40; i++) Text('ligne $i')]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Confirmer').hitTestable(), findsOneWidget);
      expect(find.text('Annuler').hitTestable(), findsOneWidget);
    });
  });

  group('AppButton', () {
    testWidgets('bloque le double envoi pendant l\'appel et affiche un indicateur', (tester) async {
      var calls = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Valider',
              loadingLabel: 'Enregistrement...',
              onPressed: () {
                calls++;
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Valider'));
      await tester.pump();
      expect(find.text('Enregistrement...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Enregistrement...'));
      await tester.tap(find.text('Enregistrement...'));
      await tester.pump();
      expect(calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Valider'), findsOneWidget);
      await tester.tap(find.text('Valider'));
      await tester.pump();
      expect(calls, 2);
    });

    testWidgets('désactivé sans action', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppButton(label: 'Valider', onPressed: null)),
        ),
      );
      final button = tester.widget<FilledButton>(find.byWidgetPredicate((widget) => widget is FilledButton));
      expect(button.onPressed, isNull);
    });
  });
}
