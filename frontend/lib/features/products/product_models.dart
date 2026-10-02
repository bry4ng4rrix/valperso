import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';

/// Produit du catalogue (référence et nom non uniques).
class Product {
  const Product({
    required this.id,
    required this.reference,
    required this.name,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.isActive,
    this.category,
    this.imageUrl,
  });

  factory Product.fromJson(Json json) => Product(
    id: toInt(json['id']),
    reference: '${json['reference']}',
    name: '${json['name']}',
    category: toObject(json['category'], CategoryRef.fromJson),
    purchasePrice: toDouble(json['purchase_price']),
    sellingPrice: toDouble(json['selling_price']),
    isActive: json['is_active'] != false,
    imageUrl: toStringOrNull(json['image_url']),
  );

  final int id;
  final String reference;
  final String name;
  final CategoryRef? category;
  final double purchasePrice;
  final double sellingPrice;
  final bool isActive;

  /// Prévu pour l'image principale quand l'API la fournira.
  final String? imageUrl;

  double get unitProfit => sellingPrice - purchasePrice;

  String get label => Formats.capitalize(name);
}

/// Élément de la liste des produits : un produit, avec sa quantité quand un magasin est choisi.
class ProductListItem {
  const ProductListItem({
    required this.product,
    this.stockId,
    this.store,
    this.quantity,
    this.lowStock = false,
    this.outOfStock = false,
  });

  final Product product;
  final int? stockId;
  final StoreRef? store;
  final int? quantity;
  final bool lowStock;
  final bool outOfStock;

  bool get hasStock => quantity != null;
}
