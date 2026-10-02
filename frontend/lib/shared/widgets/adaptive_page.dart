import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';
import '../../core/utils/responsive.dart';
import 'app_card.dart';
import 'list_page.dart';

/// Écran principal hors liste (accueil, caisse, paramètres...) :
/// barre de titre sur mobile, en-tête de page sur grand écran.
class AdaptivePage extends StatelessWidget {
  const AdaptivePage({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.primaryAction,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final PrimaryAction? primaryAction;

  /// Onglets éventuels.
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    if (context.isWide) {
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: title,
              subtitle: subtitle,
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
      body: body,
    );
  }
}

/// Contenu défilant centré et limité en largeur, avec les marges adaptées à l'écran.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = Sizes.contentMaxWidth, this.onRefresh});

  final List<Widget> children;
  final double maxWidth;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final padding = context.isWide ? Gaps.xl : Gaps.lg;
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(padding, context.isWide ? 0 : Gaps.lg, padding, Gaps.xxl * 2),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}
