import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/core/api/api_exception.dart';
import 'package:valmag/core/api/paged.dart';
import 'package:valmag/core/api/paged_controller.dart';

/// Faux serveur paginé : 45 éléments, filtre « pair ».
class _FakeSource {
  final List<PageQuery> queries = [];

  Future<Paged<int>> fetch(PageQuery query) async {
    queries.add(query);
    var items = List.generate(45, (index) => index + 1);
    if (query.filters['even'] == true) items = items.where((value) => value.isEven).toList();
    final start = (query.page - 1) * query.pageSize;
    final slice = items.skip(start).take(query.pageSize).toList();
    return Paged(
      items: slice,
      total: items.length,
      page: query.page,
      pageSize: query.pageSize,
      pages: (items.length / query.pageSize).ceil(),
    );
  }
}

void main() {
  test('charge la première page puis navigue', () async {
    final source = _FakeSource();
    final controller = PagedController<int>(source.fetch);
    await controller.load();
    expect(controller.items.first, 1);
    expect(controller.total, 45);
    expect(controller.pages, 3);
    await controller.nextPage();
    expect(controller.page, 2);
    expect(controller.items.first, 21);
    await controller.previousPage();
    expect(controller.page, 1);
  });

  test('un filtre recharge la page 1 et est envoyé à l\'API', () async {
    final source = _FakeSource();
    final controller = PagedController<int>(source.fetch);
    await controller.load(2);
    await controller.setFilter('even', true);
    expect(controller.page, 1);
    expect(controller.total, 22);
    expect(source.queries.last.toQuery(), containsPair('even', true));
  });

  test('compteur de filtres actifs : sans recherche, tri, période, clés internes ni filtres fixes', () async {
    final controller = PagedController<int>(
      _FakeSource().fetch,
      filters: {'has_debt': true},
      fixedKeys: const {'has_debt'},
    );
    await controller.updateFilters({
      'search': 'abc',
      'sort': '-created_at',
      'date_from': '2026-01-01',
      '_period': 'x',
      'store_id': 2,
      'status': null,
    });
    expect(controller.activeFilterCount, 1);
    await controller.clearFilters(keep: {'search'});
    expect(controller.filter('store_id'), isNull);
    expect(controller.filter('search'), 'abc');
    expect(controller.filter('has_debt'), isTrue, reason: 'un filtre fixe n\'est jamais retiré');
  });

  test('cleanQuery retire les valeurs vides et les clés internes', () {
    expect(const PageQuery(filters: {'a': null, 'b': '', '_c': 1, 'd': 0, 'e': false}).toQuery(), {
      'd': 0,
      'e': false,
      'page': 1,
      'page_size': 20,
    });
  });

  test('fetchAll récupère toutes les pages par 100 (export)', () async {
    final source = _FakeSource();
    final controller = PagedController<int>(source.fetch, filters: {'even': true});
    final filtered = await controller.fetchAll();
    expect(filtered, hasLength(22));
    final all = await controller.fetchAll(useFilters: false);
    expect(all, hasLength(45));
    expect(source.queries.every((query) => query.pageSize <= PageQuery.maxPageSize), isTrue);
  });

  test('erreur : conservée et exposée, les éléments précédents restent affichés', () async {
    var fail = false;
    final controller = PagedController<int>((query) async {
      if (fail) throw ApiException(message: 'Serveur indisponible', code: 'NETWORK');
      return const Paged(items: [1, 2], total: 2, page: 1, pageSize: 20, pages: 1);
    });
    await controller.load();
    fail = true;
    await controller.refresh();
    expect(controller.error?.message, 'Serveur indisponible');
    expect(controller.items, [1, 2]);
  });

  test('une réponse lente plus ancienne n\'écrase pas une réponse récente', () async {
    final slow = Completer<Paged<int>>();
    var calls = 0;
    final controller = PagedController<int>((query) {
      calls++;
      if (calls == 1) return slow.future;
      return Future.value(const Paged(items: [99], total: 1, page: 1, pageSize: 20, pages: 1));
    });
    final first = controller.load();
    await controller.setFilter('search', 'récent');
    slow.complete(const Paged(items: [1], total: 1, page: 1, pageSize: 20, pages: 1));
    await first;
    expect(controller.items, [99]);
  });
}
