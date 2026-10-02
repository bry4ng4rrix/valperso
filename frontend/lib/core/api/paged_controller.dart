import 'package:flutter/foundation.dart';

import 'api_exception.dart';
import 'paged.dart';

typedef PageFetcher<T> = Future<Paged<T>> Function(PageQuery query);

/// État d'une liste paginée : éléments, page courante, filtres, chargement et erreur.
///
/// Utilisé par toutes les listes de l'application (ventes, produits, clients...) :
/// la pagination, les filtres et les états (chargement / vide / erreur) restent identiques partout.
class PagedController<T> extends ChangeNotifier {
  PagedController(this._fetch, {Map<String, Object?> filters = const {}, this.pageSize = 20})
      : _filters = {...filters};

  final PageFetcher<T> _fetch;
  final int pageSize;
  final Map<String, Object?> _filters;

  List<T> items = const [];
  int total = 0;
  int page = 1;
  int pages = 0;
  bool isLoading = false;
  bool hasLoaded = false;
  ApiException? error;
  int _requestId = 0;
  bool _disposed = false;

  Map<String, Object?> get filters => Map.unmodifiable(_filters);

  Object? filter(String key) => _filters[key];

  bool get isEmpty => hasLoaded && items.isEmpty && error == null;

  /// Nombre de filtres actifs (hors recherche et clés internes), pour le badge du bouton Filtres.
  int get activeFilterCount => _filters.entries
      .where((e) => e.key != 'search' && e.key != 'sort' && !e.key.startsWith('_') && e.value != null && e.value != '')
      .length;

  Future<void> load([int targetPage = 1]) async {
    final requestId = ++_requestId;
    isLoading = true;
    error = null;
    _notify();
    try {
      final result = await _fetch(PageQuery(page: targetPage, pageSize: pageSize, filters: _filters));
      if (requestId != _requestId) return; // une requête plus récente a été lancée entre-temps
      items = result.items;
      total = result.total;
      page = result.page == 0 ? targetPage : result.page;
      pages = result.pages;
    } on ApiException catch (exception) {
      if (requestId != _requestId) return;
      error = exception;
    } finally {
      if (requestId == _requestId) {
        isLoading = false;
        hasLoaded = true;
        _notify();
      }
    }
  }

  Future<void> refresh() => load(page);

  Future<void> nextPage() async {
    if (page < pages) await load(page + 1);
  }

  Future<void> previousPage() async {
    if (page > 1) await load(page - 1);
  }

  /// Modifie un ou plusieurs filtres et revient à la première page.
  Future<void> updateFilters(Map<String, Object?> changes) {
    _filters.addAll(changes);
    _filters.removeWhere((_, value) => value == null || value == '');
    return load(1);
  }

  Future<void> setFilter(String key, Object? value) => updateFilters({key: value});

  /// Retire tous les filtres sauf ceux listés dans [keep].
  Future<void> clearFilters({Set<String> keep = const {}}) {
    _filters.removeWhere((key, _) => !keep.contains(key) && !key.startsWith('_'));
    return load(1);
  }

  /// Récupère TOUS les résultats (page par page, 100 par 100), pour un export.
  /// Avec [useFilters] = false, seuls les filtres internes (préfixés par `_`) sont conservés.
  Future<List<T>> fetchAll({bool useFilters = true, int maxPages = 200}) async {
    final filters = useFilters
        ? Map<String, Object?>.of(_filters)
        : {for (final e in _filters.entries) if (e.key.startsWith('_')) e.key: e.value};
    final results = <T>[];
    for (var current = 1; current <= maxPages; current++) {
      final result = await _fetch(PageQuery(page: current, pageSize: PageQuery.maxPageSize, filters: filters));
      results.addAll(result.items);
      if (current >= result.pages) break;
    }
    return results;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
