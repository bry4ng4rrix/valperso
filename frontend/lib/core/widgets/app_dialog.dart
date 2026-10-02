import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';

/// Largeur d'une boîte de dialogue sur tablette et ordinateur.
enum DialogSize {
  small(420),
  medium(520),
  large(640);

  const DialogSize(this.width);
  final double width;
}

/// Marges autour de la boîte : faibles sur mobile pour profiter de toute la largeur.
EdgeInsets dialogInsets(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width < Breakpoints.tablet
      ? const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xl)
      : const EdgeInsets.symmetric(horizontal: Gaps.xxl, vertical: Gaps.xxl);
}

/// Largeur réelle de la boîte : toute la largeur disponible sur mobile,
/// la largeur [size] (limitée à l'écran) sur tablette et ordinateur.
double dialogWidth(BuildContext context, DialogSize size) {
  final screen = MediaQuery.sizeOf(context).width;
  final available = screen - dialogInsets(context).horizontal;
  return screen < Breakpoints.tablet ? available : math.min(size.width, available);
}

/// Boîte de dialogue de l'application, adaptée à la taille de l'écran.
///
/// - largeur fixe (pas de boîte étroite qui se rétrécit autour du texte) ;
/// - contenu défilant si l'écran est petit, boutons toujours visibles en bas ;
/// - sur mobile : boutons sur toute la largeur, faciles à toucher.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.icon,
    this.iconColor,
    this.size = DialogSize.medium,
    this.centerTitle = false,
  });

  /// Panneau visible de la boîte (utile pour mesurer sa largeur).
  static const panelKey = ValueKey('app-dialog-panel');

  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? icon;
  final Color? iconColor;
  final DialogSize size;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = MediaQuery.sizeOf(context).width < Breakpoints.tablet;
    final padding = mobile ? Gaps.lg : Gaps.xl;
    return Dialog(
      insetPadding: dialogInsets(context),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        key: AppDialog.panelKey,
        width: dialogWidth(context, size),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding, padding, padding, Gaps.md),
              child: Column(
                crossAxisAlignment: centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: iconColor ?? theme.colorScheme.primary, size: 32),
                    const SizedBox(height: Gaps.md),
                  ],
                  Text(
                    title,
                    style: theme.textTheme.titleLarge,
                    textAlign: centerTitle ? TextAlign.center : TextAlign.start,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: content,
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(padding, Gaps.lg, padding, padding),
                child: _Actions(actions: actions, mobile: mobile),
              )
            else
              SizedBox(height: padding),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.actions, required this.mobile});

  final List<Widget> actions;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    if (!mobile) {
      return Wrap(alignment: WrapAlignment.end, spacing: Gaps.sm, runSpacing: Gaps.sm, children: actions);
    }
    // Mobile : deux boutons côte à côte sur toute la largeur, au-delà les uns sous les autres.
    if (actions.length <= 2) {
      return Row(
        children: [
          for (final (index, action) in actions.indexed) ...[
            if (index > 0) const SizedBox(width: Gaps.sm),
            Expanded(child: action),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, action) in actions.reversed.indexed) ...[
          if (index > 0) const SizedBox(height: Gaps.sm),
          action,
        ],
      ],
    );
  }
}
