import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/store_selector.dart';
import '../categories/categories_repository.dart';
import '../stock/stock_repository.dart';
import '../stock/stock_value_dialog.dart';
import '../stores/stores_repository.dart';
import 'product_models.dart';
import 'product_widgets.dart';
import 'products_repository.dart';

enum ProductsMode { store, catalogue }

/// Liste des produits.
///
/// - « Par magasin » : les produits d'un magasin avec leur quantité et leur état de stock ;
/// - « Catalogue » : tous les produits, actifs ou non (gestion du catalogue).
/// Un vendeur voit toujours les produits de son magasin.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.initialStockState, this.initialStoreId});

  /// Filtre de départ depuis l'accueil : `low` (stock faible) ou `out` (épuisés), tous magasins.
  final String? initialStockState;

  /// Magasin de départ (ex. depuis la fiche d'un magasin).
  final int? initialStoreId;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late ProductsMode _mode = _user.can(Perm.stockView) ? ProductsMode.store : ProductsMode.catalogue;
  late final PagedController<ProductListItem> _controller = PagedController(
    _fetch,
    filters: _initialFilters(),
    liveEntities: const {'product', 'stock', 'category'},
  );

  bool get _showCost => _user.canAny(const [Perm.productCreate, Perm.productUpdate]);
  bool get _canSwitchMode => _user.can(Perm.stockView) && _user.isAdmin;

  Map<String, Object?> _initialFilters() => _mode == ProductsMode.store
      ? {
          'store_id': _user.canChooseStore ? widget.initialStoreId : _user.store?.id,
          'low_stock': widget.initialStockState == 'low' ? true : null,
          'out_of_stock': widget.initialStockState == 'out' ? true : null,
        }
      : {'is_active': true};

  Future<Paged<ProductListItem>> _fetch(PageQuery query) async {
    if (_mode == ProductsMode.store) {
      final page = await context.read<StockRepository>().lines(query);
      return page.map((line) => line.toListItem());
    }
    final page = await context.read<ProductsRepository>().list(query);
    return page.map((product) => ProductListItem(product: product));
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// L'administrateur commence sur le Stock Local (sauf lien « stock faible / épuisés » : tous les magasins).
  Future<void> _start() async {
    final allStores = widget.initialStockState != null;
    if (_mode == ProductsMode.store && _user.canChooseStore && _controller.filter('store_id') == null && !allStores) {
      final stores = await context.read<StoresRepository>().active();
      final central = stores.where((store) => store.isCentral).firstOrNull;
      if (!mounted) return;
      if (central != null) return _controller.setFilter('store_id', central.id);
    }
    await _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _switchMode(ProductsMode mode) async {
    if (mode == _mode) return;
    final search = _controller.filter('search');
    final storeId = _controller.filter('store_id');
    setState(() => _mode = mode);
    await _controller.replaceFilters({
      'search': search,
      if (mode == ProductsMode.store) 'store_id': storeId ?? _user.store?.id,
      if (mode == ProductsMode.catalogue) 'is_active': true,
    });
  }

  Future<void> _openDetail(ProductListItem item) async {
    await context.push('/products/${item.product.id}');
    if (mounted) await _controller.refresh();
  }

  void _openFilters() {
    showFilterSheet(
      context,
      onReset: () => _controller.clearFilters(keep: {'search', 'store_id'}),
      builder: (context, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FutureBuilder<List<Category>>(
            future: context.read<CategoriesRepository>().active(),
            builder: (context, snapshot) => FilterDropdown<int>(
              label: 'Catégorie',
              value: _controller.filter('category_id') as int?,
              allLabel: 'Toutes les catégories',
              options: {for (final category in snapshot.data ?? const <Category>[]) category.id: category.label},
              onChanged: (value) {
                _controller.setFilter('category_id', value);
                refresh();
              },
            ),
          ),
          if (_mode == ProductsMode.catalogue)
            FilterDropdown<bool>(
              label: 'Statut',
              value: _controller.filter('is_active') as bool?,
              options: const {true: 'Actifs', false: 'Inactifs'},
              onChanged: (value) {
                _controller.setFilter('is_active', value);
                refresh();
              },
            ),
          ChoiceChips<String>(
            label: 'Trier par',
            value: (_controller.filter('sort') as String?) ?? 'name',
            options: {
              'name': 'Nom',
              'reference': 'Référence',
              if (_mode == ProductsMode.store) ...{'quantity': 'Quantité ↑', '-quantity': 'Quantité ↓'},
              if (_mode == ProductsMode.catalogue) ...{'selling_price': 'Prix ↑', '-selling_price': 'Prix ↓'},
              '-created_at': 'Plus récents',
            },
            onChanged: (value) {
              _controller.setFilter('sort', value);
              refresh();
            },
          ),
        ],
      ),
    );
  }

  Widget _quickFilters() {
    final stockFilter = _controller.filter('out_of_stock') == true
        ? 'out'
        : _controller.filter('low_stock') == true
        ? 'low'
        : 'all';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_canSwitchMode || (_mode == ProductsMode.store && _user.canChooseStore))
          Wrap(
            spacing: Gaps.md,
            runSpacing: Gaps.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_canSwitchMode)
                SegmentedButton<ProductsMode>(
                  segments: const [
                    ButtonSegment(
                      value: ProductsMode.store,
                      label: Text('Par magasin'),
                      icon: Icon(Icons.storefront_outlined),
                    ),
                    ButtonSegment(value: ProductsMode.catalogue, label: Text('Catalogue'), icon: Icon(Icons.list_alt)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) => _switchMode(selection.first),
                ),
              if (_mode == ProductsMode.store && _user.canChooseStore)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: StoreSelector(
                    value: _controller.filter('store_id') as int?,
                    allLabel: 'Tous les magasins',
                    dense: true,
                    onChanged: (store) => _controller.setFilter('store_id', store?.id),
                  ),
                ),
            ],
          ),
        if (_mode == ProductsMode.store) ...[
          const SizedBox(height: Gaps.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (key, label) in const [('all', 'Tous'), ('low', 'Stock faible'), ('out', 'Épuisés')])
                  Padding(
                    padding: const EdgeInsets.only(right: Gaps.sm),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: stockFilter == key,
                      onSelected: (_) => _controller.updateFilters({
                        'low_stock': key == 'low' ? true : null,
                        'out_of_stock': key == 'out' ? true : null,
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final withStock = _mode == ProductsMode.store;
    return ListPage(
      title: 'Produits',
      controller: _controller,
      countLabel: (total) => '$total produit${total > 1 ? 's' : ''} trouvé${total > 1 ? 's' : ''}',
      search: AppSearchField(
        hint: 'Nom, référence, catégorie ou prix',
        initialValue: _controller.filter('search') as String?,
        onChanged: (value) => _controller.setFilter('search', value),
      ),
      onOpenFilters: _openFilters,
      quickFilters: ListenableBuilder(listenable: _controller, builder: (context, _) => _quickFilters()),
      actions: [
        if (withStock && _user.can(Perm.reportView))
          IconButton(
            tooltip: 'Valeur du stock',
            onPressed: () => showStockValueDialog(context, storeId: _controller.filter('store_id') as int?),
            icon: const Icon(Icons.account_balance_outlined),
          ),
        ExportButton<ProductListItem>(
          controller: _controller,
          columns: productExportColumns(showCost: _showCost, withStock: withStock),
          fileBaseName: withStock ? 'produits_stock' : 'produits',
          sheetName: 'Produits',
        ),
      ],
      primaryAction: _user.can(Perm.productCreate)
          ? PrimaryAction(
              label: 'Nouveau produit',
              icon: Icons.add,
              onPressed: () async {
                await context.push('/products/new');
                if (mounted) await _controller.refresh();
              },
            )
          : null,
      body: PagedListView<ProductListItem>(
        controller: _controller,
        onTap: _openDetail,
        emptyTitle: 'Aucun produit trouvé',
        emptyMessage: 'Essayez de modifier la recherche ou les filtres.',
        columns: productTableColumns(showCost: _showCost, withStock: withStock),
        cardBuilder: (context, item) => ProductCard(item: item, showCost: _showCost, onTap: () => _openDetail(item)),
      ),
    );
  }
}
