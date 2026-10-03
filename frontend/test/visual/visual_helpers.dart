import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:valmag/shared/widgets/states.dart';

import '../support/demo_data.dart';
import '../support/fake_api.dart';
import '../support/test_app.dart';

/// Outils communs des tests visuels (captures de référence dans test/visual/goldens).
///
/// Après une modification volontaire de l'interface, regénérer les captures puis les relire :
///   flutter test test/visual --update-goldens

const phone = Size(390, 844);
const desktop = Size(1440, 900);

/// Téléphone, page entière : pour relire le contenu situé sous l'écran (pas une taille réelle).
const phoneLong = Size(390, 2200);

String folder(Size size, {bool light = false, bool seller = false}) =>
    '${size == desktop ? 'ordinateur' : (size == phone ? 'telephone' : 'telephone_page_entiere')}/${seller ? 'vendeur' : (light ? 'clair' : 'sombre')}';

/// Ouvre l'application connectée sur la route demandée.
Future<FakeApi> openScreen(
  WidgetTester tester,
  String route, {
  required Size size,
  bool light = false,
  bool seller = false,
}) async {
  setScreenSize(tester, size);
  final api = FakeApi();
  stubDemoApi(api);
  await pumpApp(
    tester,
    api,
    loggedIn: demoMe(admin: !seller),
    light: light,
  );
  if (route != '/') {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
    await settle(tester);
  }
  return api;
}

/// Compare l'écran à sa capture de référence, après avoir vérifié qu'il s'affiche sans erreur.
/// [unmount] : démonter l'application après la capture (sauf si le test continue ensuite).
Future<void> expectScreen(WidgetTester tester, FakeApi api, String path, {bool unmount = true}) async {
  expect(tester.takeException(), isNull, reason: path);
  expect(find.byType(ErrorState), findsNothing, reason: '$path : erreur de chargement');
  expect(api.unmatched, isEmpty, reason: '$path : routes non simulées');
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$path.png'));
  if (!unmount) return;
  // Démonte l'application et laisse finir les minuteurs (recherche différée, infobulles...).
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}
