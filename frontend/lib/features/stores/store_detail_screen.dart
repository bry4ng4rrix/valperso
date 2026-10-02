import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/status_badge.dart';
import '../stock/stock_models.dart';
import '../stock/stock_repository.dart';
import '../users/user_models.dart';
import 'store_models.dart';
import 'stores_repository.dart';

/// Fiche magasin : coordonnées, valeur du stock, employés, actions.
class StoreDetailScreen extends StatefulWidget {
  const StoreDetailScreen({super.key, required this.storeId});

  final int storeId;

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen> {
  late Future<Store> _future = context.read<StoresRepository>().get(widget.storeId);
  Future<Paged<AppUser>>? _employees;
  Future<StockValueReport>? _value;

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  void _loadExtras() {
    final user = context.read<SessionController>().requireUser;
    if (user.can(Perm.userView)) {
      _employees = context.read<StoresRepository>().employees(widget.storeId, const PageQuery(pageSize: 50));
    }
    if (user.can(Perm.reportView)) _value = context.read<StockRepository>().value(storeId: widget.storeId);
  }

  void _reload() => setState(() {
    _future = context.read<StoresRepository>().get(widget.storeId);
    _loadExtras();
  });

  Future<void> _toggleActive(Store store) async {
    final deactivate = store.isActive;
    final confirmed = await showConfirmation(
      context,
      title: deactivate ? 'Désactiver ${store.label} ?' : 'Réactiver ${store.label} ?',
      message: deactivate
          ? 'Plus aucune vente ni aucun transfert ne sera possible dans ce magasin. Son historique est conservé.'
          : 'Le magasin pourra de nouveau vendre et recevoir des transferts.',
      changes: [FieldChange('Statut', deactivate ? 'Actif' : 'Inactif', deactivate ? 'Inactif' : 'Actif')],
      confirmLabel: deactivate ? 'Désactiver' : 'Réactiver',
      type: deactivate ? ConfirmationType.danger : ConfirmationType.normal,
    );
    if (!confirmed || !mounted) return;
    final repository = context.read<StoresRepository>();
    final done = await runApiAction(
      context,
      () => deactivate ? repository.deactivate(store.id) : repository.update(store.id, {'is_active': true}),
      success: deactivate ? 'Magasin désactivé.' : 'Magasin réactivé.',
    );
    if (done) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().requireUser;
    return FutureBuilder<Store>(
      future: _future,
      builder: (context, snapshot) {
        final store = snapshot.data;
        return DetailPage(
          title: store?.label ?? 'Magasin',
          maxWidth: 860,
          actions: [
            if (store != null && user.can(Perm.storeUpdate))
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  await context.push('/stores/${store.id}/edit');
                  if (mounted) _reload();
                },
              ),
            if (store != null && !store.isCentral && user.can(store.isActive ? Perm.storeDelete : Perm.storeUpdate))
              IconButton(
                tooltip: store.isActive ? 'Désactiver' : 'Réactiver',
                icon: Icon(
                  store.isActive ? Icons.block : Icons.check_circle_outline,
                  color: store.isActive ? AppColors.danger : null,
                ),
                onPressed: () => _toggleActive(store),
              ),
          ],
          child: snapshot.hasError
              ? ErrorState(message: errorMessageOf(snapshot.error), onRetry: _reload)
              : store == null
              ? const LoadingState(lines: 3)
              : ListView(
                  padding: const EdgeInsets.all(Gaps.lg),
                  children: [
                    SectionCard(
                      title: 'Informations',
                      icon: store.isCentral ? Icons.warehouse : Icons.storefront,
                      trailing: store.isCentral
                          ? const StatusBadge('Stock central', tone: BadgeTone.primary)
                          : Badges.active(store.isActive),
                      child: Column(
                        children: [
                          InfoRow(label: 'Nom', value: store.label),
                          InfoRow(label: 'Adresse', value: Formats.title(store.address ?? '—')),
                          InfoRow(label: 'Téléphone', value: store.phone ?? '—'),
                        ],
                      ),
                    ),
                    if (_value != null) ...[
                      const SizedBox(height: Gaps.lg),
                      FutureBuilder<StockValueReport>(
                        future: _value,
                        builder: (context, snapshot) {
                          final total = snapshot.data?.total;
                          return SectionCard(
                            title: 'Stock du magasin',
                            icon: Icons.inventory_outlined,
                            trailing: TextButton(
                              onPressed: () => context.go('/stock'),
                              child: const Text('Voir le stock'),
                            ),
                            child: total == null
                                ? const LinearProgressIndicator()
                                : Column(
                                    children: [
                                      InfoRow(label: 'Unités en stock', value: Formats.quantity(total.quantity)),
                                      InfoRow(label: 'Valeur d\'achat', value: Formats.money(total.purchaseValue)),
                                      InfoRow(label: 'Valeur de vente', value: Formats.money(total.saleValue)),
                                      InfoRow(label: 'Bénéfice potentiel', value: Formats.money(total.potentialProfit)),
                                    ],
                                  ),
                          );
                        },
                      ),
                    ],
                    if (_employees != null) ...[
                      const SizedBox(height: Gaps.lg),
                      FutureBuilder<Paged<AppUser>>(
                        future: _employees,
                        builder: (context, snapshot) {
                          final employees = snapshot.data?.items;
                          return SectionCard(
                            title: 'Employés',
                            icon: Icons.badge_outlined,
                            child: employees == null
                                ? const LinearProgressIndicator()
                                : employees.isEmpty
                                ? const Text('Aucun employé. Affectez un vendeur depuis l\'écran Utilisateurs.')
                                : Column(
                                    children: [
                                      for (final employee in employees)
                                        ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(employee.fullName),
                                          subtitle: Text(employee.username.toLowerCase()),
                                          trailing: Badges.role(employee.role.name),
                                          onTap: () => context.push('/users/${employee.id}'),
                                        ),
                                    ],
                                  ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}
