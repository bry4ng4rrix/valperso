import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/status_badge.dart';
import 'transfer_models.dart';
import 'transfers_repository.dart';

class TransferDetailScreen extends StatefulWidget {
  const TransferDetailScreen({super.key, required this.transferId});

  final int transferId;

  @override
  State<TransferDetailScreen> createState() => _TransferDetailScreenState();
}

class _TransferDetailScreenState extends State<TransferDetailScreen> {
  late Future<StockTransfer> _future = context.read<TransfersRepository>().get(widget.transferId);

  void _reload() => setState(() {
    _future = context.read<TransfersRepository>().get(widget.transferId);
  });

  Future<void> _cancel(StockTransfer transfer) async {
    final confirmed = await showConfirmation(
      context,
      title: 'Annuler le transfert ${transfer.reference} ?',
      message:
          'Les quantités seront renvoyées de ${transfer.destination.label} vers ${transfer.source.label}. '
          'Impossible si une partie a déjà été vendue ou transférée.',
      content: _ItemsList(items: transfer.items),
      confirmLabel: 'Annuler le transfert',
      cancelLabel: 'Retour',
      type: ConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;
    final done = await runApiAction(
      context,
      () => context.read<TransfersRepository>().cancel(transfer.id),
      success: 'Transfert annulé : le stock a été remis dans ${transfer.source.label}.',
    );
    if (done) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().requireUser;
    return FutureBuilder<StockTransfer>(
      future: _future,
      builder: (context, snapshot) {
        final transfer = snapshot.data;
        return DetailPage(
          title: transfer?.reference ?? 'Transfert',
          maxWidth: 760,
          child: snapshot.hasError
              ? ErrorState(message: errorMessageOf(snapshot.error), onRetry: _reload)
              : transfer == null
              ? const LoadingState(lines: 3)
              : ListView(
                  padding: const EdgeInsets.all(Gaps.lg),
                  children: [
                    SectionCard(
                      title: 'Transfert',
                      icon: Icons.swap_horiz,
                      trailing: Badges.transferStatus(transfer.status),
                      child: Column(
                        children: [
                          InfoRow(label: 'Source', value: transfer.source.label),
                          InfoRow(label: 'Destination', value: transfer.destination.label),
                          InfoRow(label: 'Date', value: Formats.dateTime(transfer.createdAt)),
                          InfoRow(label: 'Créé par', value: transfer.creator.fullName),
                          InfoRow(label: 'Quantité totale', value: Formats.quantity(transfer.totalQuantity)),
                        ],
                      ),
                    ),
                    const SizedBox(height: Gaps.lg),
                    SectionCard(
                      title: 'Produits transférés',
                      icon: Icons.inventory_2_outlined,
                      child: _ItemsList(items: transfer.items),
                    ),
                    if (!transfer.isCancelled && user.can(Perm.transferCancel)) ...[
                      const SizedBox(height: Gaps.xl),
                      AppButton(
                        label: 'Annuler le transfert',
                        icon: Icons.undo,
                        variant: AppButtonVariant.danger,
                        expand: true,
                        onPressed: () => _cancel(transfer),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _ItemsList extends StatelessWidget {
  const _ItemsList({required this.items});

  final List<TransferItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(Formats.capitalize(item.product.name)),
            subtitle: Text(item.product.reference.toUpperCase()),
            trailing: Text('x ${Formats.quantity(item.quantity)}', style: Theme.of(context).textTheme.titleSmall),
          ),
      ],
    );
  }
}
