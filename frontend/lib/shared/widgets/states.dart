import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/errors/error_messages.dart';

/// Chargement : silhouettes grises simples (pas d'animation lourde).
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.lines = 6});

  final int lines;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    return ListView.separated(
      padding: const EdgeInsets.all(Gaps.lg),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: lines,
      separatorBuilder: (_, _) => const SizedBox(height: Gaps.md),
      itemBuilder: (_, index) => Container(
        height: 72,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.md)),
      ),
    );
  }
}

/// Liste vide : un titre, une aide, et éventuellement une action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.action});

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: Gaps.md),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: Gaps.xs),
              Text(message!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: Gaps.lg), action!],
          ],
        ),
      ),
    );
  }
}

/// Erreur de chargement avec un bouton « Réessayer ».
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.danger),
            const SizedBox(height: Gaps.md),
            Text(ErrorMessages.loadFailed, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: Gaps.xs),
              Text(message!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
            const SizedBox(height: Gaps.lg),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

/// Affiche le contenu d'un chargement unique (FutureBuilder avec états cohérents).
class AsyncContent<T> extends StatelessWidget {
  const AsyncContent({super.key, required this.future, required this.builder, required this.onRetry});

  final Future<T>? future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return ErrorState(message: error is Exception ? _message(error) : null, onRetry: onRetry);
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return builder(context, snapshot.data as T);
      },
    );
  }

  String? _message(Exception error) {
    final text = error.toString();
    final index = text.indexOf('): ');
    return index >= 0 ? text.substring(index + 3) : null;
  }
}
