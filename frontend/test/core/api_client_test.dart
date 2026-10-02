import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/core/api/api_client.dart';
import 'package:valmag/core/api/api_config.dart';
import 'package:valmag/core/api/api_exception.dart';
import 'package:valmag/core/storage/key_value_store.dart';

import '../support/fake_api.dart';

void main() {
  late FakeApi api;
  late MemoryKeyValueStore storage;
  late ApiClient client;

  setUp(() async {
    api = FakeApi();
    storage = MemoryKeyValueStore({StorageKeys.accessToken: 'old-access', StorageKeys.refreshToken: 'refresh-1'});
    client = ApiClient(baseUrl: 'http://test.local', tokens: TokenStore(storage), adapter: api);
    await client.tokens.load();
  });

  test('ajoute le jeton à chaque requête et le préfixe /api/v1', () async {
    api.on('GET', '/products', (_) => {'items': []});
    await client.get('/products', query: {'search': 'stylo', 'category_id': null});
    final request = api.requests.single;
    expect(request.uri.toString(), 'http://test.local/api/v1/products?search=stylo');
    expect(request.headers['Authorization'], 'Bearer old-access');
  });

  test('401 : renouvelle les jetons puis rejoue la requête une seule fois', () async {
    api.on(
      'GET',
      '/products',
      (request) => request.headers['Authorization'] == 'Bearer new-access'
          ? {'auth': request.headers['Authorization']}
          : const FakeResponse(401, {'detail': 'Jeton expiré', 'code': 'TOKEN_EXPIRED'}),
    );
    api.on('POST', '/auth/refresh', (request) {
      expect((request.data as Map)['refresh_token'], 'refresh-1');
      return {'access_token': 'new-access', 'refresh_token': 'refresh-2', 'token_type': 'bearer', 'expires_in': 900};
    });

    final data = await client.get('/products') as Map;
    expect(data['auth'], 'Bearer new-access');
    expect(await storage.read(StorageKeys.accessToken), 'new-access');
    expect(await storage.read(StorageKeys.refreshToken), 'refresh-2');
    expect(api.calls('POST', '/auth/refresh'), hasLength(1));
    expect(api.calls('GET', '/products'), hasLength(2));
  });

  test('renouvellement impossible : session effacée et retour au login', () async {
    api.onError('GET', '/sales/history', status: 401, code: 'TOKEN_EXPIRED');
    api.onError('POST', '/auth/refresh', status: 401, code: 'TOKEN_REVOKED');
    var expired = false;
    client.onSessionExpired = () => expired = true;

    await expectLater(client.get('/sales/history'), throwsA(isA<ApiException>()));
    expect(expired, isTrue);
    expect(client.tokens.hasSession, isFalse);
    expect(await storage.read(StorageKeys.refreshToken), isNull);
  });

  test('erreur métier convertie en ApiException avec le message du backend', () async {
    api.onError('POST', '/sales', status: 400, code: 'INSUFFICIENT_STOCK', detail: 'Stock insuffisant dans H109');
    await expectLater(
      client.post('/sales', data: const {}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'INSUFFICIENT_STOCK')
            .having((error) => error.message, 'message', 'Stock insuffisant dans H109'),
      ),
    );
  });

  test('connexion : pas de jeton envoyé', () async {
    api.on('POST', '/auth/login', (_) => {'ok': true});
    await client.post('/auth/login', data: const {'username': 'a', 'password': 'b'}, authenticated: false);
    expect(api.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('changement d\'adresse du serveur', () async {
    client.updateBaseUrl('192.168.1.10:8001/api/v1/');
    expect(client.baseUrl, 'http://192.168.1.10:8001');
    expect(ApiConfig.normalize('https://api.exemple.mg/'), 'https://api.exemple.mg');
  });
}
