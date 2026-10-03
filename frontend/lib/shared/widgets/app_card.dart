import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';

/// Carte standard (bordure fine, fond légèrement plus clair que le fond de l'écran).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(Gaps.lg)});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Carte avec un titre, pour regrouper des informations dans les écrans de détail.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.icon});

  final String title;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: Gaps.sm),
              ],
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              ?trailing,
            ],
          ),
          const SizedBox(height: Gaps.md),
          child,
        ],
      ),
    );
  }
}

/// Ligne « libellé ............ valeur », pour les détails et les résumés.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.valueStyle, this.emphasis = false});

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        valueStyle ??
        (emphasis ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gaps.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Libellé court, valeur plus large (e-mail, adresse, montants).
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: emphasis
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: Gaps.md),
          Expanded(
            flex: 3,
            child: Text(value, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// En-tête d'écran avec un titre et des actions, pour les écrans larges.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, Gaps.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Wrap(spacing: Gaps.sm, children: actions),
        ],
      ),
    );
  }
}
