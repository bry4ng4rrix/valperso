import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../api/api_exception.dart';
import '../errors/error_messages.dart';

enum NoticeType { success, info, warning, error }

/// Retour visuel après une action : court, discret, toujours au même endroit.
abstract final class Notify {
  static void success(BuildContext context, String message) => _show(context, message, NoticeType.success);

  static void info(BuildContext context, String message) => _show(context, message, NoticeType.info);

  static void warning(BuildContext context, String message) => _show(context, message, NoticeType.warning);

  static void error(BuildContext context, Object error) {
    final message = error is ApiException ? error.message : ErrorMessages.unknown;
    _show(context, message, NoticeType.error);
  }

  static void _show(BuildContext context, String message, NoticeType type) {
    final (icon, color) = switch (type) {
      NoticeType.success => (Icons.check_circle_outline, AppColors.success),
      NoticeType.info => (Icons.info_outline, AppColors.info),
      NoticeType.warning => (Icons.warning_amber_rounded, AppColors.warning),
      NoticeType.error => (Icons.error_outline, AppColors.danger),
    };
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: Duration(seconds: type == NoticeType.error ? 5 : 3),
          content: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          showCloseIcon: type == NoticeType.error,
        ),
      );
  }
}
