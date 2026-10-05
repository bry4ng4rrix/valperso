import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:valmag/core/realtime/realtime_notices.dart';
import 'package:valmag/core/realtime/realtime_service.dart';

import '../support/demo_data.dart';
import '../support/fake_api.dart';
import '../support/fake_realtime.dart';
import '../support/test_app.dart';

/// Laisse le faux WebSocket livrer ses messages et les minuteries de reconnexion s'écouler :
/// ils tournent sur la vraie boucle asynchrone, pas sur l'horloge simulée du test.
Future<void> deliver(WidgetTester tester, [Duration wait = const Duration(milliseconds: 20)]) async {
  await tester.runAsync(() => Future<void>.delayed(wait));
  await tester.pump();
}

const _retry = Duration(milliseconds: 1100);

void main() {
  setUpAll(initFrenchDates);

  test('adresse du WebSocket : http -> ws, https -> wss, jeton en paramètre', () {
    expect(realtimeUri('http://185.215.167.79:8020', 'abc').toString(), 'ws://185.215.167.79:8020/api/v1/ws?token=abc');
    expect(realtimeUri('https://api.exemple.mg', 'abc').toString(), 'wss://api.exemple.mg/api/v1/ws?token=abc');
  });

  test('avis affichés pour les actions des autres utilisateurs', () {
    RealtimeChange change(String entity, String action, [String? label]) =>
        RealtimeChange(entity: entity, action: action, id: 1, actorId: 2, label: label);
    expect(noticeFor(change('sale', 'created', 'FAC-2026-000012')), 'Nouvelle vente FAC-2026-000012');
    expect(noticeFor(change('product', 'created', 'ROBE ROUGE')), 'Nouveau produit : Robe rouge');
    expect(noticeFor(change('product', 'deleted', 'ROBE ROUGE')), 'Produit supprimé : Robe rouge');
    expect(noticeFor(change('stock', 'updated')), isNull);
  });

  testWidgets('connexion avec la session, changements reçus, reconnexion puis resynchronisation', (tester) async {
    final realtime = FakeRealtime();
    final api = FakeApi();
    stubDemoApi(api);
    final dependencies = await pumpApp(tester, api, loggedIn: demoMe(), realtime: realtime);
    final service = dependencies.realtime;
    final received = <RealtimeChange>[];
    service.changes.listen(received.add);

    expect(realtime.connections.single.toString(), 'ws://test.local/api/v1/ws?token=access-0');
    realtime.ready();
    await deliver(tester);
    expect(service.isConnected, isTrue);

    realtime.announce([
      {'entity': 'sale', 'action': 'created', 'id': 5, 'actor_id': 2, 'label': 'FAC-2026-000005'},
    ]);
    await deliver(tester);
    expect(received.single.entity, 'sale');
    expect(received.single.id, 5);

    // Coupure : nouvelle tentative après 1 s, puis rechargement de tous les écrans.
    realtime.drop();
    await deliver(tester);
    expect(service.isConnected, isFalse);
    await deliver(tester, _retry);
    expect(realtime.connections, hasLength(2));
    realtime.ready();
    await deliver(tester);
    expect(received.last.isResync, isTrue);

    // Déconnexion : plus de WebSocket, plus de tentative.
    await dependencies.session.logout();
    await deliver(tester, _retry);
    expect(service.isConnected, isFalse);
    expect(realtime.connections, hasLength(2));
    await settle(tester);
  });

  testWidgets('jeton refusé (4401) : profil relu (jeton renouvelé) puis reconnexion', (tester) async {
    final realtime = FakeRealtime();
    final api = FakeApi();
    stubDemoApi(api);
    await pumpApp(tester, api, loggedIn: demoMe(), realtime: realtime);
    final profileReads = api.calls('GET', '/auth/me').length;

    realtime.drop(RealtimeService.closeUnauthorized);
    await settle(tester);
    await deliver(tester, _retry);

    expect(api.calls('GET', '/auth/me').length, profileReads + 1);
    expect(realtime.connections, hasLength(2));
  });

  testWidgets('une liste se recharge seule quand le serveur annonce un changement', (tester) async {
    setScreenSize(tester, desktopSize);
    final realtime = FakeRealtime();
    final api = FakeApi();
    stubDemoApi(api);
    await pumpApp(tester, api, loggedIn: demoMe(), realtime: realtime);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/categories');
    await settle(tester);
    realtime.ready();
    await deliver(tester);
    final loads = api.calls('GET', '/categories').length;

    // Changement sans rapport : rien n'est rechargé.
    realtime.announce([
      {'entity': 'transfer', 'action': 'created', 'id': 1, 'actor_id': 9},
    ]);
    await deliver(tester);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(api.calls('GET', '/categories'), hasLength(loads));

    // Plusieurs changements rapprochés : un seul rechargement, sans écran de chargement.
    for (var id = 1; id <= 3; id++) {
      realtime.announce([
        {'entity': 'category', 'action': 'created', 'id': id, 'actor_id': 9},
      ]);
    }
    await deliver(tester);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(api.calls('GET', '/categories'), hasLength(loads + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('une vente faite par un collègue est signalée', (tester) async {
    setScreenSize(tester, desktopSize);
    final realtime = FakeRealtime();
    final api = FakeApi();
    stubDemoApi(api);
    await pumpApp(tester, api, loggedIn: demoMe(), realtime: realtime);
    realtime.ready();
    await deliver(tester);

    realtime.announce([
      {'entity': 'sale', 'action': 'created', 'id': 7, 'actor_id': 999, 'label': 'FAC-2026-000007'},
    ]);
    await deliver(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nouvelle vente FAC-2026-000007'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
  });
}
