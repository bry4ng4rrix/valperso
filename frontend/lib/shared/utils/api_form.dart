import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/widgets/notifications.dart';

/// Comportement commun des formulaires qui envoient des données à l'API :
/// - les erreurs de validation renvoyées par l'API s'affichent sous le champ concerné ;
/// - les autres erreurs s'affichent dans une notification.
mixin ApiFormState<W extends StatefulWidget> on State<W> {
  Map<String, String> fieldErrors = const {};

  String? errorFor(String field) => fieldErrors[field];

  /// Lance l'appel. Renvoie `null` si l'API a refusé (l'erreur est déjà affichée).
  Future<T?> submitToApi<T extends Object>(Future<T> Function() call) async {
    if (fieldErrors.isNotEmpty) setState(() => fieldErrors = const {});
    try {
      return await call();
    } on ApiException catch (error) {
      if (!mounted) return null;
      setState(() => fieldErrors = error.fieldErrors);
      Notify.error(context, error);
      return null;
    }
  }
}

/// Lance une action API hors formulaire. Renvoie `true` si elle a réussi ;
/// sinon l'erreur est affichée dans une notification.
Future<bool> runApiAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) Notify.success(context, success);
    return true;
  } on ApiException catch (error) {
    if (context.mounted) Notify.error(context, error);
    return false;
  }
}
