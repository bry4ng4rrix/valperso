import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../utils/formatters.dart';
import '../widgets/notifications.dart';
import 'realtime_service.dart';

/// Signale ce que font les autres utilisateurs, en direct : nouvelle vente, produit ajouté ou supprimé.
/// Les écrans concernés se mettent à jour d'eux-mêmes (voir `LiveRefresh`) ; ceci n'est qu'un avis.
class RealtimeNotices extends StatefulWidget {
  const RealtimeNotices({super.key, required this.userId, required this.child});

  /// Utilisateur connecté : ses propres actions ne sont pas signalées.
  final int userId;
  final Widget child;

  @override
  State<RealtimeNotices> createState() => _RealtimeNoticesState();
}

class _RealtimeNoticesState extends State<RealtimeNotices> {
  StreamSubscription<RealtimeChange>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_subscription?.cancel());
    _subscription = context.read<RealtimeService?>()?.changes.listen(_onChange);
  }

  void _onChange(RealtimeChange change) {
    if (change.actorId == null || change.actorId == widget.userId || !mounted) return;
    final message = noticeFor(change);
    if (message != null) Notify.info(context, message);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Texte de l'avis pour un changement, ou null s'il n'est pas signalé.
String? noticeFor(RealtimeChange change) {
  // Les noms sont enregistrés en majuscules : affichés comme dans le reste de l'application.
  final name = Formats.capitalize(change.label?.toLowerCase());
  return switch ((change.entity, change.action)) {
    ('sale', 'created') => 'Nouvelle vente ${change.label ?? ''}'.trim(),
    ('product', 'created') => name.isEmpty ? 'Nouveau produit' : 'Nouveau produit : $name',
    ('product', 'deleted') => name.isEmpty ? 'Produit supprimé' : 'Produit supprimé : $name',
    _ => null,
  };
}
