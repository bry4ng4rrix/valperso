import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/core/storage/key_value_store.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

void main() {
  setUpAll(initFrenchDates);

  testWidgets('sans session : écran de connexion, puis connexion réussie vers l\'accueil vendeur', (tester) async {
    setScreenSize(tester, mobileSize);
    final api = FakeApi();
    final vendeur = meJson(admin: false, id: 2, store: storeJson(id: 2, name: 'h109', central: false));
    api.on('POST', '/auth/login', (_) => tokensJson);
    api.on('GET', '/auth/me', (_) => vendeur);
    api.on('GET', '/sales/history', (_) => page([saleJson()]));
    api.on('GET', '/stock/low-stock', (_) => page([]));
    final dependencies = await pumpApp(tester, api);

    expect(find.text('Connectez-vous pour continuer'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'vendeur1@local.mg');
    await tester.enterText(find.byType(TextFormField).at(1), 'testest');
    await tester.tap(find.text('Se connecter'));
    await settle(tester);

    final login = api.calls('POST', '/auth/login').single;
    expect(login.data, {'username': 'vendeur1@local.mg', 'password': 'testest'});
    expect(find.text('Bonjour Jean Rakoto'), findsOneWidget);
    expect(find.text('Magasin : H109'), findsOneWidget);
    // Le mot de passe n'est jamais enregistré ; seuls les jetons le sont.
    final stored = (dependencies.storage as MemoryKeyValueStore).values;
    expect(stored[StorageKeys.accessToken], 'access-1');
    expect(stored.values, isNot(contains('testest')));
  });

  testWidgets('identifiants incorrects : message en français, pas de navigation', (tester) async {
    setScreenSize(tester, mobileSize);
    final api = FakeApi();
    api.onError('POST', '/auth/login', status: 401, code: 'INVALID_CREDENTIALS', detail: 'Identifiants invalides');
    await pumpApp(tester, api);
    await tester.enterText(find.byType(TextFormField).at(0), 'x');
    await tester.enterText(find.byType(TextFormField).at(1), 'mauvais');
    await tester.tap(find.text('Se connecter'));
    await settle(tester);
    expect(find.text('Identifiants invalides'), findsOneWidget);
    expect(find.text('Connectez-vous pour continuer'), findsOneWidget);
  });

  testWidgets('champs obligatoires vérifiés avant l\'envoi', (tester) async {
    setScreenSize(tester, mobileSize);
    final api = FakeApi();
    await pumpApp(tester, api);
    await tester.tap(find.text('Se connecter'));
    await settle(tester);
    expect(find.text('Champ obligatoire.'), findsNWidgets(2));
    expect(api.calls('POST', '/auth/login'), isEmpty);
  });

  testWidgets('mobile : barre de navigation du bas filtrée par permissions, page Plus', (tester) async {
    setScreenSize(tester, mobileSize);
    final api = FakeApi();
    api.on('GET', '/sales/history', (_) => page([]));
    api.on('GET', '/stock/low-stock', (_) => page([]));
    await pumpApp(
      tester,
      api,
      loggedIn: meJson(admin: false, id: 2, store: storeJson(id: 2, name: 'h109', central: false)),
    );

    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    for (final label in ['Accueil', 'Ventes', 'Produits', 'Clients', 'Plus']) {
      expect(find.descendant(of: bar, matching: find.text(label)), findsOneWidget);
    }
    await tester.tap(find.descendant(of: bar, matching: find.text('Plus')));
    await settle(tester);
    expect(find.text('Paiements et dettes'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Utilisateurs'), findsNothing);
    expect(find.text('Magasins'), findsNothing);
    expect(find.text('Se déconnecter'), findsOneWidget);
  });

  testWidgets('bureau : menu latéral complet pour l\'administrateur, tableau de bord', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = FakeApi();
    stubAdminBasics(api);
    await pumpApp(tester, api, loggedIn: meJson(admin: true));

    expect(find.byType(NavigationBar), findsNothing);
    for (final label in ['Utilisateurs', 'Magasins', 'Transferts', 'Caisse', 'Journal d\'audit']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Tableau de bord'), findsOneWidget);
    expect(find.text('Chiffre d\'affaires'), findsOneWidget);
    expect(find.text('15 000 Ar'), findsOneWidget);
    expect(find.text('Actions rapides'), findsOneWidget);
    final summary = api.calls('GET', '/dashboard/summary').single;
    expect(summary.queryParameters.keys, containsAll(['date_from', 'date_to']));
  });

  testWidgets('déconnexion après confirmation', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = FakeApi();
    stubAdminBasics(api);
    final dependencies = await pumpApp(tester, api, loggedIn: meJson(admin: true));

    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(find.text('Se déconnecter ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Tableau de bord'), findsOneWidget);

    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Se déconnecter'));
    await settle(tester);
    expect(find.text('Connectez-vous pour continuer'), findsOneWidget);
    expect(dependencies.api.tokens.hasSession, isFalse);
  });

  testWidgets('session expirée : retour au login avec un message', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = FakeApi();
    stubAdminBasics(api);
    api.onError('GET', '/dashboard/summary', status: 401, code: 'TOKEN_EXPIRED');
    api.onError('POST', '/auth/refresh', status: 401, code: 'TOKEN_REVOKED');
    await pumpApp(tester, api, loggedIn: meJson(admin: true));
    expect(find.text('Votre session a expiré. Reconnectez-vous.'), findsOneWidget);
    expect(find.text('Connectez-vous pour continuer'), findsOneWidget);
  });
}
