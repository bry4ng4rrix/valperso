import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

enum AppButtonVariant { primary, secondary, danger, success, text }

/// Compte les fenêtres ouvertes (boîtes de dialogue, feuilles, menus) dans les navigateurs observés.
/// [AppButton] s'en sert pour ne pas afficher « Enregistrement... » pendant une confirmation.
class PopupTracker extends NavigatorObserver {
  static final ValueNotifier<int> openCount = ValueNotifier(0);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) openCount.value++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) openCount.value--;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) openCount.value--;
  }
}

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
  int _popupsAtPress = 0;

  Future<void> _handlePress() async {
    if (_busy || widget.onPressed == null) return;
    _popupsAtPress = PopupTracker.openCount.value;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pendant qu'une confirmation est ouverte par-dessus, le bouton reste bloqué (pas de double envoi)
    // mais n'annonce pas « Enregistrement... » : rien n'est envoyé avant la confirmation.
    return ValueListenableBuilder<int>(
      valueListenable: PopupTracker.openCount,
      builder: (context, openPopups, _) => _build(context, showBusy: _busy && openPopups <= _popupsAtPress),
    );
  }

  Widget _build(BuildContext context, {required bool showBusy}) {
    final onPressed = widget.onPressed == null || _busy ? null : _handlePress;
    final label = Text(showBusy ? (widget.loadingLabel ?? widget.label) : widget.label);
    final Widget? icon = showBusy
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
