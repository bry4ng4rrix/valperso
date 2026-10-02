import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';

/// Bouton « Filtres » avec le nombre de filtres actifs.
class FilterButton extends StatelessWidget {
  const FilterButton({super.key, required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: activeCount > 0,
      label: Text('$activeCount'),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.tune, size: 20),
        label: const Text('Filtres'),
      ),
    );
  }
}

/// Ouvre les filtres d'une liste : en bas de l'écran sur mobile, en boîte de dialogue sinon.
/// [builder] reçoit un `refresh` à appeler pour reconstruire le panneau après un changement.
Future<void> showFilterSheet(
  BuildContext context, {
  required Widget Function(BuildContext context, VoidCallback refresh) builder,
  VoidCallback? onReset,
}) {
  final isMobile = MediaQuery.sizeOf(context).width < Breakpoints.tablet;
  Widget panel(BuildContext context) => StatefulBuilder(
    builder: (context, setState) => Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Filtres', style: Theme.of(context).textTheme.titleLarge)),
              if (onReset != null)
                TextButton(
                  onPressed: () {
                    onReset();
                    setState(() {});
                  },
                  child: const Text('Réinitialiser'),
                ),
            ],
          ),
          const SizedBox(height: Gaps.md),
          Flexible(child: SingleChildScrollView(child: builder(context, () => setState(() {})))),
          const SizedBox(height: Gaps.lg),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voir les résultats')),
        ],
      ),
    ),
  );

  if (isMobile) {
    return showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: panel);
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: Gaps.lg),
          child: panel(context),
        ),
      ),
    ),
  );
}

/// Liste déroulante de filtre, avec une option « Tous ».
class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.allLabel = 'Tous',
  });

  final String label;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.md),
      child: DropdownButtonFormField<T?>(
        key: ValueKey('$label-$value'),
        initialValue: options.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text(allLabel)),
          for (final entry in options.entries) DropdownMenuItem<T?>(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Choix rapide sous forme de puces (ex. Tous / Avec dette / Sans dette).
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({super.key, required this.value, required this.options, required this.onChanged, this.label});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label!, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: Gaps.xs),
          ],
          Wrap(
            spacing: Gaps.sm,
            runSpacing: Gaps.sm,
            children: [
              for (final entry in options.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: entry.key == value,
                  onSelected: (_) => onChanged(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
