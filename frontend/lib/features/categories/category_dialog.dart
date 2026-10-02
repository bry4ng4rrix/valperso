import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import 'categories_repository.dart';
import '../../core/widgets/app_dialog.dart';

/// Création ou modification d'une catégorie. Renvoie la catégorie enregistrée.
Future<Category?> showCategoryDialog(BuildContext context, {Category? category}) {
  return showDialog<Category>(
    context: context,
    builder: (_) => _CategoryDialog(category: category),
  );
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.category});

  final Category? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> with ApiFormState {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.category?.label);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = context.read<CategoriesRepository>();
    final existing = widget.category;
    final name = _name.text.trim();
    Category? saved;
    if (existing == null) {
      saved = await submitToApi(() => repository.create(name: name));
    } else {
      if (name.toUpperCase() == existing.name.toUpperCase()) return Navigator.of(context).pop();
      final confirmed = await showConfirmation(
        context,
        title: 'Enregistrer les modifications ?',
        changes: [FieldChange('Nom', existing.label, name)],
      );
      if (!confirmed || !mounted) return;
      saved = await submitToApi(() => repository.update(existing.id, {'name': name}));
    }
    if (saved == null || !mounted) return;
    Notify.success(context, existing == null ? 'Catégorie créée.' : 'Catégorie modifiée.');
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.category == null ? 'Nouvelle catégorie' : 'Modifier la catégorie',
      size: DialogSize.small,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Nom',
              controller: _name,
              autofocus: true,
              required: true,
              errorText: errorFor('name'),
              validator: Validators.text(required: true, min: 2, max: 100),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        AppButton(label: 'Enregistrer', onPressed: _save),
      ],
    );
  }
}
