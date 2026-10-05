import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:valmag/core/widgets/app_dialog.dart';
import 'package:valmag/features/company/company_screen.dart';

import '../support/demo_data.dart';
import '../support/fake_api.dart';
import '../support/test_app.dart';

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(32, 0)]);

Future<FakeApi> _open(WidgetTester tester, String route) async {
  setScreenSize(tester, desktopSize);
  final api = FakeApi();
  stubDemoApi(api);
  await pumpApp(tester, api, loggedIn: demoMe());
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
  await settle(tester);
  return api;
}

void main() {
  setUpAll(initFrenchDates);

  testWidgets('utilisateurs : bouton Supprimer (pas pour soi-même), confirmation puis suppression', (tester) async {
    final api = await _open(tester, '/users');
    api.on('DELETE', '/users/4', (_) => null, status: 204);

    // Valencia (moi) : pas de bouton ; Antsa et Fleur : Supprimer ; Sitraka (désactivé) : Réactiver.
    expect(find.byTooltip('Supprimer'), findsNWidgets(2));
    expect(find.byTooltip('Réactiver'), findsOneWidget);

    final loads = api.calls('GET', '/users').length;
    await tester.tap(find.byTooltip('Supprimer').last); // Fleur
    await tester.pumpAndSettle();
    expect(find.text('Supprimer Fleur Rasoanaivo ?'), findsOneWidget);
    expect(api.calls('DELETE', '/users/4'), isEmpty, reason: 'rien avant la confirmation');

    await tester.tap(find.descendant(of: find.byType(AppDialog), matching: find.text('Supprimer')));
    await settle(tester);
    expect(api.calls('DELETE', '/users/4'), hasLength(1));
    expect(find.text('Utilisateur supprimé.'), findsOneWidget);
    expect(api.calls('GET', '/users').length, greaterThan(loads), reason: 'liste rechargée');
  });

  testWidgets('paramètres : section Société, Modifier ouvre directement le formulaire', (tester) async {
    await _open(tester, '/settings');

    expect(find.text('Société'), findsOneWidget);
    expect(find.text('Valheri Wear'), findsWidgets);
    await tester.tap(find.descendant(of: find.byType(Card), matching: find.text('Modifier')).last);
    await settle(tester);

    expect(find.text('Logo (factures et tickets)'), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget);
  });

  testWidgets('société : le logo choisi est envoyé au serveur et affiché', (tester) async {
    final realPicker = pickCompanyLogo;
    pickCompanyLogo = () async => XFile.fromData(_png, name: 'logo.png', mimeType: 'image/png');
    addTearDown(() => pickCompanyLogo = realPicker);
    final api = await _open(tester, '/settings/company?edit=1');
    api.on(
      'POST',
      '/company/logo',
      (_) => {
        'id': 1,
        'name': 'valheri wear',
        'logo_url': '/media/company/abc.png',
        'phone': null,
        'email': null,
        'address': null,
        'city': null,
      },
    );

    await tester.tap(find.text('Choisir une image'));
    await settle(tester);

    expect(api.calls('POST', '/company/logo'), hasLength(1));
    expect(find.text('Logo enregistré.'), findsOneWidget);
    expect(find.text('Changer le logo'), findsOneWidget);
    expect(find.text('Retirer'), findsOneWidget);
  });
}
