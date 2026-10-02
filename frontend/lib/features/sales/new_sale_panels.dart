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
import '../stock/stock_models.dart';
import 'cart_controller.dart';
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
          hint: 'Rechercher un produit (nom, référence, catégorie, prix)',
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
    if (cart.isEmpty) {
      return const Padding(padding: EdgeInsets.all(Gaps.md), child: Text('Le panier est vide. Ajoutez des produits.'));
    }
    return Column(
      children: [
        for (final line in cart.lines)
          _CartLineTile(key: ValueKey(line.product.id), line: line, onEditQuantity: () => _editQuantity(context, line)),
      ],
    );
  }
}

/// Ligne du panier : produit, quantité, et la description de l'article (taille, couleur...).
class _CartLineTile extends StatefulWidget {
  const _CartLineTile({super.key, required this.line, required this.onEditQuantity});

  final CartLine line;
  final VoidCallback onEditQuantity;

  @override
  State<_CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends State<_CartLineTile> {
  late final TextEditingController _description = TextEditingController(text: widget.line.description);

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartController>();
    final theme = Theme.of(context);
    final line = widget.line;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                onTap: widget.onEditQuantity,
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
          const SizedBox(height: Gaps.xs),
          TextField(
            controller: _description,
            inputFormatters: [LengthLimitingTextInputFormatter(255)],
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Description (taille, couleur...)',
              prefixIcon: Icon(Icons.notes, size: 20),
            ),
            onChanged: (text) => cart.setDescription(line.product.id, text),
          ),
        ],
      ),
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

// --- Paiement ---------------------------------------------------------------------------------------------

/// « Payé » (tout est payé maintenant) ou « Dette (avance) ». Il n'y a pas de mode de paiement à choisir.
///
/// Dette (avance) : le champ est pré-rempli avec le prix total ; on y laisse ce qui est payé
/// maintenant (l'avance). Champ vide = dette sans avance : tout le total reste à payer.
class PaymentPanel extends StatefulWidget {
  const PaymentPanel({super.key});

  @override
  State<PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<PaymentPanel> {
  late final TextEditingController _paid;

  @override
  void initState() {
    super.initState();
    final cart = context.read<CartController>();
    _paid = TextEditingController(text: cart.payInFull ? '' : _format(cart.advanceAmount));
  }

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  String _format(double amount) => amount > 0 ? Formats.amount(amount) : '';

  void _select(CartController cart, bool withDebt) {
    if (withDebt) {
      // Pré-rempli avec le prix total initial : on le remplace par le montant payé maintenant.
      _paid.text = _format(cart.total);
      cart.setPayment(inFull: false, advance: cart.total);
    } else {
      _paid.clear();
      cart.setPayment(inFull: true, advance: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final theme = Theme.of(context);
    final withDebt = !cart.payInFull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.check_circle_outline), label: Text('Payé')),
            ButtonSegment(value: true, icon: Icon(Icons.schedule), label: Text('Dette (avance)')),
          ],
          selected: {withDebt},
          onSelectionChanged: (selection) => _select(cart, selection.first),
        ),
        if (withDebt) ...[
          const SizedBox(height: Gaps.md),
          MoneyField(
            label: 'Payé maintenant',
            controller: _paid,
            helper: cart.isDebtWithoutAdvance
                ? 'Vide : dette sans avance, tout le total reste à payer.'
                : 'Total ${Formats.money(cart.total)} · vide = dette sans avance',
            validator: (value) {
              final amount = parseAmount(value) ?? 0;
              return amount > cart.total ? 'Le montant payé ne peut pas dépasser le total.' : null;
            },
            onChanged: (text) => cart.setPayment(advance: parseAmount(text) ?? 0),
          ),
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
                    cart.isDebtWithoutAdvance
                        ? 'Dette sans avance : reste à payer ${Formats.money(cart.remaining)}'
                        : 'Avance ${Formats.money(cart.amountPaid)} — reste à payer ${Formats.money(cart.remaining)}',
                    style: theme.textTheme.titleSmall?.copyWith(color: AppColors.warning),
                  ),
                  const SizedBox(height: Gaps.xs),
                  const Text('Les dates de remboursement et le téléphone du client sont obligatoires.'),
                ],
              ),
            ),
            const SizedBox(height: Gaps.md),
            const InstallmentsEditor(),
          ],
        ],
        if (!cart.isEmpty)
          for (final error in cart.paymentErrors)
            Padding(
              padding: const EdgeInsets.only(top: Gaps.xs),
              child: Text('• $error', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger)),
            ),
      ],
    );
  }
}

