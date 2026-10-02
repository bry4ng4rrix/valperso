import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/product_avatar.dart';
import '../../shared/widgets/search_field.dart';
import 'stock_models.dart';
import 'stock_repository.dart';
import '../../core/widgets/app_dialog.dart';

/// Opérations de stock autorisées pour cet utilisateur.
List<StockOperation> allowedStockOperations(CurrentUser user) => [
  if (user.can(Perm.stockEntry)) StockOperation.entry,
  if (user.can(Perm.stockExit)) ...[StockOperation.exit, StockOperation.loss],
  if (user.can(Perm.stockAdjust)) StockOperation.adjust,
];

/// Ouvre la feuille d'opération de stock. Avec [line], le produit et le magasin sont déjà choisis ;
/// sinon l'utilisateur cherche le produit dans le magasin [storeId].
/// Renvoie true si une opération a été enregistrée.
Future<bool> showStockOperationSheet(
  BuildContext context, {
  StockLine? line,
  int? storeId,
  StockOperation? operation,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: _StockOperationSheet(line: line, storeId: storeId, initialOperation: operation),
    ),
  );
  return result ?? false;
}

class _StockOperationSheet extends StatefulWidget {
  const _StockOperationSheet({this.line, this.storeId, this.initialOperation});

  final StockLine? line;
  final int? storeId;
  final StockOperation? initialOperation;

  @override
  State<_StockOperationSheet> createState() => _StockOperationSheetState();
}

