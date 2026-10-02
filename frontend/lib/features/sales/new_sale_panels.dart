import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged_controller.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/refs.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/pagination_controls.dart';
import '../../shared/widgets/product_avatar.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/states.dart';
import '../customers/customers_repository.dart';
import '../payments/payment_models.dart';
import '../stock/stock_models.dart';
import 'cart_controller.dart';
import 'sale_models.dart';
import '../../core/widgets/app_dialog.dart';

// --- Produits ---------------------------------------------------------------------------------------

/// Produits du magasin de la vente, avec leur prix et la quantité disponible.
class ProductCatalog extends StatelessWidget {
  const ProductCatalog({super.key, required this.controller});

  final PagedController<StockLine> controller;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          hint: 'Rechercher un produit (nom, référence)',
          initialValue: controller.filter('search') as String?,
          onChanged: (value) => controller.setFilter('search', value),
        ),
        const SizedBox(height: Gaps.sm),
        Expanded(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              if (controller.filter('store_id') == null) {
                return const EmptyState(title: 'Choisissez le magasin de la vente', icon: Icons.storefront_outlined);
              }
              if (!controller.hasLoaded || (controller.isLoading && controller.items.isEmpty)) {
                return const LoadingState(lines: 5);
              }
              if (controller.error != null && controller.items.isEmpty) {
                return ErrorState(message: controller.error!.message, onRetry: controller.refresh);
              }
              if (controller.items.isEmpty) {
                return const EmptyState(title: 'Aucun produit', message: 'Modifiez la recherche.');
              }
              return Column(
                children: [
                  if (controller.isLoading) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: Gaps.lg),
                      itemCount: controller.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Gaps.sm),
                      itemBuilder: (context, index) => _CatalogTile(line: controller.items[index], cart: cart),
                    ),
                  ),
                  PaginationControls(
                    page: controller.page,
                    pages: controller.pages,
                    total: controller.total,
                    isLoading: controller.isLoading,
                    onPageSelected: controller.load,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.line, required this.cart});

  final StockLine line;
  final CartController cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inCart = cart.quantityOf(line.product.id);
    final available = line.quantity - inCart;
    final canAdd = line.product.isActive && available > 0;
    return AppCard(
      padding: const EdgeInsets.all(Gaps.sm),
      onTap: canAdd ? () => cart.add(line.product, available: line.quantity) : null,
      child: Row(
        children: [
          ProductAvatar(name: line.product.label, imageUrl: line.product.imageUrl, size: 48),
          const SizedBox(width: Gaps.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.label,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${line.product.reference.toUpperCase()} · ${line.quantity > 0 ? '${line.quantity} en stock' : 'Épuisé'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: line.quantity > 0 ? null : AppColors.danger),
                ),
                Text(
                  Formats.money(line.product.sellingPrice),
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
          if (inCart > 0)
            Padding(
              padding: const EdgeInsets.only(right: Gaps.xs),
              child: Badge(
                label: Text('$inCart'),
                backgroundColor: theme.colorScheme.primary,
                textColor: theme.colorScheme.onPrimary,
              ),
            ),
          IconButton.filledTonal(
            tooltip: canAdd ? 'Ajouter au panier' : 'Stock insuffisant',
            onPressed: canAdd ? () => cart.add(line.product, available: line.quantity) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

// --- Panier -------------------------------------------------------------------------------------------

class CartPanel extends StatelessWidget {
  const CartPanel({super.key});

  Future<void> _editQuantity(BuildContext context, CartLine line) async {
    final controller = TextEditingController(text: '${line.quantity}');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AppDialog(
        title: line.product.label,
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Quantité', helperText: 'Disponible : ${line.available}'),
          onSubmitted: (text) => Navigator.of(context).pop(int.tryParse(text)),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(int.tryParse(controller.text)),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && context.mounted) context.read<CartController>().setQuantity(line.product.id, value);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final theme = Theme.of(context);
    if (cart.isEmpty) {
      return const Padding(padding: EdgeInsets.all(Gaps.md), child: Text('Le panier est vide. Ajoutez des produits.'));
    }
    return Column(
      children: [
        for (final line in cart.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: Gaps.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.product.label,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${Formats.money(line.unitPrice)} × ${line.quantity} = ${Formats.money(line.total)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (line.exceedsStock)
                        Text(
                          'Stock disponible : ${line.available}',
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer une unité',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => cart.setQuantity(line.product.id, line.quantity - 1),
                  icon: Icon(line.quantity == 1 ? Icons.delete_outline : Icons.remove),
                ),
                InkWell(
                  onTap: () => _editQuantity(context, line),
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 40),
                    padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.xs),
                    alignment: Alignment.center,
                    child: Text('${line.quantity}', style: theme.textTheme.titleMedium),
                  ),
                ),
                IconButton(
                  tooltip: 'Ajouter une unité',
                  visualDensity: VisualDensity.compact,
                  onPressed: line.quantity < line.available
                      ? () => cart.setQuantity(line.product.id, line.quantity + 1)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// --- Client -------------------------------------------------------------------------------------------

class CustomerPanel extends StatefulWidget {
  const CustomerPanel({super.key});

  @override
  State<CustomerPanel> createState() => _CustomerPanelState();
}

class _CustomerPanelState extends State<CustomerPanel> {
  bool _creating = false;
  Future<List<CustomerRef>>? _results;
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _search(String term) {
    setState(() {
      _results = term.trim().isEmpty ? null : context.read<CustomersRepository>().search(term.trim());
    });
  }

  void _useNewCustomer() {
    if (!_formKey.currentState!.validate()) return;
    context.read<CartController>().setCustomer(
      CartCustomer.create(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: trimOrNull(_phone.text),
      ),
    );
    setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final theme = Theme.of(context);
    final customer = cart.customer;
    if (customer != null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(customer.isNew ? Icons.person_add_alt : Icons.person, color: theme.colorScheme.primary),
        ),
        title: Text(customer.fullName),
        subtitle: Text([customer.phoneNumber ?? 'Pas de téléphone', if (customer.isNew) 'nouveau client'].join(' · ')),
        trailing: TextButton(onPressed: () => cart.setCustomer(null), child: const Text('Changer')),
      );
    }
    if (_creating) {
      return Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Prénom',
              controller: _firstName,
              required: true,
              validator: Validators.text(required: true, max: 100),
            ),
            const SizedBox(height: Gaps.sm),
            AppTextField(
              label: 'Nom',
              controller: _lastName,
              required: true,
              validator: Validators.text(required: true, max: 100),
            ),
            const SizedBox(height: Gaps.sm),
            AppTextField(
              label: 'Téléphone',
              controller: _phone,
              keyboardType: TextInputType.phone,
              validator: Validators.phone,
              helper: 'Obligatoire pour une vente avec avance ou à crédit.',
            ),
            const SizedBox(height: Gaps.md),
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: Gaps.sm,
              overflowSpacing: Gaps.xs,
              children: [
                TextButton(onPressed: () => setState(() => _creating = false), child: const Text('Annuler')),
                FilledButton(onPressed: _useNewCustomer, child: const Text('Utiliser ce client')),
              ],
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(hint: 'Rechercher un client (nom, téléphone)', onChanged: _search),
        if (_results != null)
          FutureBuilder<List<CustomerRef>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Padding(padding: EdgeInsets.all(Gaps.sm), child: Text('Recherche impossible.'));
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final customers = snapshot.data!;
              if (customers.isEmpty) {
                return const Padding(padding: EdgeInsets.all(Gaps.sm), child: Text('Aucun client trouvé.'));
              }
              return Column(
                children: [
                  for (final customer in customers)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(customer.fullName),
                      subtitle: Text(customer.phone ?? 'Pas de téléphone'),
                      onTap: () => cart.setCustomer(CartCustomer.existing(customer)),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: Gaps.sm),
        OutlinedButton.icon(
          onPressed: () => setState(() => _creating = true),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Nouveau client'),
        ),
      ],
    );
  }
}

// --- Remise ---------------------------------------------------------------------------------------------

class DiscountPanel extends StatefulWidget {
  const DiscountPanel({super.key});

  @override
  State<DiscountPanel> createState() => _DiscountPanelState();
}

class _DiscountPanelState extends State<DiscountPanel> {
  late final TextEditingController _value;

  @override
  void initState() {
    super.initState();
    final cart = context.read<CartController>();
    _value = TextEditingController(text: cart.discountValue > 0 ? Formats.amount(cart.discountValue) : '');
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Remise en montant uniquement (pas de pourcentage).
        SegmentedButton<DiscountType>(
          segments: const [
            ButtonSegment(value: DiscountType.none, label: Text('Aucune')),
            ButtonSegment(value: DiscountType.fixed, label: Text('Montant')),
          ],
          selected: {cart.discountType},
          onSelectionChanged: (selection) {
            final type = selection.first;
            if (type == DiscountType.none) _value.clear();
            cart.setDiscount(type, parseAmount(_value.text) ?? 0);
          },
        ),
        if (cart.discountType != DiscountType.none) ...[
          const SizedBox(height: Gaps.md),
          AppTextField(
            label: 'Remise (Ar)',
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ,.]'))],
            errorText: cart.discountErrors.firstOrNull,
            helper: cart.discountAmount > 0 ? 'Remise appliquée : ${Formats.money(cart.discountAmount)}' : null,
            onChanged: (text) => cart.setDiscount(cart.discountType, parseAmount(text) ?? 0),
          ),
        ],
      ],
    );
  }
}

// --- Paiement -------------------------------------------------------------------------------------------

class PaymentPanel extends StatefulWidget {
  const PaymentPanel({super.key});

  @override
  State<PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<PaymentPanel> {
  late final TextEditingController _advance;
  late final TextEditingController _reference;

  @override
  void initState() {
    super.initState();
    final cart = context.read<CartController>();
    _advance = TextEditingController(text: cart.advanceAmount > 0 ? Formats.amount(cart.advanceAmount) : '');
    _reference = TextEditingController(text: cart.paymentReference ?? '');
  }

  @override
  void dispose() {
    _advance.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate(CartController cart) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 730)),
      initialDate: cart.dueDate ?? today.add(const Duration(days: 7)),
      helpText: 'Date d\'échéance du reste à payer',
    );
    if (picked != null) cart.setPayment(due: picked);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final theme = Theme.of(context);
    final credit = cart.paymentMethod == PaymentMethod.credit;
    final errors = cart.paymentErrors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mode de paiement', style: theme.textTheme.labelMedium),
        const SizedBox(height: Gaps.xs),
        Wrap(
          spacing: Gaps.sm,
          runSpacing: Gaps.sm,
          children: [
            for (final method in PaymentMethod.values)
              ChoiceChip(
                label: Text(method == PaymentMethod.credit ? 'Crédit (rien payé)' : method.label),
                selected: cart.paymentMethod == method,
                onSelected: (_) => cart.setPayment(method: method),
              ),
          ],
        ),
        if (!credit) ...[
          const SizedBox(height: Gaps.md),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Paiement complet')),
              ButtonSegment(value: false, label: Text('Avance')),
            ],
            selected: {cart.payInFull},
            onSelectionChanged: (selection) => cart.setPayment(inFull: selection.first),
          ),
          if (!cart.payInFull) ...[
            const SizedBox(height: Gaps.md),
            MoneyField(
              label: 'Montant de l\'avance',
              controller: _advance,
              helper: 'Total : ${Formats.money(cart.total)}',
              onChanged: (text) => cart.setPayment(advance: parseAmount(text) ?? 0),
            ),
          ],
          if (cart.paymentMethod != PaymentMethod.cash) ...[
            const SizedBox(height: Gaps.md),
            AppTextField(
              label: 'Référence du paiement (facultatif)',
              controller: _reference,
              onChanged: (text) => cart.setPayment(reference: text),
            ),
          ],
        ],
        if (cart.hasDebt) ...[
          const SizedBox(height: Gaps.md),
          Container(
            padding: const EdgeInsets.all(Gaps.md),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Reste à payer : ${Formats.money(cart.remaining)}',
                  style: theme.textTheme.titleSmall?.copyWith(color: AppColors.warning),
                ),
                const SizedBox(height: Gaps.xs),
                const Text('Une date d\'échéance et le téléphone du client sont obligatoires.'),
                const SizedBox(height: Gaps.sm),
                OutlinedButton.icon(
                  onPressed: () => _pickDueDate(cart),
                  icon: const Icon(Icons.event),
                  label: Text(
                    cart.dueDate == null ? 'Choisir l\'échéance' : 'Échéance : ${Formats.date(cart.dueDate)}',
                  ),
                ),
              ],
            ),
          ),
        ],
        if (errors.isNotEmpty && (!cart.isEmpty)) ...[
          const SizedBox(height: Gaps.sm),
          for (final error in errors)
            Text('• $error', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger)),
        ],
      ],
    );
  }
}

