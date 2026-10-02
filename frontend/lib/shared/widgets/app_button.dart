import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

enum AppButtonVariant { primary, secondary, danger, success, text }

/// Bouton de l'application. Si [onPressed] renvoie un Future, le bouton se désactive et affiche
/// un indicateur jusqu'à la fin de l'action : un double appui ne lance jamais l'action deux fois.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.loadingLabel,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final Future<void> Function()? onPressed;
  final AppButtonVariant variant;
  final String? loadingLabel;
  final bool expand;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _busy = false;

  Future<void> _handlePress() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed == null || _busy ? null : _handlePress;
    final label = Text(_busy ? (widget.loadingLabel ?? widget.label) : widget.label);
    final Widget? icon = _busy
        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : widget.icon == null
            ? null
            : Icon(widget.icon, size: 20);

    final Widget button = switch (widget.variant) {
      AppButtonVariant.primary => FilledButton.icon(onPressed: onPressed, icon: icon, label: label),
      AppButtonVariant.danger => FilledButton.icon(
          onPressed: onPressed,
          icon: icon,
          label: label,
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
        ),
      AppButtonVariant.success => FilledButton.icon(
          onPressed: onPressed,
          icon: icon,
          label: label,
          style: FilledButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
        ),
      AppButtonVariant.secondary => OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label),
      AppButtonVariant.text => TextButton.icon(onPressed: onPressed, icon: icon, label: label),
    };
    return widget.expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
