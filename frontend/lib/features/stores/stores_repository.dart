import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';
import '../users/user_models.dart';
import 'store_models.dart';

class StoresRepository {
  StoresRepository(this._api);

  final ApiClient _api;

  Future<Paged<Store>> list(PageQuery query) async =>
      Paged.fromJson(await _api.get('/stores', query: query.toQuery()) as Json, Store.fromJson);

  Future<List<Store>>? _activeCache;

  /// Tous les magasins actifs (pour les listes de choix), gardés en mémoire jusqu'à une modification.
  /// Le Stock Local arrive en premier.
  Future<List<Store>> active({bool refresh = false}) {
    if (refresh) _activeCache = null;
    return _activeCache ??= _loadActive()
      ..catchError((Object _) {
        _activeCache = null;
        return const <Store>[];
      });
  }

  Future<List<Store>> _loadActive() async {
    final page = await list(const PageQuery(pageSize: PageQuery.maxPageSize, filters: {'is_active': true}));
    return [...page.items.where((store) => store.isCentral), ...page.items.where((store) => !store.isCentral)];
  }

  void invalidate() => _activeCache = null;

  Future<Store> get(int id) async => Store.fromJson(await _api.get('/stores/$id') as Json);

  Future<Paged<AppUser>> employees(int storeId, PageQuery query) async =>
      Paged.fromJson(await _api.get('/stores/$storeId/employees', query: query.toQuery()) as Json, AppUser.fromJson);

  Future<Store> create({required String name, String? address, String? phone}) async {
    final store = Store.fromJson(
      await _api.post('/stores', data: {'name': name, 'address': address, 'phone': phone}) as Json,
    );
    invalidate();
    return store;
  }

  Future<Store> update(int id, Map<String, Object?> changes) async {
    final store = Store.fromJson(await _api.patch('/stores/$id', data: changes) as Json);
    invalidate();
    return store;
  }

  Future<void> deactivate(int id) async {
    await _api.delete('/stores/$id');
    invalidate();
  }
}
