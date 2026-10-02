import '../api/api_client.dart';
import '../utils/json.dart';
import 'current_user.dart';

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Connexion avec le nom d'utilisateur ou l'email. Les jetons sont enregistrés de façon sécurisée.
  Future<void> login(String identifier, String password) async {
    final data = await _api.post(
      '/auth/login',
      data: {'username': identifier.trim(), 'password': password},
      authenticated: false,
    ) as Json;
    await _api.tokens.save(access: '${data['access_token']}', refresh: '${data['refresh_token']}');
  }

  Future<CurrentUser> me() async => CurrentUser.fromJson(await _api.get('/auth/me') as Json);

  Future<void> logout() => _api.tokens.clear();
}
