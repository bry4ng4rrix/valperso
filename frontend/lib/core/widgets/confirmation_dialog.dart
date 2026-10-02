import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import 'app_dialog.dart';

enum ConfirmationType { normal, warning, danger }

/// Une modification affichée avant confirmation : « Prix : 10 000 Ar → 12 000 Ar ».
class FieldChange {
  const FieldChange(this.label, this.before, this.after);

  final String label;
  final String before;
  final String after;

  bool get changed => before != after;
}

/// Boîte de confirmation unique de l'application (ventes, suppressions, modifications...).
///
/// Renvoie `true` seulement si l'utilisateur confirme. Pour une action sensible,
/// [doubleCheck] demande une seconde confirmation.
Future<bool> showConfirmation(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  List<FieldChange>? changes,
  String confirmLabel = 'Confirmer',
  String cancelLabel = 'Annuler',
  ConfirmationType type = ConfirmationType.normal,
  bool doubleCheck = false,
  DialogSize? size,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ConfirmationDialog(
      title: title,
      message: message,
      content: content,
      changes: changes,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      type: type,
      size: size ?? (content != null ? DialogSize.large : DialogSize.medium),
    ),
  );
  if (confirmed != true) return false;
  if (!doubleCheck || !context.mounted) return confirmed == true;
  return showConfirmation(
    context,
    title: 'Êtes-vous vraiment sûr ?',
    message: 'Cette action est sensible et ne pourra pas être annulée facilement.',
    confirmLabel: confirmLabel,
    type: type,
  );
}

class ConfirmationDialog extends StatelessWidget {
  const ConfirmationDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.changes,
    this.confirmLabel = 'Confirmer',
    this.cancelLabel = 'Annuler',
    this.type = ConfirmationType.normal,
    this.size = DialogSize.medium,
  });

  final String title;
  final String? message;
  final Widget? content;
  final List<FieldChange>? changes;
  final String confirmLabel;
  final String cancelLabel;
  final ConfirmationType type;
  final DialogSize size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (type) {
      ConfirmationType.normal => (Icons.help_outline, theme.colorScheme.primary),
      ConfirmationType.warning => (Icons.warning_amber_rounded, AppColors.warning),
      ConfirmationType.danger => (Icons.delete_outline, AppColors.danger),
    };
    return AppDialog(
      title: title,
      icon: icon,
      iconColor: color,
      centerTitle: true,
      size: size,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message != null) Text(message!, style: theme.textTheme.bodyMedium),
          if (message != null && (content != null || changes != null)) const SizedBox(height: Gaps.md),
          if (changes != null) ChangeList(changes: changes!),
          ?content,
        ],
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
        FilledButton(
          style: type == ConfirmationType.danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Liste « avant → après ». Les champs inchangés sont regroupés en fin de liste.
class ChangeList extends StatelessWidget {
  const ChangeList({super.key, required this.changes});

  final List<FieldChange> changes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modified = changes.where((c) => c.changed).toList();
    if (modified.isEmpty) {
      return Text('Aucun changement.', style: theme.textTheme.bodyMedium);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final change in modified)
          Padding(
            padding: const EdgeInsets.only(bottom: Gaps.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(change.label, style: theme.textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(
                  change.before.isEmpty ? '—' : change.before,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.arrow_forward, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: Gaps.xs),
                    Expanded(
                      child: Text(
                        change.after.isEmpty ? '—' : change.after,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Confirmation avec un champ texte obligatoire (ex. motif d'annulation d'une vente).
/// Renvoie le texte saisi, ou `null` si l'utilisateur annule.
Future<String?> showReasonConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String fieldLabel,
  String confirmLabel = 'Confirmer',
  ConfirmationType type = ConfirmationType.danger,
}) {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AppDialog(
      title: title,
      icon: type == ConfirmationType.danger ? Icons.delete_outline : Icons.warning_amber_rounded,
      iconColor: type == ConfirmationType.danger ? AppColors.danger : AppColors.warning,
      centerTitle: true,
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: Gaps.md),
            TextFormField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: fieldLabel),
              validator: (value) => (value == null || value.trim().length < 3) ? 'Au moins 3 caractères.' : null,
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          style: type == ConfirmationType.danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white)
              : null,
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.of(context).pop(controller.text.trim());
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
