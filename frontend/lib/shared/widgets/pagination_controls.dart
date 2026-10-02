import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';
import '../../core/utils/responsive.dart';

/// Pagination : « Page 2 / 25 » avec Précédent / Suivant (et numéros de page sur grand écran).
class PaginationControls extends StatelessWidget {
  const PaginationControls({
    super.key,
    required this.page,
    required this.pages,
    required this.total,
    required this.onPageSelected,
    this.isLoading = false,
  });

  final int page;
  final int pages;
  final int total;
  final ValueChanged<int> onPageSelected;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (pages <= 1) {
      return Padding(
        padding: const EdgeInsets.all(Gaps.sm),
        child: Text('$total résultat${total > 1 ? 's' : ''}', style: Theme.of(context).textTheme.bodySmall),
      );
    }
    final canPrevious = page > 1 && !isLoading;
    final canNext = page < pages && !isLoading;
    final compact = context.isMobile;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            tooltip: 'Page précédente',
            onPressed: canPrevious ? () => onPageSelected(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: Gaps.sm),
          if (compact)
            Text('Page $page / $pages', style: Theme.of(context).textTheme.labelLarge)
          else
            for (final number in _visiblePages())
              number == null
                  ? const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('…'))
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: number == page
                          ? FilledButton(
                              onPressed: null,
                              style: FilledButton.styleFrom(minimumSize: const Size(40, 40)),
                              child: Text('$number'),
                            )
                          : TextButton(
                              onPressed: isLoading ? null : () => onPageSelected(number),
                              style: TextButton.styleFrom(minimumSize: const Size(40, 40)),
                              child: Text('$number'),
                            ),
                    ),
          const SizedBox(width: Gaps.sm),
          IconButton.outlined(
            tooltip: 'Page suivante',
            onPressed: canNext ? () => onPageSelected(page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          if (!compact) ...[
            const SizedBox(width: Gaps.md),
            Text('$total résultats', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  /// Numéros affichés : 1 … 4 5 6 … 25 (null = points de suspension).
  List<int?> _visiblePages() {
    final numbers = <int>{1, pages, page - 1, page, page + 1}.where((n) => n >= 1 && n <= pages).toList()..sort();
    final result = <int?>[];
    for (final number in numbers) {
      if (result.isNotEmpty && result.last != null && number - result.last! > 1) result.add(null);
      result.add(number);
    }
    return result;
  }
}
