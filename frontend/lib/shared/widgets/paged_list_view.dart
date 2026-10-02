import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged_controller.dart';
import 'pagination_controls.dart';
import 'states.dart';

/// Colonne d'un tableau sur grand écran.
class TableColumnDef<T> {
  const TableColumnDef(this.label, this.cell, {this.numeric = false});

  /// Colonne de texte simple.
  TableColumnDef.text(this.label, String Function(T item) text, {this.numeric = false})
    : cell = ((item) => Text(text(item)));

  final String label;
  final Widget Function(T item) cell;
  final bool numeric;
}

/// Liste paginée standard : chargement, vide, erreur, rafraîchissement et pagination.
///
/// Sur mobile : cartes empilées (pas de tableau horizontal géant).
/// Sur grand écran (>= 900 px) et si [columns] est fourni : tableau dense.
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.controller,
    required this.cardBuilder,
    this.columns,
    this.onTap,
    this.emptyTitle = 'Aucun résultat.',
    this.emptyMessage = 'Modifiez vos filtres ou votre recherche.',
    this.emptyAction,
    this.tableBreakpoint = 900,
  });

  final PagedController<T> controller;
  final Widget Function(BuildContext context, T item) cardBuilder;
  final List<TableColumnDef<T>>? columns;
  final ValueChanged<T>? onTap;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;
  final double tableBreakpoint;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.hasLoaded || (controller.isLoading && controller.items.isEmpty)) {
          return const LoadingState();
        }
        if (controller.error != null && controller.items.isEmpty) {
          return ErrorState(message: controller.error!.message, onRetry: controller.refresh);
        }
        if (controller.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(
              children: [
                const SizedBox(height: Gaps.xxl),
                EmptyState(title: emptyTitle, message: emptyMessage, action: emptyAction),
              ],
            ),
          );
        }
        return Column(
          children: [
            if (controller.isLoading) const LinearProgressIndicator(minHeight: 2),
            if (controller.error != null) _ErrorBar(message: controller.error!.message, onRetry: controller.refresh),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useTable = columns != null && constraints.maxWidth >= tableBreakpoint;
                  return useTable ? _buildTable(context, constraints) : _buildCards(context, constraints);
                },
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
    );
  }

  Widget _buildCards(BuildContext context, BoxConstraints constraints) {
    // Une colonne de cartes, centrée et limitée en largeur : lisible sur mobile comme sur tablette.
    final horizontal = constraints.maxWidth > 760 ? (constraints.maxWidth - 720) / 2 : Gaps.lg;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(horizontal, Gaps.sm, horizontal, 96),
        itemCount: controller.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: Gaps.md),
        itemBuilder: (context, index) {
          final item = controller.items[index];
          final card = cardBuilder(context, item);
          return onTap == null ? card : GestureDetector(onTap: () => onTap!(item), child: card);
        },
      ),
    );
  }

  Widget _buildTable(BuildContext context, BoxConstraints constraints) {
    final defs = columns!;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth - Gaps.lg * 2),
            child: Card(
              child: DataTable(
                showCheckboxColumn: false,
                headingRowHeight: 44,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 64,
                columns: [for (final def in defs) DataColumn(label: Text(def.label), numeric: def.numeric)],
                rows: [
                  for (final item in controller.items)
                    DataRow(
                      onSelectChanged: onTap == null ? null : (_) => onTap!(item),
                      cells: [for (final def in defs) DataCell(def.cell(item))],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.lg, 0),
      padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xs),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
          const SizedBox(width: Gaps.sm),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
