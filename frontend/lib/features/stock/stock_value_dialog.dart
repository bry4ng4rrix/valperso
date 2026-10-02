import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_dialog.dart';
import '../../shared/widgets/app_card.dart';
import 'stock_models.dart';
import 'stock_repository.dart';

/// Valeur du stock (prix, prix de vente, bénéfice potentiel) d'un magasin ou de tous les magasins.
Future<void> showStockValueDialog(BuildContext context, {int? storeId}) => showDialog<void>(
  context: context,
  builder: (_) => StockValueDialog(storeId: storeId),
);

class StockValueDialog extends StatelessWidget {
  const StockValueDialog({super.key, required this.storeId});

  final int? storeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      title: 'Valeur du stock',
      size: DialogSize.medium,
      content: FutureBuilder<StockValueReport>(
        future: context.read<StockRepository>().value(storeId: storeId),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('Impossible de calculer la valeur du stock.');
          if (!snapshot.hasData) {
            return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
          }
          final report = snapshot.data!;
          Widget block(String title, StockValue value, {bool total = false}) => Padding(
            padding: const EdgeInsets.only(bottom: Gaps.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: total ? theme.textTheme.titleMedium : theme.textTheme.titleSmall),
                InfoRow(label: 'Quantité', value: Formats.quantity(value.quantity)),
                InfoRow(label: 'Valeur au prix', value: Formats.money(value.purchaseValue)),
                InfoRow(label: 'Valeur de vente', value: Formats.money(value.saleValue)),
                InfoRow(label: 'Bénéfice potentiel', value: Formats.money(value.potentialProfit), emphasis: total),
              ],
            ),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final value in report.stores) block(value.store?.label ?? 'Magasin', value),
              if (report.stores.length != 1) ...[const Divider(), block('Total', report.total, total: true)],
            ],
          );
        },
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer'))],
    );
  }
}
