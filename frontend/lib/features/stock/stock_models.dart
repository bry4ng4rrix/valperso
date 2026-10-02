import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';
import '../products/product_models.dart';

/// Quantité d'un produit dans un magasin, avec ses états et ses valeurs calculés par l'API.
class StockLine {
  const StockLine({
    required this.id,
    required this.product,
    required this.store,
    required this.quantity,
    required this.alertThreshold,
    required this.lowStock,
    required this.outOfStock,
    required this.purchaseValue,
    required this.saleValue,
    required this.potentialProfit,
    this.updatedAt,
  });

  factory StockLine.fromJson(Json json) => StockLine(
    id: toInt(json['id']),
    product: Product.fromJson(Json.from(json['product'] as Map)),
    store: StoreRef.fromJson(Json.from(json['store'] as Map)),
    quantity: toInt(json['quantity']),
    alertThreshold: toInt(json['alert_threshold']),
    lowStock: json['low_stock'] == true,
    outOfStock: json['out_of_stock'] == true,
    purchaseValue: toDouble(json['purchase_value']),
    saleValue: toDouble(json['sale_value']),
    potentialProfit: toDouble(json['potential_profit']),
    updatedAt: toDate(json['updated_at']),
  );

  final int id;
  final Product product;
  final StoreRef store;
  final int quantity;
  final int alertThreshold;
  final bool lowStock;
  final bool outOfStock;
  final double purchaseValue;
  final double saleValue;
  final double potentialProfit;
  final DateTime? updatedAt;

  ProductListItem toListItem() => ProductListItem(
    product: product,
    stockId: id,
    store: store,
    quantity: quantity,
    lowStock: lowStock,
    outOfStock: outOfStock,
  );
}

enum MovementType {
  entry('ENTRY', 'Entrée'),
  exit('EXIT', 'Sortie'),
  sale('SALE', 'Vente'),
  returned('RETURN', 'Retour'),
  adjustment('ADJUSTMENT', 'Ajustement'),
  loss('LOSS', 'Perte'),
  transferOut('TRANSFER_OUT', 'Transfert sortant'),
  transferIn('TRANSFER_IN', 'Transfert entrant');

  const MovementType(this.code, this.label);
  final String code;
  final String label;

  static MovementType fromCode(String code) =>
      values.firstWhere((type) => type.code == code, orElse: () => MovementType.adjustment);
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.product,
    required this.store,
    required this.user,
    required this.type,
    required this.quantity,
    required this.createdAt,
    this.reason,
    this.reference,
  });

  factory StockMovement.fromJson(Json json) => StockMovement(
    id: toInt(json['id']),
    product: ProductRef.fromJson(Json.from(json['product'] as Map)),
    store: StoreRef.fromJson(Json.from(json['store'] as Map)),
    user: UserRef.fromJson(Json.from(json['user'] as Map)),
    type: MovementType.fromCode('${json['type']}'),
    quantity: toInt(json['quantity']),
    reason: toStringOrNull(json['reason']),
    reference: toStringOrNull(json['reference']),
    createdAt: toDate(json['created_at']) ?? DateTime.now(),
  );

  final int id;
  final ProductRef product;
  final StoreRef store;
  final UserRef user;
  final MovementType type;

  /// Positive pour une entrée, négative pour une sortie.
  final int quantity;
  final String? reason;
  final String? reference;
  final DateTime createdAt;
}

/// Valeur du stock (magasin ou total).
class StockValue {
  const StockValue({
    required this.quantity,
    required this.purchaseValue,
    required this.saleValue,
    required this.potentialProfit,
    this.store,
  });

  factory StockValue.fromJson(Json json) => StockValue(
    store: toObject(json['store'], StoreRef.fromJson),
    quantity: toInt(json['quantity']),
    purchaseValue: toDouble(json['purchase_value']),
    saleValue: toDouble(json['sale_value']),
    potentialProfit: toDouble(json['potential_profit']),
  );

  final StoreRef? store;
  final int quantity;
  final double purchaseValue;
  final double saleValue;
  final double potentialProfit;
}

class StockValueReport {
  const StockValueReport({required this.stores, required this.total});

  factory StockValueReport.fromJson(Json json) => StockValueReport(
    stores: toList(json['stores'], StockValue.fromJson),
    total: StockValue.fromJson(Json.from(json['total'] as Map)),
  );

  final List<StockValue> stores;
  final StockValue total;
}
