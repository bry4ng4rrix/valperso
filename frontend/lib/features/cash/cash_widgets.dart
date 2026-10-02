import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/status_badge.dart';
import 'cash_models.dart';
import 'cash_repository.dart';
import '../../core/widgets/app_dialog.dart';

StatusBadge cashStatusBadge(CashRegister register) => register.isOpen
    ? const StatusBadge('Ouverte', tone: BadgeTone.success, icon: Icons.lock_open)
    : const StatusBadge('Fermée', tone: BadgeTone.neutral, icon: Icons.lock_outline);

Color? differenceColor(double? difference) {
  if (difference == null || difference == 0) return null;
  return difference < 0 ? AppColors.danger : AppColors.warning;
}

/// Résumé d'une caisse : fond, montant théorique, montant compté et écart.
class RegisterSummary extends StatelessWidget {
  const RegisterSummary({super.key, required this.register, required this.storeLabel});

  final CashRegister register;
  final String storeLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoRow(label: 'Magasin', value: storeLabel),
        InfoRow(
          label: 'Ouverte le',
          value: '${Formats.dateTime(register.openedAt)}${register.openedAutomatically ? ' (automatique)' : ''}',
        ),
        if (register.closedAt != null)
          InfoRow(
            label: 'Fermée le',
            value: '${Formats.dateTime(register.closedAt)}${register.closedAutomatically ? ' (automatique)' : ''}',
          ),
        InfoRow(label: 'Fond de caisse', value: Formats.money(register.openingAmount)),
        InfoRow(label: 'Montant théorique', value: Formats.money(register.expectedAmount), emphasis: register.isOpen),
        if (register.closingAmount != null)
          InfoRow(label: 'Montant compté', value: Formats.money(register.closingAmount)),
        if (register.difference != null)
          InfoRow(
            label: 'Écart',
            value: Formats.money(register.difference),
            valueStyle: TextStyle(color: differenceColor(register.difference), fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction});

  final CashTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final positive = transaction.amount >= 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        positive ? Icons.add_circle_outline : Icons.remove_circle_outline,
        color: positive ? AppColors.success : AppColors.danger,
      ),
      title: Text(transaction.type.label),
      subtitle: Text(
        [
          Formats.dateTime(transaction.createdAt),
          if (transaction.reason != null) Formats.text(transaction.reason),
          if (transaction.reference != null) 'réf. ${transaction.reference}',
        ].join(' · '),
      ),
      trailing: Text(
        '${positive ? '+' : ''}${Formats.money(transaction.amount)}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: positive ? AppColors.success : AppColors.danger),
      ),
    );
  }
}

/// Ouvrir la caisse d'un magasin. Renvoie la caisse ouverte.
Future<CashRegister?> showOpenRegisterDialog(
  BuildContext context, {
  required int? storeId,
  required String storeLabel,
}) {
  return showDialog<CashRegister>(
    context: context,
    builder: (_) => _AmountDialog(
      title: 'Ouvrir la caisse',
      fieldLabel: 'Fond de caisse',
      helper: 'Montant en espèces présent dans la caisse à l\'ouverture.',
      confirm: (context, amount) => showConfirmation(
        context,
        title: 'Ouvrir la caisse ?',
        message: '$storeLabel\nFond de caisse : ${Formats.money(amount)}',
        confirmLabel: 'Ouvrir',
      ),
      submit: (context, amount) => context.read<CashRepository>().open(openingAmount: amount, storeId: storeId),
      successMessage: 'Caisse ouverte.',
    ),
  );
}

