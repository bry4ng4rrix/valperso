import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/paged_controller.dart';
import '../../core/utils/responsive.dart';
import 'app_card.dart';
import 'filters.dart';

/// Action principale d'une liste (ex. « Nouveau produit ») : bouton flottant sur mobile,
/// bouton bleu dans l'en-tête sur grand écran.
class PrimaryAction {
  const PrimaryAction({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// Mise en page commune de tous les écrans de liste :
/// titre, recherche, filtres, filtres rapides, nombre de résultats, liste paginée, export.
class ListPage extends StatelessWidget {
  const ListPage({
    super.key,
    required this.title,
    required this.controller,
    required this.body,
    this.search,
    this.quickFilters,
    this.onOpenFilters,
    this.actions = const [],
    this.primaryAction,
    this.countLabel,
    this.bottom,
    this.embedded = false,
  });

  final String title;
  final PagedController<dynamic> controller;
  final Widget body;
  final Widget? search;
  final Widget? quickFilters;
  final VoidCallback? onOpenFilters;
  final List<Widget> actions;
  final PrimaryAction? primaryAction;

  /// Texte du compteur, ex. (n) => '$n produits trouvés'.
  final String Function(int total)? countLabel;

  /// Onglets éventuels sous le titre (ex. Tous / Avec dette).
  final PreferredSizeWidget? bottom;

  /// Affichée dans un onglet d'un autre écran : pas de barre de titre,
  /// les actions (export...) sont placées à côté de la recherche.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    final toolbar = Padding(
      padding: EdgeInsets.fromLTRB(wide ? Gaps.xl : Gaps.lg, Gaps.sm, wide ? Gaps.xl : Gaps.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (search != null)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: search),
                  ),
                ),
              if (onOpenFilters != null) ...[
                const SizedBox(width: Gaps.sm),
                ListenableBuilder(
                  listenable: controller,
                  builder: (_, _) => FilterButton(activeCount: controller.activeFilterCount, onPressed: onOpenFilters!),
                ),
              ],
              if (embedded) ...actions,
            ],
          ),
          if (quickFilters != null) ...[const SizedBox(height: Gaps.sm), quickFilters!],
          const SizedBox(height: Gaps.sm),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Text(
              controller.hasLoaded ? _count(controller.total) : ' ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );

    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          const SizedBox(height: Gaps.xs),
          Expanded(child: body),
        ],
      );
    }
    if (wide) {
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: title,
              actions: [
                ...actions,
                if (primaryAction != null)
                  FilledButton.icon(
                    onPressed: primaryAction!.onPressed,
                    icon: Icon(primaryAction!.icon),
                    label: Text(primaryAction!.label),
                  ),
              ],
            ),
            ?bottom,
            toolbar,
            const SizedBox(height: Gaps.sm),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions, bottom: bottom),
      floatingActionButton: primaryAction == null
          ? null
          : FloatingActionButton.extended(
              onPressed: primaryAction!.onPressed,
              icon: Icon(primaryAction!.icon),
              label: Text(primaryAction!.label),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          const SizedBox(height: Gaps.xs),
          Expanded(child: body),
        ],
      ),
    );
  }

  String _count(int total) => countLabel?.call(total) ?? '$total résultat${total > 1 ? 's' : ''}';
}

/// Écran de détail ou de formulaire : barre de titre + contenu sur toute la largeur de l'écran.
class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.title, required this.child, this.actions = const [], this.bottomBar});

  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      bottomNavigationBar: bottomBar,
      body: child,
    );
  }
}
