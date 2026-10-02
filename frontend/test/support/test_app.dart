import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:valmag/app/app.dart';
import 'package:valmag/app/dependencies.dart';
import 'package:valmag/core/storage/key_value_store.dart';

import 'fake_api.dart';
import 'fixtures.dart';

Future<void> initFrenchDates() async {
  Intl.defaultLocale = 'fr';
  await initializeDateFormatting('fr');
}

/// Taille d'écran des tests (mobile, tablette, bureau).
void setScreenSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const mobileSize = Size(400, 860);
const desktopSize = Size(1440, 1000);

/// Lance l'application complète avec un faux serveur.
/// Si [loggedIn] est fourni, une session existe déjà (jetons enregistrés et /auth/me simulé).
/// [light] : thème clair (le thème sombre est celui par défaut).
Future<AppDependencies> pumpApp(
  WidgetTester tester,
  FakeApi api, {
  Map<String, Object?>? loggedIn,
  bool light = false,
}) async {
  final storage = MemoryKeyValueStore({
    if (loggedIn != null) StorageKeys.accessToken: 'access-0',
    if (loggedIn != null) StorageKeys.refreshToken: 'refresh-0',
    if (light) StorageKeys.themeMode: 'light',
  });
  if (loggedIn != null) api.on('GET', '/auth/me', (_) => loggedIn);
  final dependencies = AppDependencies(storage: storage, baseUrl: 'http://test.local', adapter: api);
  await tester.runAsync(dependencies.start);
  await tester.pumpWidget(CommerceApp(dependencies: dependencies));
  await settle(tester);
  return dependencies;
}

/// Laisse passer les réponses du faux serveur et les animations.
Future<void> settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Routes communes d'un administrateur (accueil et listes de base).
void stubAdminBasics(FakeApi api) {
  api.on('GET', '/stores', (_) => page([storeJson(), storeJson(id: 2, name: 'h109', central: false)]));
  api.on('GET', '/dashboard/summary', (_) => dashboardJson());
  api.on('GET', '/dashboard/sales', (_) => <Object>[]);
  api.on('GET', '/dashboard/low-stock', (_) => page([stockLineJson(quantity: 2)]));
  api.on(
    'GET',
    '/categories',
    (_) => page([
      {'id': 1, 'name': 'papeterie', 'description': null, 'is_active': true},
    ]),
  );
}