/// Fermer la caisse : saisie du montant compté, aperçu de l'écart, confirmation.
Future<CashRegister?> showCloseRegisterDialog(BuildContext context, CashRegister register) {
  return showDialog<CashRegister>(
    context: context,
    builder: (_) => _AmountDialog(
      title: 'Fermer la caisse',
      fieldLabel: 'Montant compté',
      helper: 'Montant théorique : ${Formats.money(register.expectedAmount)}',
      preview: (amount) {
        final difference = amount - register.expectedAmount;
        return difference == 0
            ? 'Aucun écart.'
            : 'Écart : ${Formats.money(difference)} (${difference < 0 ? 'manque' : 'excédent'})';
      },
      confirm: (context, amount) {
        final difference = amount - register.expectedAmount;
        return showConfirmation(
          context,
          title: 'Fermer la caisse ?',
          message: difference == 0
              ? 'Le montant compté correspond au montant théorique.'
              : 'Attention : un écart de ${Formats.money(difference)} sera enregistré.',
          changes: [
            const FieldChange('Statut', 'Ouverte', 'Fermée'),
            FieldChange('Montant théorique → compté', Formats.money(register.expectedAmount), Formats.money(amount)),
          ],
          confirmLabel: 'Fermer la caisse',
          type: difference == 0 ? ConfirmationType.warning : ConfirmationType.danger,
        );
      },
      submit: (context, amount) => context.read<CashRepository>().close(register.id, closingAmount: amount),
      successMessage: 'Caisse fermée.',
    ),
  );
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.fieldLabel,
    required this.confirm,
    required this.submit,
    required this.successMessage,
    this.helper,
    this.preview,
  });

  final String title;
  final String fieldLabel;
  final String? helper;
  final String Function(double amount)? preview;
  final Future<bool> Function(BuildContext context, double amount) confirm;
  final Future<CashRegister> Function(BuildContext context, double amount) submit;
  final String successMessage;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> with ApiFormState {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseAmount(_amount.text)!;
    final confirmed = await widget.confirm(context, amount);
    if (!confirmed || !mounted) return;
    final register = await submitToApi(() => widget.submit(context, amount));
    if (register == null || !mounted) return;
    Notify.success(context, widget.successMessage);
    Navigator.of(context).pop(register);
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseAmount(_amount.text);
    return AppDialog(
      title: widget.title,
      size: DialogSize.small,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MoneyField(
              label: widget.fieldLabel,
              controller: _amount,
              required: true,
              helper: widget.helper,
              errorText: errorFor('opening_amount') ?? errorFor('closing_amount'),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.preview != null && amount != null) ...[
              const SizedBox(height: Gaps.md),
              Text(widget.preview!(amount), style: Theme.of(context).textTheme.titleSmall),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        AppButton(label: 'Continuer', onPressed: _save),
      ],
    );
  }
}

/// Opération manuelle sur la caisse (dépense, retrait, dépôt, ajustement). Renvoie true si enregistrée.
Future<bool> showCashTransactionDialog(BuildContext context, CashRegister register) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _TransactionDialog(register: register),
  );
  return result ?? false;
}

class _TransactionDialog extends StatefulWidget {
  const _TransactionDialog({required this.register});

  final CashRegister register;

  @override
  State<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<_TransactionDialog> with ApiFormState {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  CashTransactionType _type = CashTransactionType.expense;
  bool _adjustDown = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _reference.dispose();
    super.dispose();
  }

  /// Effet sur le montant théorique (négatif = sortie d'argent).
  double _signed(double amount) => switch (_type) {
    CashTransactionType.expense || CashTransactionType.withdrawal => -amount,
    CashTransactionType.adjustment => _adjustDown ? -amount : amount,
    _ => amount,
  };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseAmount(_amount.text)!;
    final signed = _signed(amount);
    final expected = widget.register.expectedAmount;
    final confirmed = await showConfirmation(
      context,
      title: '${_type.label} de ${Formats.money(amount)} ?',
      message: 'Motif : ${_reason.text.trim()}',
      changes: [FieldChange('Montant théorique', Formats.money(expected), Formats.money(expected + signed))],
      type: signed < 0 ? ConfirmationType.warning : ConfirmationType.normal,
      confirmLabel: 'Enregistrer',
    );
    if (!confirmed || !mounted) return;
    final saved = await submitToApi(
      () => context.read<CashRepository>().addTransaction(
        widget.register.id,
        type: _type,
        amount: _type == CashTransactionType.adjustment ? signed : amount,
        reason: _reason.text.trim(),
        reference: trimOrNull(_reference.text),
      ),
    );
    if (saved == null || !mounted) return;
    Notify.success(context, 'Opération enregistrée.');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Opération de caisse',
      size: DialogSize.small,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Gaps.sm,
              runSpacing: Gaps.sm,
              children: [
                for (final type in CashTransactionType.manualTypes)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: type == _type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
            if (_type == CashTransactionType.adjustment) ...[
              const SizedBox(height: Gaps.md),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Ajouter')),
                  ButtonSegment(value: true, label: Text('Retirer')),
                ],
                selected: {_adjustDown},
                onSelectionChanged: (selection) => setState(() => _adjustDown = selection.first),
              ),
            ],
            const SizedBox(height: Gaps.md),
            MoneyField(
              label: 'Montant',
              controller: _amount,
              required: true,
              validator: Validators.positiveAmount,
              errorText: errorFor('amount'),
            ),
            const SizedBox(height: Gaps.md),
            AppTextField(
              label: 'Motif',
              controller: _reason,
              required: true,
              validator: Validators.text(required: true, min: 3, max: 255),
              errorText: errorFor('reason'),
            ),
            const SizedBox(height: Gaps.md),
            AppTextField(label: 'Référence (facultatif)', controller: _reference, errorText: errorFor('reference')),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        AppButton(label: 'Continuer', onPressed: _save),
      ],
    );
  }
}
