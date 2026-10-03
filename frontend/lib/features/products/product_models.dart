import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';

/// Photo d'un produit (chemin servi par l'API, ex. /media/products/....jpg).
class ProductImage {
  const ProductImage({required this.id, required this.url});

  factory ProductImage.fromJson(Json json) => ProductImage(id: toInt(json['id']), url: '${json['url']}');

  final int id;
  final String url;
}

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
    this.images = const [],
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
    images: toList(json['images'], ProductImage.fromJson),
  );

  final int id;
  final String reference;
  final String name;
  final CategoryRef? category;
  final double purchasePrice;
  final double sellingPrice;
  final bool isActive;

  /// Photo principale (la première), ou null.
  final String? imageUrl;

  /// Toutes les photos (la fiche produit ; les listes de stock n'ont que la principale).
  final List<ProductImage> images;

  List<String> get imageUrls => [for (final image in images) image.url];

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
