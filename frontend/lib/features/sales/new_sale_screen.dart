import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/navigation.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/models/refs.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/store_selector.dart';
import '../invoices/invoice_actions.dart';
import '../stock/stock_models.dart';
import '../stock/stock_repository.dart';
import '../stores/stores_repository.dart';
import 'cart_controller.dart';
import 'new_sale_panels.dart';
import 'sale_models.dart';
import 'sales_repository.dart';

/// Nouvelle vente.
///
/// Mobile : étapes (Produits → Client → Paiement → Résumé).
/// Grand écran : produits à gauche, panier et paiement à droite.
/// La vente n'est envoyée qu'une seule fois, après la confirmation de l'utilisateur.
class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late final CartController _cart = context.read<CartController>();
  late final PagedController<StockLine> _catalog = PagedController(
    (query) => context.read<StockRepository>().lines(query),
    filters: {'sort': 'name'},
  );
  int _step = 0;
  Sale? _completed;
  bool _storeReady = false;

  /// Confirmation ouverte ou envoi en cours : un second appui est ignoré (pas de double vente).
  bool _confirming = false;
  bool _submitting = false;

  static const _steps = ['Produits', 'Client', 'Paiement', 'Résumé'];

  @override
  void initState() {
    super.initState();
    // Après la première image : le panier (partagé) ne doit pas notifier pendant la construction.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initStore());
  }

  @override
  void dispose() {
    _catalog.dispose();
    super.dispose();
  }

  /// Magasin de la vente : celui du vendeur, ou le Stock Local par défaut pour l'administrateur.
  Future<void> _initStore() async {
    if (!_user.canChooseStore) {
      if (_user.store != null && _cart.store?.id != _user.store!.id) _cart.setStore(_user.store);
    } else if (_cart.store == null) {
      final stores = await context.read<StoresRepository>().active();
      final central = stores.where((store) => store.isCentral).firstOrNull;
      if (central != null) _cart.setStore(central.ref);
    }
    if (!mounted) return;
    setState(() => _storeReady = true);
    if (_cart.store != null) await _catalog.setFilter('store_id', _cart.store!.id);
  }

  Future<void> _changeStore(StoreRef? store) async {
    if (store == null || store.id == _cart.store?.id) return;
    if (!_cart.isEmpty) {
      final confirmed = await showConfirmation(
        context,
        title: 'Changer de magasin ?',
        message: 'Le panier sera vidé : les quantités disponibles dépendent du magasin.',
        changes: [FieldChange('Magasin', _cart.store?.label ?? '—', store.label)],
        type: ConfirmationType.warning,
      );
      if (!confirmed) return;
    }
    _cart.setStore(store);
    await _catalog.setFilter('store_id', store.id);
  }

  bool _stepValid(int step) => switch (step) {
    0 => _cart.cartErrors.isEmpty,
    1 => _cart.customer != null,
    2 => _cart.discountErrors.isEmpty && _cart.paymentErrors.isEmpty,
    _ => _cart.isReady,
  };

  Future<void> _submit() async {
    if (_confirming || _submitting) return;
    final errors = _cart.allErrors;
    if (errors.isNotEmpty) return Notify.warning(context, errors.first);
    final store = _cart.store!;
    _confirming = true;
    final confirmed = await showConfirmation(
      context,
      title: 'Valider la vente ?',
      content: SaleConfirmationSummary(cart: _cart, storeLabel: store.label),
      confirmLabel: 'Valider la vente',
      type: _cart.hasDebt ? ConfirmationType.warning : ConfirmationType.normal,
    );
    _confirming = false;
    if (!confirmed || !mounted) return;
    setState(() => _submitting = true);
    try {
      final sale = await context.read<SalesRepository>().create(_cart.toNewSale(includeStore: _user.canChooseStore));
      if (!mounted) return;
      _cart.clear();
      setState(() {
        _completed = sale;
        _step = 0;
      });
      await _catalog.refresh();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'CASH_REGISTER_CLOSED') {
        setState(() => _submitting = false);
        return _cashClosed(error);
      }
      Notify.error(context, error);
      if (error.code == 'INSUFFICIENT_STOCK') await _catalog.refresh();
    } finally {
      if (mounted && _submitting) setState(() => _submitting = false);
    }
  }

  Future<void> _cashClosed(ApiException error) async {
    final openCash = await showConfirmation(
      context,
      title: 'Caisse fermée',
      message:
          '${error.message}\nUn paiement en espèces nécessite une caisse ouverte dans ce magasin. '
          'Ouvrez la caisse ou choisissez un autre mode de paiement.',
      confirmLabel: _user.can(Perm.cashOpen) ? 'Ouvrir la caisse' : 'Compris',
      type: ConfirmationType.warning,
    );
    if (openCash && _user.can(Perm.cashOpen) && mounted) context.push(Routes.cash);
  }

  Future<void> _clearCart() async {
    final confirmed = await showConfirmation(
      context,
      title: 'Vider le panier ?',
      message: 'Les produits, le client et le paiement saisis seront effacés.',
      confirmLabel: 'Vider',
      type: ConfirmationType.danger,
    );
    if (!confirmed) return;
    _cart.clear();
    setState(() => _step = 0);
  }

  /// Affiché dans l'onglet « Nouvelle vente » de l'écran Ventes (le titre est celui de l'écran).
  @override
  Widget build(BuildContext context) {
    final completed = _completed;
    if (completed != null) {
      return _SaleSuccess(sale: completed, onNewSale: () => setState(() => _completed = null));
    }
    if (!_user.canChooseStore && _user.store == null) {
      return const EmptyState(
        title: 'Aucun magasin affecté',
        message: 'Demandez à un administrateur de vous affecter à un magasin pour vendre.',
        icon: Icons.storefront_outlined,
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListenableBuilder(
      listenable: _cart,
      builder: (context, _) => Scaffold(
        body: !_storeReady ? const LoadingState(lines: 4) : (wide ? _wideLayout() : _stepsLayout()),
        bottomNavigationBar: wide || !_storeReady ? null : _bottomBar(),
      ),
    );
  }

  Widget _storeHeader() {
    final store = _cart.store;
    final selector = _user.canChooseStore
        ? StoreSelector(value: store?.id, label: 'Magasin de la vente', onChanged: (value) => _changeStore(value?.ref))
        : InfoRow(label: 'Magasin', value: store?.label ?? '—');
    return Row(
      children: [
        Expanded(child: selector),
        if (!_cart.isEmpty) ...[
          const SizedBox(width: Gaps.sm),
          IconButton(
            tooltip: 'Vider le panier',
            onPressed: _clearCart,
            icon: const Icon(Icons.remove_shopping_cart_outlined, color: AppColors.danger),
          ),
        ],
      ],
    );
  }

  // --- Grand écran -------------------------------------------------------------------------------

  Widget _wideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.lg, Gaps.sm, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _storeHeader(),
                const SizedBox(height: Gaps.md),
                Expanded(child: ProductCatalog(controller: _catalog)),
              ],
            ),
          ),
        ),
        SizedBox(
          width: context.isDesktop ? 460 : 400,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gaps.sm, Gaps.lg, Gaps.lg, Gaps.xl),
            children: [
              SectionCard(
                title: 'Panier (${_cart.itemCount})',
                icon: Icons.shopping_cart_outlined,
                child: const CartPanel(),
              ),
              const SizedBox(height: Gaps.md),
              const SectionCard(title: 'Client', icon: Icons.person_outline, child: CustomerPanel()),
              if (_user.can(Perm.saleDiscount)) ...[
                const SizedBox(height: Gaps.md),
                const SectionCard(title: 'Remise', icon: Icons.percent, child: DiscountPanel()),
              ],
              const SizedBox(height: Gaps.md),
              const SectionCard(title: 'Paiement', icon: Icons.payments_outlined, child: PaymentPanel()),
              const SizedBox(height: Gaps.md),
              SectionCard(
                title: 'Résumé',
                icon: Icons.receipt_outlined,
                child: SaleTotals(cart: _cart),
              ),
              const SizedBox(height: Gaps.lg),
              _ValidateButton(enabled: !_cart.isEmpty, busy: _submitting, onPressed: _submit),
            ],
          ),
        ),
      ],
    );
  }

  // --- Mobile : étapes --------------------------------------------------------------------------------

  Widget _stepsLayout() {
    final content = switch (_step) {
      0 => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _storeHeader(),
          const SizedBox(height: Gaps.md),
          if (!_cart.isEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Panier : ${_cart.itemCount} article${_cart.itemCount > 1 ? 's' : ''}'),
              subtitle: Text(Formats.money(_cart.subtotal)),
              children: const [CartPanel()],
            ),
          Expanded(child: ProductCatalog(controller: _catalog)),
        ],
      ),
      1 => const SingleChildScrollView(
        child: SectionCard(title: 'Client', icon: Icons.person_outline, child: CustomerPanel()),
      ),
      2 => SingleChildScrollView(
        child: Column(
          children: [
            if (_user.can(Perm.saleDiscount)) ...[
              const SectionCard(title: 'Remise', icon: Icons.percent, child: DiscountPanel()),
              const SizedBox(height: Gaps.md),
            ],
            const SectionCard(title: 'Paiement', icon: Icons.payments_outlined, child: PaymentPanel()),
          ],
        ),
      ),
      _ => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionCard(title: 'Panier', icon: Icons.shopping_cart_outlined, child: CartPanel()),
            const SizedBox(height: Gaps.md),
            SectionCard(
              title: 'Résumé',
              icon: Icons.receipt_outlined,
              child: SaleConfirmationSummary(cart: _cart, storeLabel: _cart.store?.label ?? '—'),
            ),
            for (final error in _cart.allErrors)
              Padding(
                padding: const EdgeInsets.only(top: Gaps.xs),
                child: Text('• $error', style: const TextStyle(color: AppColors.danger)),
              ),
          ],
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepIndicator(
          steps: _steps,
          current: _step,
          onTap: (index) {
            if (index < _step || _canReach(index)) setState(() => _step = index);
          },
        ),
        Expanded(
          child: Padding(padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.lg, 0), child: content),
        ),
      ],
    );
  }

  bool _canReach(int step) {
    for (var index = 0; index < step; index++) {
      if (!_stepValid(index)) return false;
    }
    return true;
  }

  Widget _bottomBar() {
    final last = _step == _steps.length - 1;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.lg, Gaps.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_cart.itemCount} article${_cart.itemCount > 1 ? 's' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(Formats.money(_cart.total), style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ),
                if (_step > 0) TextButton(onPressed: () => setState(() => _step--), child: const Text('Retour')),
                if (!last) ...[
                  const SizedBox(width: Gaps.sm),
                  FilledButton(
                    onPressed: _stepValid(_step) ? () => setState(() => _step++) : null,
                    child: const Text('Suivant'),
                  ),
                ],
              ],
            ),
            if (last) ...[
              const SizedBox(height: Gaps.sm),
              _ValidateButton(enabled: _cart.isReady, busy: _submitting, onPressed: _submit),
            ],
          ],
        ),
      ),
    );
  }
}

