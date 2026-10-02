import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/models/refs.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/store_selector.dart';
import '../stock/stock_models.dart';
import '../stock/stock_repository.dart';
import '../stores/stores_repository.dart';
import 'transfer_models.dart';
import 'transfers_repository.dart';

class _TransferLine {
  _TransferLine(this.stock) : quantity = TextEditingController(text: '1');

  final StockLine stock;
  final TextEditingController quantity;

  int get value => int.tryParse(quantity.text.trim()) ?? 0;
  bool get isValid => value > 0 && value <= stock.quantity;
}

/// Nouveau transfert : source → destination → produits → quantités → récapitulatif
/// → confirmation → envoi → résultat (stocks des deux magasins après le transfert).
class NewTransferScreen extends StatefulWidget {
  const NewTransferScreen({super.key, this.productId, this.sourceStoreId});

  /// Produit à ajouter d'office (depuis la fiche produit ou le stock).
  final int? productId;
  final int? sourceStoreId;

  @override
  State<NewTransferScreen> createState() => _NewTransferScreenState();
}

class _NewTransferScreenState extends State<NewTransferScreen> {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  StoreRef? _source;
  StoreRef? _destination;
  final Map<int, _TransferLine> _lines = {};
  StockTransfer? _result;
  Future<Paged<StockLine>>? _search;
  String _term = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!_user.canChooseStore) {
      _source = _user.store;
    } else {
      final stores = await context.read<StoresRepository>().active();
      final initial =
          stores.where((store) => store.id == widget.sourceStoreId).firstOrNull ??
          stores.where((store) => store.isCentral).firstOrNull;
      _source = initial?.ref;
    }
    if (!mounted) return;
    setState(_runSearch);
    final productId = widget.productId;
    final source = _source;
    if (productId != null && source != null) {
      final page = await context.read<StockRepository>().lines(
        PageQuery(pageSize: 1, filters: {'store_id': source.id, 'product_id': productId}),
      );
      if (mounted && page.items.isNotEmpty && page.items.first.quantity > 0) _add(page.items.first);
    }
  }

  @override
  void dispose() {
    for (final line in _lines.values) {
      line.quantity.dispose();
    }
    super.dispose();
  }

  void _runSearch() {
    final source = _source;
    _search = source == null
        ? null
        : context.read<StockRepository>().lines(
            PageQuery(pageSize: 8, filters: {'store_id': source.id, 'search': _term, 'sort': '-quantity'}),
          );
  }

  void _setSource(StoreRef? store) {
    if (store?.id == _source?.id) return;
    setState(() {
      _source = store;
      if (_destination?.id == store?.id) _destination = null;
      for (final line in _lines.values) {
        line.quantity.dispose();
      }
      _lines.clear(); // les quantités disponibles dépendent du magasin source
      _runSearch();
    });
  }

  void _add(StockLine stock) => setState(() => _lines[stock.product.id] = _TransferLine(stock));

  void _remove(int productId) => setState(() => _lines.remove(productId)?.quantity.dispose());

  List<String> get _problems => [
    if (_source == null) 'Choisissez le magasin source.',
    if (_destination == null) 'Choisissez le magasin de destination.',
    if (_lines.isEmpty) 'Ajoutez au moins un produit.',
    for (final line in _lines.values)
      if (!line.isValid) '${line.stock.product.label} : quantité entre 1 et ${line.stock.quantity}.',
  ];

  Future<void> _submit() async {
    final problems = _problems;
    if (problems.isNotEmpty) return Notify.warning(context, problems.first);
    final source = _source!;
    final destination = _destination!;
    final confirmed = await showConfirmation(
      context,
      title: 'Confirmer le transfert ?',
      message: '${source.label} → ${destination.label}',
      content: _Summary(lines: _lines.values.toList(), source: source, destination: destination),
      confirmLabel: 'Transférer',
      type: ConfirmationType.warning,
    );
    if (!confirmed || !mounted) return;
    StockTransfer? result;
    await runApiAction(context, () async {
      result = await context.read<TransfersRepository>().create(
        sourceStoreId: source.id,
        destinationStoreId: destination.id,
        lines: {for (final line in _lines.values) line.stock.product.id: line.value},
      );
    });
    if (result != null && mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return DetailPage(
      title: result == null ? 'Nouveau transfert' : 'Transfert effectué',
      child: result == null ? _form() : _ResultView(transfer: result, onNew: _reset),
    );
  }

  void _reset() {
    for (final line in _lines.values) {
      line.quantity.dispose();
    }
    setState(() {
      _lines.clear();
      _result = null;
      _destination = null;
      _runSearch();
    });
  }

  Widget _form() {
    final theme = Theme.of(context);
    final source = _source;
    return ListView(
      padding: const EdgeInsets.all(Gaps.lg),
      children: [
        TwoColumns(
          breakpoint: 900,
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: '1. Magasins',
                icon: Icons.storefront_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_user.canChooseStore)
                      StoreSelector(
                        label: 'Magasin source',
                        value: source?.id,
                        onChanged: (store) => _setSource(store?.ref),
                      )
                    else
                      InfoRow(label: 'Magasin source', value: source?.label ?? 'Aucun magasin affecté'),
                    const SizedBox(height: Gaps.md),
                    StoreSelector(
                      label: 'Magasin de destination',
                      value: _destination?.id,
                      excludeId: source?.id,
                      onChanged: (store) => setState(() => _destination = store?.ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gaps.lg),
              SectionCard(
                title: '2. Produits à transférer',
                icon: Icons.inventory_2_outlined,
                child: source == null
                    ? const Text('Choisissez d\'abord le magasin source.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppSearchField(
                            hint: 'Rechercher un produit de ${source.label}',
                            onChanged: (term) => setState(() {
                              _term = term;
                              _runSearch();
                            }),
                          ),
                          const SizedBox(height: Gaps.sm),
                          FutureBuilder<Paged<StockLine>>(
                            future: _search,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) return const Text('Recherche impossible.');
                              if (!snapshot.hasData) return const LinearProgressIndicator();
                              final results = snapshot.data!.items;
                              if (results.isEmpty) {
                                return const Padding(padding: EdgeInsets.all(Gaps.md), child: Text('Aucun produit.'));
                              }
                              return Column(
                                children: [
                                  for (final stock in results)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: Text(stock.product.label),
                                      subtitle: Text(
                                        '${stock.product.reference.toUpperCase()} · disponible : ${stock.quantity}',
                                      ),
                                      trailing: _lines.containsKey(stock.product.id)
                                          ? const Icon(Icons.check, color: AppColors.success)
                                          : stock.quantity <= 0
                                          ? const Text('Épuisé', style: TextStyle(color: AppColors.danger))
                                          : IconButton(
                                              tooltip: 'Ajouter',
                                              onPressed: () => _add(stock),
                                              icon: const Icon(Icons.add_circle_outline),
                                            ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
              ),
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: '3. Quantités (${_lines.length})',
                icon: Icons.format_list_numbered,
                child: _lines.isEmpty
                    ? const Text('Aucun produit sélectionné.')
                    : Column(
                        children: [
                          for (final line in _lines.values)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Gaps.md),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(line.stock.product.label, style: theme.textTheme.titleSmall),
                                        Text(
                                          'Source : ${line.stock.quantity} → ${line.stock.quantity - line.value}'
                                          '${line.value == line.stock.quantity ? ' (épuisé dans la source)' : ''}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: line.isValid ? null : AppColors.danger,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: Gaps.sm),
                                  SizedBox(
                                    width: 110,
                                    child: TextField(
                                      controller: line.quantity,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      decoration: InputDecoration(
                                        labelText: 'Quantité',
                                        isDense: true,
                                        errorText: line.isValid ? null : 'Max ${line.stock.quantity}',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Tout transférer',
                                    onPressed: () => setState(() => line.quantity.text = '${line.stock.quantity}'),
                                    icon: const Icon(Icons.vertical_align_top),
                                  ),
                                  IconButton(
                                    tooltip: 'Retirer',
                                    onPressed: () => _remove(line.stock.product.id),
                                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              if (_lines.isNotEmpty && _destination != null && source != null) ...[
                const SizedBox(height: Gaps.lg),
                SectionCard(
                  title: '4. Récapitulatif',
                  icon: Icons.fact_check_outlined,
                  child: _Summary(lines: _lines.values.toList(), source: source, destination: _destination!),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gaps.xl),
        AppButton(
          label: 'Valider le transfert',
          loadingLabel: 'Transfert en cours...',
          icon: Icons.swap_horiz,
          expand: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.lines, required this.source, required this.destination});

  final List<_TransferLine> lines;
  final StoreRef source;
  final StoreRef destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = lines.fold(0, (sum, line) => sum + line.value);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${source.label} → ${destination.label}', style: theme.textTheme.titleSmall),
        const SizedBox(height: Gaps.sm),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text('${line.stock.product.label} × ${line.value}')),
                Text('${line.stock.quantity} → ${line.stock.quantity - line.value}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        const Divider(),
        Text('Total : ${Formats.quantity(total)} unité${total > 1 ? 's' : ''}', style: theme.textTheme.titleSmall),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.transfer, required this.onNew});

  final StockTransfer transfer;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Gaps.lg),
      children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 56),
        const SizedBox(height: Gaps.md),
        Text(
          'Transfert ${transfer.reference} effectué',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gaps.xs),
        Text('${transfer.source.label} → ${transfer.destination.label}', textAlign: TextAlign.center),
        const SizedBox(height: Gaps.xl),
        SectionCard(
          title: 'Stocks après le transfert',
          icon: Icons.inventory_outlined,
          child: Column(
            children: [
              for (final level in transfer.stockLevels)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Formats.capitalize(level.product.name)),
                  subtitle: Text(
                    '${transfer.source.label} : ${level.sourceQuantity}'
                    '${level.sourceQuantity == 0 ? ' (épuisé)' : ''}\n'
                    '${transfer.destination.label} : ${level.destinationQuantity}',
                  ),
                  isThreeLine: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: Gaps.xl),
        Wrap(
          spacing: Gaps.md,
          runSpacing: Gaps.md,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => context.pushReplacement('/transfers/${transfer.id}'),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Voir le transfert'),
            ),
            FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.add), label: const Text('Nouveau transfert')),
          ],
        ),
      ],
    );
  }
}
