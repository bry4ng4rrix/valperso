import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../sales/cart_controller.dart';

/// Déconnexion, toujours après confirmation.
Future<void> confirmLogout(BuildContext context) async {
  final cartIsEmpty = context.read<CartController>().isEmpty;
  final confirmed = await showConfirmation(
    context,
    title: 'Se déconnecter ?',
    message: cartIsEmpty
        ? 'Vous devrez saisir à nouveau vos identifiants pour vous reconnecter.'
        : 'Une vente est en cours : son panier sera perdu. Vous devrez saisir à nouveau vos identifiants.',
    confirmLabel: 'Se déconnecter',
    type: ConfirmationType.warning,
  );
  if (confirmed && context.mounted) await context.read<SessionController>().logout();
}
