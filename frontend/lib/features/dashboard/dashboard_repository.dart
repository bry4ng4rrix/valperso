import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';
import '../sales/sale_models.dart';

class TopProduct {
  const TopProduct({
    required this.productId,
    required this.reference,
    required this.name,
    required this.quantitySold,
    required this.revenue,
    this.stockQuantity,
  });

  factory TopProduct.fromJson(Json json) => TopProduct(
    productId: toInt(json['product_id']),
    reference: '${json['reference']}',
    name: '${json['name']}',
    quantitySold: toInt(json['quantity_sold']),
    revenue: toDouble(json['revenue']),
    stockQuantity: json['stock_quantity'] == null ? null : toInt(json['stock_quantity']),
  );

  final int productId;
  final String reference;
  final String name;
  final int quantitySold;
  final double revenue;

  /// Produits les moins vendus : quantité encore en stock.
  final int? stockQuantity;
}

/// Chiffres d'un magasin sur la période (stock : quantité actuelle).
class StorePerformance {
  const StorePerformance({
    required this.store,
    required this.salesCount,
    required this.revenue,
    required this.salesMargin,
    required this.debtAmount,
    required this.stockQuantity,
  });

  factory StorePerformance.fromJson(Json json) => StorePerformance(
    store: StoreRef.fromJson(Json.from(json['store'] as Map)),
    salesCount: toInt(json['sales_count']),
    revenue: toDouble(json['revenue']),
    salesMargin: toDouble(json['sales_margin']),
    debtAmount: toDouble(json['debt_amount']),
    stockQuantity: toInt(json['stock_quantity']),
  );

  final StoreRef store;
  final int salesCount;
  final double revenue;
  final double salesMargin;
  final double debtAmount;
  final int stockQuantity;
}

class SalesPoint {
  const SalesPoint({required this.period, required this.salesCount, required this.revenue});

  factory SalesPoint.fromJson(Json json) => SalesPoint(
    period: toDate(json['period']) ?? DateTime.now(),
    salesCount: toInt(json['sales_count']),
    revenue: toDouble(json['revenue']),
  );

  final DateTime period;
  final int salesCount;
  final double revenue;
}

class DashboardSummary {
  const DashboardSummary({
    required this.salesCount,
    required this.revenue,
    required this.estimatedProfit,
    required this.salesMargin,
    required this.amountCollected,
    required this.debtAmount,
    required this.productsCount,
    required this.storesCount,
    required this.stockQuantity,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.unavailableProductsCount,
    required this.topProducts,
    required this.recentSales,
    this.leastSoldProducts = const [],
    this.storesPerformance = const [],
  });

  factory DashboardSummary.fromJson(Json json) => DashboardSummary(
    salesCount: toInt(json['sales_count']),
    revenue: toDouble(json['revenue']),
    estimatedProfit: toDouble(json['estimated_profit']),
    salesMargin: toDouble(json['sales_margin']),
    amountCollected: toDouble(json['amount_collected']),
    debtAmount: toDouble(json['debt_amount']),
    productsCount: toInt(json['products_count']),
    storesCount: toInt(json['stores_count']),
    stockQuantity: toInt(json['stock_quantity']),
    lowStockCount: toInt(json['low_stock_count']),
    outOfStockCount: toInt(json['out_of_stock_count']),
    unavailableProductsCount: toInt(json['unavailable_products_count']),
    topProducts: toList(json['top_products'], TopProduct.fromJson),
    leastSoldProducts: toList(json['least_sold_products'], TopProduct.fromJson),
    storesPerformance: toList(json['stores_performance'], StorePerformance.fromJson),
    recentSales: toList(json['recent_sales'], Sale.fromJson),
  );

  final int salesCount;
  final double revenue;

  /// Marge (prix de vente − prix) × quantité de tout le stock actuel.
  final double estimatedProfit;

  /// Marge (prix de vente − prix) × quantité des produits vendus sur la période (« Encaissé »).
  final double salesMargin;

  /// Paiements reçus sur la période.
  final double amountCollected;
  final double debtAmount;
  final int productsCount;
  final int storesCount;
  final int stockQuantity;
  final int lowStockCount;
  final int outOfStockCount;
  final int unavailableProductsCount;
  final List<TopProduct> topProducts;

  /// Produits en stock les moins vendus sur la période (0 vendu compris).
  final List<TopProduct> leastSoldProducts;
  final List<StorePerformance> storesPerformance;
  final List<Sale> recentSales;
}

class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  Future<DashboardSummary> summary({Map<String, Object?> range = const {}, int? storeId}) async =>
      DashboardSummary.fromJson(
        await _api.get('/dashboard/summary', query: cleanQuery({...range, 'store_id': storeId})) as Json,
      );

  Future<List<SalesPoint>> sales({Map<String, Object?> range = const {}, int? storeId, String groupBy = 'day'}) async =>
      toList(
        await _api.get('/dashboard/sales', query: cleanQuery({...range, 'store_id': storeId, 'group_by': groupBy})),
        SalesPoint.fromJson,
      );
}
