import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';

class Category {
  const Category({required this.id, required this.name, required this.isActive, this.description});

  factory Category.fromJson(Json json) => Category(
    id: toInt(json['id']),
    name: '${json['name']}',
    description: toStringOrNull(json['description']),
    isActive: json['is_active'] != false,
  );

  final int id;
  final String name;
  final String? description;
  final bool isActive;

  String get label => Formats.capitalize(name);
}

class CategoriesRepository {
  CategoriesRepository(this._api);

  final ApiClient _api;

  Future<Paged<Category>> list(PageQuery query) async =>
      Paged.fromJson(await _api.get('/categories', query: query.toQuery()) as Json, Category.fromJson);

  Future<List<Category>>? _activeCache;

  /// Catégories actives, pour les listes de choix (gardées en mémoire jusqu'à une modification).
  Future<List<Category>> active({bool refresh = false}) {
    if (refresh) _activeCache = null;
    return _activeCache ??= _loadActive()
      ..catchError((Object _) {
        _activeCache = null;
        return const <Category>[];
      });
  }

  Future<List<Category>> _loadActive() async => (await list(
    const PageQuery(pageSize: PageQuery.maxPageSize, filters: {'is_active': true, 'sort': 'name'}),
  )).items;

  void invalidate() => _activeCache = null;

  Future<Category> create({required String name}) async {
    final category = Category.fromJson(await _api.post('/categories', data: {'name': name}) as Json);
    invalidate();
    return category;
  }

  Future<Category> update(int id, Map<String, Object?> changes) async {
    final category = Category.fromJson(await _api.patch('/categories/$id', data: changes) as Json);
    invalidate();
    return category;
  }

  Future<void> deactivate(int id) async {
    await _api.delete('/categories/$id');
    invalidate();
  }
}
