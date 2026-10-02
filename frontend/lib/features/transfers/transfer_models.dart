import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';

class TransferItem {
  const TransferItem({required this.product, required this.quantity});

  factory TransferItem.fromJson(Json json) =>
      TransferItem(product: ProductRef.fromJson(Json.from(json['product'] as Map)), quantity: toInt(json['quantity']));

  final ProductRef product;
  final int quantity;
}

/// Stock d'un produit dans les deux magasins après un transfert.
class TransferStockLevel {
  const TransferStockLevel({required this.product, required this.sourceQuantity, required this.destinationQuantity});

  factory TransferStockLevel.fromJson(Json json) => TransferStockLevel(
    product: ProductRef.fromJson(Json.from(json['product'] as Map)),
    sourceQuantity: toInt(json['source_quantity']),
    destinationQuantity: toInt(json['destination_quantity']),
  );

  final ProductRef product;
  final int sourceQuantity;
  final int destinationQuantity;
}

class StockTransfer {
  const StockTransfer({
    required this.id,
    required this.reference,
    required this.source,
    required this.destination,
    required this.status,
    required this.items,
    required this.creator,
    required this.createdAt,
    this.stockLevels = const [],
  });

  factory StockTransfer.fromJson(Json json) => StockTransfer(
    id: toInt(json['id']),
    reference: '${json['reference']}',
    source: StoreRef.fromJson(Json.from(json['source_store'] as Map)),
    destination: StoreRef.fromJson(Json.from(json['destination_store'] as Map)),
    status: '${json['status']}',
    items: toList(json['items'], TransferItem.fromJson),
    creator: UserRef.fromJson(Json.from(json['creator'] as Map)),
    createdAt: toDate(json['created_at']) ?? DateTime.now(),
    stockLevels: toList(json['stock_levels'], TransferStockLevel.fromJson),
  );

  final int id;
  final String reference;
  final StoreRef source;
  final StoreRef destination;
  final String status; // COMPLETED ou CANCELLED
  final List<TransferItem> items;
  final UserRef creator;
  final DateTime createdAt;
  final List<TransferStockLevel> stockLevels;

  bool get isCancelled => status == 'CANCELLED';
  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);
}
