import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';
import 'stock_models.dart';

/// Type d'opération manuelle sur le stock.
enum StockOperation {
  entry('Entrée de stock'),
  exit('Sortie de stock'),
  loss('Perte'),
  adjust('Ajustement d\'inventaire');

  const StockOperation(this.label);
  final String label;
}

class StockRepository {
  StockRepository(this._api);

  final ApiClient _api;

  Future<Paged<StockLine>> lines(PageQuery query) async =>
      Paged.fromJson(await _api.get('/stock', query: query.toQuery()) as Json, StockLine.fromJson);

  Future<Paged<StockLine>> lowStock(PageQuery query) async =>
      Paged.fromJson(await _api.get('/stock/low-stock', query: query.toQuery()) as Json, StockLine.fromJson);

  Future<Paged<StockLine>> outOfStock(PageQuery query) async =>
      Paged.fromJson(await _api.get('/stock/out-of-stock', query: query.toQuery()) as Json, StockLine.fromJson);

  /// Toutes les lignes de stock d'un produit (un par magasin).
  Future<List<StockLine>> productLines(int productId) async =>
      (await lines(PageQuery(pageSize: PageQuery.maxPageSize, filters: {'product_id': productId}))).items;

  Future<Paged<StockMovement>> movements(PageQuery query) async =>
      Paged.fromJson(await _api.get('/stock/movements', query: query.toQuery()) as Json, StockMovement.fromJson);

  Future<StockLine> updateThreshold(int stockId, int threshold) async => StockLine.fromJson(
    await _api.put('/stock/$stockId/alert-threshold', data: {'alert_threshold': threshold}) as Json,
  );

  /// Entrée, sortie, perte ou ajustement. Pour un ajustement, [quantity] est la quantité comptée.
  Future<StockMovement> apply(
    StockOperation operation, {
    required int productId,
    required int quantity,
    int? storeId,
    String? reason,
    String? reference,
  }) async {
    final (path, body) = switch (operation) {
      StockOperation.entry => ('/stock/entry', {'quantity': quantity, 'reference': reference}),
      StockOperation.exit => ('/stock/exit', {'quantity': quantity, 'type': 'EXIT', 'reference': reference}),
      StockOperation.loss => ('/stock/exit', {'quantity': quantity, 'type': 'LOSS', 'reference': reference}),
      StockOperation.adjust => ('/stock/adjust', {'new_quantity': quantity}),
    };
    final data = await _api.post(path, data: {...body, 'product_id': productId, 'store_id': storeId, 'reason': reason});
    return StockMovement.fromJson(data as Json);
  }

  Future<StockValueReport> value({int? storeId, int? productId}) async => StockValueReport.fromJson(
    await _api.get('/dashboard/stock-value', query: {'store_id': storeId, 'product_id': productId}) as Json,
  );
}