/// Dates de remboursement du reste à payer : une ligne par date, avec son montant.
/// Ajouter ou retirer une date répartit le reste également ; les montants restent modifiables.
class InstallmentsEditor extends StatelessWidget {
  const InstallmentsEditor({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final theme = Theme.of(context);
    final installments = cart.installments;
    final balanced = cart.installmentsTotal == cart.remaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Dates de remboursement', style: theme.textTheme.titleSmall),
        const SizedBox(height: Gaps.sm),
        for (final (index, installment) in installments.indexed)
          InstallmentRow(
            key: ValueKey(installment.id),
            number: index + 1,
            installment: installment,
            // Une seule date : elle couvre tout le reste à payer.
            amountEditable: installments.length > 1,
            canRemove: installments.length > 1,
          ),
        Wrap(
          spacing: Gaps.sm,
          runSpacing: Gaps.xs,
          children: [
            OutlinedButton.icon(
              onPressed: installments.length < 36 ? cart.addInstallment : null,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une date'),
            ),
            if (installments.length > 1)
              TextButton.icon(
                onPressed: cart.splitInstallmentsEvenly,
                icon: const Icon(Icons.balance),
                label: const Text('Répartir également'),
              ),
          ],
        ),
        if (installments.length > 1) ...[
          const SizedBox(height: Gaps.xs),
          Text(
            'Total prévu : ${Formats.money(cart.installmentsTotal)} sur ${Formats.money(cart.remaining)}',
            style: theme.textTheme.bodySmall?.copyWith(color: balanced ? AppColors.success : AppColors.danger),
          ),
        ],
      ],
    );
  }
}

/// Une date de remboursement : la date à choisir, le montant, et le bouton pour la retirer.
class InstallmentRow extends StatefulWidget {
  const InstallmentRow({
    super.key,
    required this.number,
    required this.installment,
    required this.amountEditable,
    required this.canRemove,
  });

  final int number;
  final CartInstallment installment;
  final bool amountEditable;
  final bool canRemove;

  @override
  State<InstallmentRow> createState() => _InstallmentRowState();
}

class _InstallmentRowState extends State<InstallmentRow> {
  late final TextEditingController _amount = TextEditingController(text: _format(widget.installment.amount));

  String _format(double amount) => amount > 0 ? Formats.amount(amount) : '';

  @override
  void didUpdateWidget(covariant InstallmentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Montant changé par la répartition (et non par la saisie) : le champ suit.
    if ((parseAmount(_amount.text) ?? 0) != widget.installment.amount) {
      _amount.text = _format(widget.installment.amount);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate(CartController cart) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = widget.installment.dueDate;
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 1095)),
      initialDate: current != null && !current.isBefore(today) ? current : today.add(const Duration(days: 7)),
      helpText: 'Date du remboursement ${widget.number}',
    );
    if (picked != null) cart.setInstallmentDate(widget.installment.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartController>();
    final date = widget.installment.dueDate;
    final dateButton = OutlinedButton.icon(
      onPressed: () => _pickDate(cart),
      icon: const Icon(Icons.event),
      label: Text(date == null ? 'Choisir la date' : Formats.date(date), overflow: TextOverflow.ellipsis),
    );
    final amount = MoneyField(
      label: 'Montant',
      controller: _amount,
      enabled: widget.amountEditable,
      onChanged: (text) => cart.setInstallmentAmount(widget.installment.id, parseAmount(text) ?? 0),
    );
    final remove = IconButton(
      tooltip: 'Retirer cette date',
      onPressed: widget.canRemove ? () => cart.removeInstallment(widget.installment.id) : null,
      icon: const Icon(Icons.delete_outline),
    );
    final theme = Theme.of(context);
    final number = Text('${widget.number}.', style: theme.textTheme.titleSmall);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 380) {
            return Row(
              children: [
                number,
                const SizedBox(width: Gaps.sm),
                Expanded(flex: 5, child: dateButton),
                const SizedBox(width: Gaps.sm),
                Expanded(flex: 6, child: amount),
                remove,
              ],
            );
          }
          // Téléphone : chaque remboursement dans son cadre, la date au-dessus du montant.
          return Container(
            padding: const EdgeInsets.fromLTRB(Gaps.sm, Gaps.sm, Gaps.xs, Gaps.sm),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    number,
                    const SizedBox(width: Gaps.sm),
                    Expanded(child: dateButton),
                    remove,
                  ],
                ),
                const SizedBox(height: Gaps.sm),
                Padding(
                  padding: const EdgeInsets.only(right: Gaps.sm),
                  child: amount,
                ),
              ],
            ),
          );
        },
      ),
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
          InfoRow(
            label: 'Remboursements',
            value: [
              for (final installment in cart.sortedInstallments)
                '${Formats.date(installment.dueDate)} : ${Formats.money(installment.amount)}',
            ].join('\n'),
          ),
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
    final payment = cart.payInFull
        ? 'Payé'
        : cart.isDebtWithoutAdvance
        ? 'Dette sans avance (rien payé maintenant)'
        : 'Dette avec avance de ${Formats.money(cart.amountPaid)}';
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
                            if (line.description.isNotEmpty) Text(line.description, style: theme.textTheme.bodySmall),
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
