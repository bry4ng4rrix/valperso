import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';
import '../sales/sale_models.dart';
import '../stock/stock_models.dart';

class TopProduct {
  const TopProduct({
    required this.productId,
    required this.reference,
    required this.name,
    required this.quantitySold,
    required this.revenue,
  });

  factory TopProduct.fromJson(Json json) => TopProduct(
    productId: toInt(json['product_id']),
    reference: '${json['reference']}',
    name: '${json['name']}',
    quantitySold: toInt(json['quantity_sold']),
    revenue: toDouble(json['revenue']),
  );

  final int productId;
  final String reference;
  final String name;
  final int quantitySold;
  final double revenue;
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
  });

  factory DashboardSummary.fromJson(Json json) => DashboardSummary(
    salesCount: toInt(json['sales_count']),
    revenue: toDouble(json['revenue']),
    estimatedProfit: toDouble(json['estimated_profit']),
    amountCollected: toDouble(json['amount_collected']),
    debtAmount: toDouble(json['debt_amount']),
    productsCount: toInt(json['products_count']),
    storesCount: toInt(json['stores_count']),
    stockQuantity: toInt(json['stock_quantity']),
    lowStockCount: toInt(json['low_stock_count']),
    outOfStockCount: toInt(json['out_of_stock_count']),
    unavailableProductsCount: toInt(json['unavailable_products_count']),
    topProducts: toList(json['top_products'], TopProduct.fromJson),
    recentSales: toList(json['recent_sales'], Sale.fromJson),
  );

  final int salesCount;
  final double revenue;
  final double estimatedProfit;
  final double amountCollected;
  final double debtAmount;
  final int productsCount;
  final int storesCount;
  final int stockQuantity;
  final int lowStockCount;
  final int outOfStockCount;
  final int unavailableProductsCount;
  final List<TopProduct> topProducts;
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

  Future<Paged<StockLine>> lowStock({int? storeId, int pageSize = 5}) async => Paged.fromJson(
    await _api.get('/dashboard/low-stock', query: cleanQuery({'store_id': storeId, 'page_size': pageSize})) as Json,
    StockLine.fromJson,
  );
}