// --- Résumé -----------------------------------------------------------------------------------------------

/// Montants de la vente (aperçu ; le serveur recalcule tout à l'enregistrement).
class SaleTotals extends StatelessWidget {
  const SaleTotals({super.key, required this.cart, this.compact = false});

  final CartController cart;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) InfoRow(label: 'Articles', value: Formats.quantity(cart.itemCount)),
        InfoRow(label: 'Sous-total', value: Formats.money(cart.subtotal)),
        if (cart.discountAmount > 0) InfoRow(label: 'Remise', value: '- ${Formats.money(cart.discountAmount)}'),
        InfoRow(label: 'Total', value: Formats.money(cart.total), emphasis: true),
        InfoRow(label: 'Payé maintenant', value: Formats.money(cart.amountPaid)),
        if (cart.hasDebt) ...[
          InfoRow(
            label: 'Reste à payer',
            value: Formats.money(cart.remaining),
            valueStyle: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
          ),
          InfoRow(label: 'Échéance', value: Formats.date(cart.dueDate)),
        ],
      ],
    );
  }
}

/// Récapitulatif affiché dans la confirmation, avant l'envoi.
class SaleConfirmationSummary extends StatelessWidget {
  const SaleConfirmationSummary({super.key, required this.cart, required this.storeLabel});

  final CartController cart;
  final String storeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = cart.customer;
    final payment = cart.paymentMethod == PaymentMethod.credit
        ? 'Crédit (rien payé maintenant)'
        : '${cart.paymentMethod.label}${cart.payInFull ? '' : ' — avance'}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoRow(label: 'Magasin', value: storeLabel),
        InfoRow(label: 'Client', value: [customer?.fullName ?? '—', ?customer?.phoneNumber].join('\n')),
        InfoRow(label: 'Paiement', value: payment),
        const SizedBox(height: Gaps.md),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${cart.itemCount} article${cart.itemCount > 1 ? 's' : ''}', style: theme.textTheme.labelMedium),
              const SizedBox(height: Gaps.xs),
              for (final line in cart.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gaps.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(line.product.label, style: theme.textTheme.bodyMedium),
                            Text(
                              '${line.quantity} × ${Formats.money(line.unitPrice)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Gaps.md),
                      Text(Formats.money(line.total), style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Gaps.sm),
        SaleTotals(cart: cart, compact: true),
      ],
    );
  }
}
