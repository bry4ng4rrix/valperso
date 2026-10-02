import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/auth/session_controller.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import 'cash_models.dart';
import 'cash_repository.dart';
import 'cash_screen.dart';
import 'cash_widgets.dart';
import '../../shared/widgets/responsive_grid.dart';

/// Détail d'une caisse de l'historique, avec ses mouvements.
class CashRegisterScreen extends StatefulWidget {
  const CashRegisterScreen({super.key, required this.registerId});

  final int registerId;

  @override
  State<CashRegisterScreen> createState() => _CashRegisterScreenState();
}

class _CashRegisterScreenState extends State<CashRegisterScreen> {
  late Future<(CashRegister, Map<int, String>)> _future = _load();

  Future<(CashRegister, Map<int, String>)> _load() async {
    final user = context.read<SessionController>().requireUser;
    final labelsFuture = storeLabels(context, user);
    final register = await context.read<CashRepository>().get(widget.registerId);
    return (register, await labelsFuture);
  }

  @override
  Widget build(BuildContext context) {
    return DetailPage(
      title: 'Caisse',
      child: FutureBuilder<(CashRegister, Map<int, String>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: errorMessageOf(snapshot.error),
              onRetry: () => setState(() {
                _future = _load();
              }),
            );
          }
          if (!snapshot.hasData) return const LoadingState(lines: 3);
          final (register, labels) = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(Gaps.lg),
            children: [
              SectionColumns(
                children: [
                  SectionCard(
                    title: 'Résumé',
                    icon: Icons.point_of_sale,
                    trailing: cashStatusBadge(register),
                    child: RegisterSummary(register: register, storeLabel: labels[register.storeId] ?? 'Magasin'),
                  ),
                  SectionCard(
                    title: 'Mouvements',
                    icon: Icons.receipt_long_outlined,
                    child: RegisterTransactions(registerId: register.id),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
