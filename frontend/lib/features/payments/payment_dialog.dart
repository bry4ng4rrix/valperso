import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import 'payment_models.dart';
import 'payments_repository.dart';
import '../../core/widgets/app_dialog.dart';

/// Encaisser un paiement sur une vente qui a un reste à payer (avance ou dette).
/// Renvoie le paiement enregistré, ou null.
Future<Payment?> showPaymentDialog(
  BuildContext context, {
  required int saleId,
  required String saleNumber,
  required double remaining,
  String? customerName,
}) {
  return showDialog<Payment>(
    context: context,
    builder: (_) =>
        _PaymentDialog(saleId: saleId, saleNumber: saleNumber, remaining: remaining, customerName: customerName),
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.saleId, required this.saleNumber, required this.remaining, this.customerName});

  final int saleId;
  final String saleNumber;
  final double remaining;
  final String? customerName;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> with ApiFormState {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: Formats.amount(widget.remaining));
  final _reference = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  String? _validateAmount(String? value) {
    final amount = parseAmount(value);
    if (amount == null) return 'Saisissez un montant.';
    if (amount <= 0) return 'Le montant doit être supérieur à 0.';
    if (amount > widget.remaining) return 'Maximum : ${Formats.money(widget.remaining)} (reste à payer).';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseAmount(_amount.text)!;
    final after = widget.remaining - amount;
    final confirmed = await showConfirmation(
      context,
      title: 'Encaisser ${Formats.money(amount)} ?',
      message: [
        'Vente ${widget.saleNumber}',
        if (widget.customerName != null) 'Client : ${widget.customerName}',
        'Mode : ${_method.label}',
      ].join('\n'),
      changes: [FieldChange('Reste à payer', Formats.money(widget.remaining), Formats.money(after))],
      confirmLabel: 'Encaisser',
    );
    if (!confirmed || !mounted) return;
    final payment = await submitToApi(
      () => context.read<PaymentsRepository>().create(
        saleId: widget.saleId,
        method: _method,
        amount: amount,
        reference: trimOrNull(_reference.text),
      ),
    );
    if (payment == null || !mounted) return;
    Notify.success(
      context,
      after <= 0
          ? 'Paiement enregistré : la vente est soldée.'
          : 'Paiement enregistré. Reste : ${Formats.money(after)}.',
    );
    Navigator.of(context).pop(payment);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Encaisser un paiement',
      size: DialogSize.small,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Vente ${widget.saleNumber} · reste à payer ${Formats.money(widget.remaining)}'),
            const SizedBox(height: Gaps.lg),
            MoneyField(
              label: 'Montant',
              controller: _amount,
              required: true,
              validator: _validateAmount,
              errorText: errorFor('amount'),
            ),
            const SizedBox(height: Gaps.md),
            Text('Mode de paiement', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: Gaps.xs),
            Wrap(
              spacing: Gaps.sm,
              runSpacing: Gaps.sm,
              children: [
                for (final method in PaymentMethod.collected)
                  ChoiceChip(
                    label: Text(method.label),
                    selected: method == _method,
                    onSelected: (_) => setState(() => _method = method),
                  ),
              ],
            ),
            const SizedBox(height: Gaps.md),
            AppTextField(
              label: 'Référence (n° de transaction...)',
              controller: _reference,
              errorText: errorFor('reference'),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        AppButton(label: 'Encaisser', icon: Icons.payments_outlined, onPressed: _save),
      ],
    );
  }
}
