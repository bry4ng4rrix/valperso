import '../utils/json.dart';

/// Une page de résultats renvoyée par l'API : `{items, total, page, page_size, pages}`.
class Paged<T> {
  const Paged({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.pages,
  });

  factory Paged.fromJson(Json json, T Function(Json json) parseItem) => Paged(
    items: toList(json['items'], parseItem),
    total: toInt(json['total']),
    page: toInt(json['page']),
    pageSize: toInt(json['page_size']),
    pages: toInt(json['pages']),
  );

  const Paged.empty() : items = const [], total = 0, page = 1, pageSize = 20, pages = 0;

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  final int pages;

  Paged<R> map<R>(R Function(T item) convert) =>
      Paged(items: items.map(convert).toList(), total: total, page: page, pageSize: pageSize, pages: pages);
}

/// Paramètres d'une demande de page. `filters` contient les filtres de l'écran (recherche, magasin...).
class PageQuery {
  const PageQuery({this.page = 1, this.pageSize = 20, this.filters = const {}});

  /// Taille maximale autorisée par l'API.
  static const maxPageSize = 100;

  final int page;
  final int pageSize;
  final Map<String, Object?> filters;

  /// Paramètres de requête prêts à envoyer (les filtres vides sont retirés).
  Map<String, Object?> toQuery() => cleanQuery({...filters, 'page': page, 'page_size': pageSize});
}

/// Retire les paramètres nuls ou vides, et les clés internes (préfixées par `_`).
Map<String, Object?> cleanQuery(Map<String, Object?> query) => {
  for (final entry in query.entries)
    if (entry.value != null && entry.value != '' && !entry.key.startsWith('_')) entry.key: entry.value,
};
