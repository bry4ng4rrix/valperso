import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';
import 'transfer_models.dart';

class TransfersRepository {
  TransfersRepository(this._api);

  final ApiClient _api;

  Future<Paged<StockTransfer>> list(PageQuery query) async =>
      Paged.fromJson(await _api.get('/stock-transfers', query: query.toQuery()) as Json, StockTransfer.fromJson);

  Future<StockTransfer> get(int id) async => StockTransfer.fromJson(await _api.get('/stock-transfers/$id') as Json);

  /// [lines] : product_id -> quantité. [sourceStoreId] null = magasin par défaut (Stock Local pour un ADMIN).
  Future<StockTransfer> create({
    required int destinationStoreId,
    required Map<int, int> lines,
    int? sourceStoreId,
  }) async {
    final data = await _api.post(
      '/stock-transfers',
      data: {
        'source_store_id': sourceStoreId,
        'destination_store_id': destinationStoreId,
        'items': [
          for (final entry in lines.entries) {'product_id': entry.key, 'quantity': entry.value},
        ],
      },
    );
    return StockTransfer.fromJson(data as Json);
  }

  Future<StockTransfer> cancel(int id) async =>
      StockTransfer.fromJson(await _api.post('/stock-transfers/$id/cancel') as Json);
}
