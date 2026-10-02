import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import '../categories/categories_repository.dart';
import '../categories/category_dialog.dart';
import 'product_models.dart';
import 'products_repository.dart';

/// Création ou modification d'un produit.
/// Règle métier : le prix de vente doit être supérieur ou égal au prix d'achat.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.productId});

  final int? productId;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> with ApiFormState {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _name = TextEditingController();
  final _purchasePrice = TextEditingController();
  final _sellingPrice = TextEditingController();
  int? _categoryId;
  Product? _product;
  late Future<void> _ready = _load();
  List<Category> _categories = const [];

  bool get _isEdit => widget.productId != null;

  Future<void> _load() async {
    final categoriesFuture = context.read<CategoriesRepository>().active();
    if (_isEdit) {
      final product = await context.read<ProductsRepository>().get(widget.productId!);
      _product = product;
      _reference.text = product.reference.toUpperCase();
      _name.text = product.label;
      _purchasePrice.text = Formats.amount(product.purchasePrice);
      _sellingPrice.text = Formats.amount(product.sellingPrice);
      _categoryId = product.category?.id;
    }
    _categories = await categoriesFuture;
  }

  @override
  void dispose() {
    _reference.dispose();
    _name.dispose();
    _purchasePrice.dispose();
    _sellingPrice.dispose();
    super.dispose();
  }

  double? get _purchase => parseAmount(_purchasePrice.text);
  double? get _selling => parseAmount(_sellingPrice.text);

  String? _validateSelling(String? value) {
    final selling = parseAmount(value);
    final purchase = _purchase;
    if (selling == null) return 'Saisissez le prix de vente.';
    if (purchase != null && selling < purchase) {
      return 'Le prix de vente doit être supérieur ou égal au prix d\'achat (${Formats.money(purchase)}).';
    }
    return null;
  }

  String _categoryName(int? id) {
    if (id == null) return 'Aucune';
    final category = _categories.where((item) => item.id == id).firstOrNull;
    return category?.label ?? (_product?.category?.id == id ? Formats.capitalize(_product!.category!.name) : '—');
  }

  Future<void> _addCategory() async {
    final category = await showCategoryDialog(context);
    if (category == null || !mounted) return;
    final categories = await context.read<CategoriesRepository>().active(refresh: true);
    setState(() {
      _categories = categories;
      _categoryId = category.id;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return Notify.warning(context, 'Corrigez les champs signalés.');
    }
    final repository = context.read<ProductsRepository>();
    final data = {
      'reference': _reference.text.trim(),
      'name': _name.text.trim(),
      'category_id': _categoryId,
      'purchase_price': _purchase,
      'selling_price': _selling,
    };
    final existing = _product;
    Product? saved;
    if (existing == null) {
      saved = await submitToApi(() => repository.create(data));
    } else {
      final changes = <String, Object?>{};
      final diff = <FieldChange>[];
      if (data['reference'].toString().toUpperCase() != existing.reference.toUpperCase()) {
        changes['reference'] = data['reference'];
        diff.add(FieldChange('Référence', existing.reference.toUpperCase(), '${data['reference']}'.toUpperCase()));
      }
      if (data['name'].toString().toUpperCase() != existing.name.toUpperCase()) {
        changes['name'] = data['name'];
        diff.add(FieldChange('Nom', existing.label, '${data['name']}'));
      }
      if (_categoryId != existing.category?.id) {
        changes['category_id'] = _categoryId;
        diff.add(FieldChange('Catégorie', _categoryName(existing.category?.id), _categoryName(_categoryId)));
      }
      if (_purchase != existing.purchasePrice) {
        changes['purchase_price'] = _purchase;
        diff.add(FieldChange('Prix d\'achat', Formats.money(existing.purchasePrice), Formats.money(_purchase)));
      }
      if (_selling != existing.sellingPrice) {
        changes['selling_price'] = _selling;
        diff.add(FieldChange('Prix de vente', Formats.money(existing.sellingPrice), Formats.money(_selling)));
      }
      if (diff.isEmpty) {
        Notify.info(context, 'Aucune modification à enregistrer.');
        return;
      }
      final confirmed = await showConfirmation(
        context,
        title: 'Enregistrer les modifications ?',
        message: 'Les ventes déjà enregistrées gardent leurs prix.',
        changes: diff,
        confirmLabel: 'Enregistrer',
      );
      if (!confirmed || !mounted) return;
      saved = await submitToApi(() => repository.update(existing.id, changes));
    }
    if (saved == null || !mounted) return;
    Notify.success(context, existing == null ? 'Produit créé (stock à 0 dans le Stock Local).' : 'Produit modifié.');
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().requireUser;
    return DetailPage(
      title: _isEdit ? 'Modifier le produit' : 'Nouveau produit',
      maxWidth: Sizes.formMaxWidth,
      child: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: errorMessageOf(snapshot.error),
              onRetry: () => setState(() {
                _ready = _load();
              }),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) return const LoadingState(lines: 4);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(Gaps.lg),
              children: [
                SectionCard(
                  title: 'Informations',
                  icon: Icons.inventory_2_outlined,
                  child: Column(
                    children: [
                      AppTextField(
                        label: 'Référence',
                        controller: _reference,
                        required: true,
                        errorText: errorFor('reference'),
                        validator: Validators.reference,
                        helper: 'Lettres, chiffres et . _ / - (ex. P-001)',
                      ),
                      const SizedBox(height: Gaps.md),
                      AppTextField(
                        label: 'Nom du produit',
                        controller: _name,
                        required: true,
                        errorText: errorFor('name'),
                        validator: Validators.text(required: true, min: 2, max: 200),
                      ),
                      const SizedBox(height: Gaps.md),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              key: ValueKey('category-$_categoryId-${_categories.length}'),
                              initialValue: _categories.any((item) => item.id == _categoryId) ? _categoryId : null,
                              isExpanded: true,
                              decoration: InputDecoration(labelText: 'Catégorie', errorText: errorFor('category_id')),
                              items: [
                                const DropdownMenuItem<int?>(value: null, child: Text('Aucune')),
                                for (final category in _categories)
                                  DropdownMenuItem<int?>(value: category.id, child: Text(category.label)),
                              ],
                              onChanged: (value) => setState(() => _categoryId = value),
                            ),
                          ),
                          if (user.can(Perm.productCreate)) ...[
                            const SizedBox(width: Gaps.sm),
                            IconButton.outlined(
                              tooltip: 'Nouvelle catégorie',
                              onPressed: _addCategory,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gaps.lg),
                SectionCard(
                  title: 'Prix',
                  icon: Icons.sell_outlined,
                  child: Column(
                    children: [
                      MoneyField(
                        label: 'Prix d\'achat (prix de stock)',
                        controller: _purchasePrice,
                        required: true,
                        errorText: errorFor('purchase_price'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: Gaps.md),
                      MoneyField(
                        label: 'Prix de vente',
                        controller: _sellingPrice,
                        required: true,
                        errorText: errorFor('selling_price'),
                        validator: _validateSelling,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: Gaps.md),
                      _MarginPreview(purchase: _purchase, selling: _selling),
                    ],
                  ),
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: Gaps.md),
                  Text(
                    'Le produit est ajouté au Stock Local avec une quantité de 0. '
                    'Faites ensuite une entrée de stock pour l\'approvisionner.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: Gaps.xl),
                AppButton(
                  label: _isEdit ? 'Enregistrer les modifications' : 'Créer le produit',
                  icon: Icons.check,
                  expand: true,
                  onPressed: _save,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MarginPreview extends StatelessWidget {
  const _MarginPreview({required this.purchase, required this.selling});

  final double? purchase;
  final double? selling;

  @override
  Widget build(BuildContext context) {
    final purchase = this.purchase;
    final selling = this.selling;
    if (purchase == null || selling == null) return const SizedBox.shrink();
    final margin = selling - purchase;
    final invalid = margin < 0;
    final percent = purchase > 0 ? ' (${(margin / purchase * 100).toStringAsFixed(1).replaceAll('.', ',')} %)' : '';
    final color = invalid ? AppColors.danger : (margin > 0 ? AppColors.success : AppColors.warning);
    return Container(
      padding: const EdgeInsets.all(Gaps.md),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.sm)),
      child: Row(
        children: [
          Icon(invalid ? Icons.error_outline : Icons.trending_up, color: color, size: 20),
          const SizedBox(width: Gaps.sm),
          Expanded(
            child: Text(
              invalid
                  ? 'Prix de vente inférieur au prix d\'achat : non autorisé.'
                  : 'Marge unitaire : ${Formats.money(margin)}$percent',
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