class _ValidateButton extends StatelessWidget {
  const _ValidateButton({required this.enabled, required this.busy, required this.onPressed});

  final bool enabled;
  final bool busy;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled && !busy ? onPressed : null,
        style: FilledButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
        icon: busy
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check, size: 20),
        label: Text(busy ? 'Enregistrement...' : 'Valider la vente'),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.steps, required this.current, required this.onTap});

  final List<String> steps;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.md, 0),
      child: Row(
        children: [
          for (final (index, label) in steps.indexed)
            Expanded(
              child: InkWell(
                onTap: () => onTap(index),
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gaps.sm),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: index <= current
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHigh,
                        child: index < current
                            ? Icon(Icons.check, size: 14, color: theme.colorScheme.onPrimary)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: index <= current
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: index == current ? theme.colorScheme.primary : null,
                          fontWeight: index == current ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Écran de fin de vente : facture, partage, nouvelle vente.
class _SaleSuccess extends StatelessWidget {
  const _SaleSuccess({required this.sale, required this.onNewSale});

  final Sale sale;
  final VoidCallback onNewSale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Gaps.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 72),
              const SizedBox(height: Gaps.md),
              Text('Vente enregistrée', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              Text(sale.number, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: Gaps.xl),
              AppCard(
                child: Column(
                  children: [
                    InfoRow(label: 'Client', value: sale.customer.fullName),
                    InfoRow(label: 'Total', value: Formats.money(sale.total), emphasis: true),
                    InfoRow(label: 'Payé', value: Formats.money(sale.amountPaid)),
                    if (sale.remainingAmount > 0) ...[
                      InfoRow(
                        label: 'Reste à payer',
                        value: Formats.money(sale.remainingAmount),
                        valueStyle: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                      ),
                      InfoRow(label: 'Échéance', value: Formats.date(sale.paymentDueDate)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Gaps.xl),
              FilledButton.icon(
                onPressed: () => context.push('/sales/${sale.id}/invoice'),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Voir la facture'),
              ),
              const SizedBox(height: Gaps.sm),
              AppButton(
                label: 'Partager la facture (PDF)',
                icon: Icons.share_outlined,
                variant: AppButtonVariant.secondary,
                expand: true,
                onPressed: () => shareInvoice(context, sale.id),
              ),
              const SizedBox(height: Gaps.sm),
              OutlinedButton.icon(
                onPressed: () => context.push('/sales/${sale.id}'),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Détail de la vente'),
              ),
              const SizedBox(height: Gaps.lg),
              TextButton.icon(onPressed: onNewSale, icon: const Icon(Icons.add), label: const Text('Nouvelle vente')),
            ],
          ),
        ),
      ),
    );
  }
}
