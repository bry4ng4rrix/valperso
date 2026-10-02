import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';
import 'user_models.dart';

class UsersRepository {
  UsersRepository(this._api);

  final ApiClient _api;

  Future<Paged<AppUser>> list(PageQuery query) async =>
      Paged.fromJson(await _api.get('/users', query: query.toQuery()) as Json, AppUser.fromJson);

  Future<AppUser> get(int id) async => AppUser.fromJson(await _api.get('/users/$id') as Json);

  Future<AppUser> create(Map<String, Object?> data) async =>
      AppUser.fromJson(await _api.post('/users', data: data) as Json);

  /// Remplace les informations (nom, prénom, username, email, téléphone, mot de passe facultatif).
  Future<AppUser> update(int id, Map<String, Object?> data) async =>
      AppUser.fromJson(await _api.put('/users/$id', data: data) as Json);

  Future<AppUser> changeRole(int id, String role) async =>
      AppUser.fromJson(await _api.put('/users/$id/role', data: {'role': role}) as Json);

  /// [storeId] null = retirer l'affectation.
  Future<AppUser> changeStore(int id, int? storeId) async =>
      AppUser.fromJson(await _api.put('/users/$id/store', data: {'store_id': storeId}) as Json);

  Future<AppUser> changeStatus(int id, {required bool isActive}) async =>
      AppUser.fromJson(await _api.put('/users/$id/status', data: {'is_active': isActive}) as Json);
}