class _StockOperationSheetState extends State<_StockOperationSheet> with ApiFormState {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  late final List<StockOperation> _operations = allowedStockOperations(context.read<SessionController>().requireUser);
  late StockOperation _operation = widget.initialOperation != null && _operations.contains(widget.initialOperation)
      ? widget.initialOperation!
      : _operations.first;
  late StockLine? _line = widget.line;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    _reference.dispose();
    super.dispose();
  }

  int? get _entered => int.tryParse(_quantity.text.trim());

  /// Quantité après l'opération (aperçu).
  int? get _after {
    final line = _line;
    final value = _entered;
    if (line == null || value == null) return null;
    return switch (_operation) {
      StockOperation.entry => line.quantity + value,
      StockOperation.exit || StockOperation.loss => line.quantity - value,
      StockOperation.adjust => value,
    };
  }

  String? _validateQuantity(String? text) {
    final value = int.tryParse(text?.trim() ?? '');
    if (value == null) return 'Saisissez une quantité entière.';
    if (_operation == StockOperation.adjust) return value < 0 ? 'La quantité ne peut pas être négative.' : null;
    if (value <= 0) return 'La quantité doit être supérieure à 0.';
    final line = _line;
    if (line != null &&
        (_operation == StockOperation.exit || _operation == StockOperation.loss) &&
        value > line.quantity) {
      return 'Stock disponible : ${line.quantity}.';
    }
    return null;
  }

  Future<void> _submit() async {
    final line = _line;
    if (line == null) return Notify.warning(context, 'Choisissez d\'abord un produit.');
    if (!_formKey.currentState!.validate()) return;
    final quantity = _entered!;
    final confirmed = await showConfirmation(
      context,
      title: _operation.label,
      type: _operation == StockOperation.entry ? ConfirmationType.normal : ConfirmationType.warning,
      message: '${line.product.label} — ${line.store.label}',
      changes: [FieldChange('Quantité en stock', Formats.quantity(line.quantity), Formats.quantity(_after))],
      confirmLabel: 'Enregistrer',
    );
    if (!confirmed || !mounted) return;
    final saved = await submitToApi(
      () => context.read<StockRepository>().apply(
        _operation,
        productId: line.product.id,
        storeId: line.store.id,
        quantity: quantity,
        reason: trimOrNull(_reason.text),
        reference: trimOrNull(_reference.text),
      ),
    );
    if (saved == null || !mounted) return;
    Notify.success(context, 'Stock mis à jour : ${line.product.label} (${Formats.quantity(_after)}).');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = _line;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.formMaxWidth),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Opération de stock', style: theme.textTheme.titleLarge),
                const SizedBox(height: Gaps.md),
                Wrap(
                  spacing: Gaps.sm,
                  runSpacing: Gaps.sm,
                  children: [
                    for (final operation in _operations)
                      ChoiceChip(
                        label: Text(operation.label),
                        selected: operation == _operation,
                        onSelected: (_) => setState(() => _operation = operation),
                      ),
                  ],
                ),
                const SizedBox(height: Gaps.lg),
                if (line == null)
                  _ProductLinePicker(storeId: widget.storeId, onSelected: (picked) => setState(() => _line = picked))
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ProductAvatar(name: line.product.label, size: 44),
                    title: Text(line.product.label),
                    subtitle: Text('${line.store.label} · en stock : ${Formats.quantity(line.quantity)}'),
                    trailing: widget.line == null
                        ? IconButton(
                            tooltip: 'Changer de produit',
                            onPressed: () => setState(() => _line = null),
                            icon: const Icon(Icons.close),
                          )
                        : null,
                  ),
                const SizedBox(height: Gaps.md),
                AppTextField(
                  label: _operation == StockOperation.adjust ? 'Quantité comptée' : 'Quantité',
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: _validateQuantity,
                  errorText: errorFor('quantity') ?? errorFor('new_quantity'),
                  helper: _after == null ? null : 'Après l\'opération : ${Formats.quantity(_after)}',
                  onChanged: (_) => setState(() {}),
                  required: true,
                ),
                const SizedBox(height: Gaps.md),
                AppTextField(
                  label: _operation == StockOperation.adjust ? 'Motif de l\'ajustement' : 'Motif',
                  controller: _reason,
                  required: _operation == StockOperation.adjust,
                  errorText: errorFor('reason'),
                  validator: Validators.text(required: _operation == StockOperation.adjust, min: 3, max: 255),
                ),
                if (_operation != StockOperation.adjust) ...[
                  const SizedBox(height: Gaps.md),
                  AppTextField(
                    label: 'Référence (bon de livraison, facture fournisseur...)',
                    controller: _reference,
                    errorText: errorFor('reference'),
                  ),
                ],
                const SizedBox(height: Gaps.xl),
                AppButton(
                  label: 'Valider',
                  icon: Icons.check,
                  expand: true,
                  variant: _operation == StockOperation.entry ? AppButtonVariant.primary : AppButtonVariant.danger,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Recherche d'un produit dans le stock d'un magasin.
class _ProductLinePicker extends StatefulWidget {
  const _ProductLinePicker({required this.storeId, required this.onSelected});

  final int? storeId;
  final ValueChanged<StockLine> onSelected;

  @override
  State<_ProductLinePicker> createState() => _ProductLinePickerState();
}

class _ProductLinePickerState extends State<_ProductLinePicker> {
  late Future<Paged<StockLine>> _results = _search('');

  Future<Paged<StockLine>> _search(String term) => context.read<StockRepository>().lines(
    PageQuery(pageSize: 8, filters: {'store_id': widget.storeId, 'search': term}),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          hint: 'Produit : nom, référence, catégorie ou prix',
          onChanged: (term) => setState(() {
            _results = _search(term);
          }),
        ),
        const SizedBox(height: Gaps.sm),
        FutureBuilder<Paged<StockLine>>(
          future: _results,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('Recherche impossible.');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final lines = snapshot.data!.items;
            if (lines.isEmpty) return const Padding(padding: EdgeInsets.all(Gaps.md), child: Text('Aucun produit.'));
            return Column(
              children: [
                for (final line in lines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(line.product.label),
                    subtitle: Text('${line.product.reference.toUpperCase()} · ${line.store.label}'),
                    trailing: Text(Formats.quantity(line.quantity)),
                    onTap: () => widget.onSelected(line),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Modifier le seuil d'alerte d'une ligne de stock. Renvoie true si modifié.
Future<bool> showThresholdDialog(BuildContext context, StockLine line) async {
  final controller = TextEditingController(text: '${line.alertThreshold}');
  final value = await showDialog<int>(
    context: context,
    builder: (context) => AppDialog(
      title: 'Seuil d\'alerte',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${line.product.label} — ${line.store.label}'),
          const SizedBox(height: Gaps.md),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Seuil',
              helperText: 'Alerte « stock faible » quand la quantité atteint ce seuil.',
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final threshold = int.tryParse(controller.text.trim());
            if (threshold != null) Navigator.of(context).pop(threshold);
          },
          child: const Text('Continuer'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (value == null || value == line.alertThreshold || !context.mounted) return false;
  final confirmed = await showConfirmation(
    context,
    title: 'Modifier le seuil d\'alerte ?',
    message: '${line.product.label} — ${line.store.label}',
    changes: [FieldChange('Seuil d\'alerte', '${line.alertThreshold}', '$value')],
  );
  if (!confirmed || !context.mounted) return false;
  return runApiAction(
    context,
    () => context.read<StockRepository>().updateThreshold(line.id, value),
    success: 'Seuil d\'alerte modifié.',
  );
}
