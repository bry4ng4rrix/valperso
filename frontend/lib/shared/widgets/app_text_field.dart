import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/formatters.dart';

/// Champ de saisie standard : libellé, aide, et erreur affichée directement sous le champ
/// (erreur locale via [validator] ou erreur renvoyée par l'API via [errorText]).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.errorText,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textInputAction,
    this.required = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? errorText;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final bool enabled;
  final int maxLines;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        helperText: helper,
        errorText: errorText,
        errorMaxLines: 3,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
        suffixIcon: suffix,
      ),
      validator: validator ?? (required ? requiredValidator : null),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      enabled: enabled,
      maxLines: maxLines,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      autofocus: autofocus,
      textInputAction: textInputAction,
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );
  }
}

String? requiredValidator(String? value) => value == null || value.trim().isEmpty ? 'Champ obligatoire.' : null;

/// Champ montant en Ariary (chiffres, espaces et virgule autorisés).
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.label,
    required this.controller,
    this.errorText,
    this.validator,
    this.required = false,
    this.helper,
    this.onChanged,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final String? errorText;
  final String? Function(String?)? validator;
  final bool required;
  final String? helper;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      controller: controller,
      errorText: errorText,
      helper: helper,
      required: required,
      onChanged: onChanged,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ,.]'))],
      suffix: const Padding(padding: EdgeInsets.all(14), child: Text('Ar')),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return required ? 'Champ obligatoire.' : null;
        final amount = parseAmount(value);
        if (amount == null) return 'Montant invalide.';
        if (amount < 0) return 'Le montant ne peut pas être négatif.';
        return validator?.call(value);
      },
    );
  }
}

/// Champ quantité entière positive.
class QuantityField extends StatelessWidget {
  const QuantityField({super.key, required this.label, required this.controller, this.max, this.min = 1});

  final String label;
  final TextEditingController controller;
  final int? max;
  final int min;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      controller: controller,
      required: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      helper: max == null ? null : 'Disponible : $max',
      validator: (value) {
        final quantity = int.tryParse(value ?? '');
        if (quantity == null) return 'Quantité invalide.';
        if (quantity < min) return 'Minimum : $min.';
        if (max != null && quantity > max!) return 'Maximum disponible : $max.';
        return null;
      },
    );
  }
}
