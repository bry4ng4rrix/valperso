import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';
import 'product_models.dart';

class ProductsRepository {
  ProductsRepository(this._api);

  final ApiClient _api;

  Future<Paged<Product>> list(PageQuery query) async =>
      Paged.fromJson(await _api.get('/products', query: query.toQuery()) as Json, Product.fromJson);

  Future<Product> get(int id) async => Product.fromJson(await _api.get('/products/$id') as Json);

  Future<Product> create(Map<String, Object?> data) async =>
      Product.fromJson(await _api.post('/products', data: data) as Json);

  /// Modification partielle : seuls les champs envoyés changent.
  Future<Product> update(int id, Map<String, Object?> changes) async =>
      Product.fromJson(await _api.patch('/products/$id', data: changes) as Json);

  Future<void> deactivate(int id) => _api.delete('/products/$id');
}
