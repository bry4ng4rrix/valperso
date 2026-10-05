import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'realtime_service.dart';

/// Recharge un écran quand le serveur annonce un changement qui le concerne.
///
/// [entities] : types de changements suivis (voir [RealtimeChange.entity]) ; [when] affine le choix
/// (ex. seulement la vente affichée). Plusieurs changements rapprochés ne déclenchent qu'un
/// rechargement. Après une reconnexion, l'écran se recharge toujours (changements manqués).
class LiveRefresh extends StatefulWidget {
  const LiveRefresh({super.key, required this.entities, required this.onChange, required this.child, this.when});

  final Set<String> entities;
  final VoidCallback onChange;
  final bool Function(RealtimeChange change)? when;
  final Widget child;

  @override
  State<LiveRefresh> createState() => _LiveRefreshState();
}

class _LiveRefreshState extends State<LiveRefresh> {
  static const _delay = Duration(milliseconds: 400);

  StreamSubscription<RealtimeChange>? _subscription;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Absent dans certains tests de widgets isolés : l'écran fonctionne alors sans temps réel.
    final realtime = context.read<RealtimeService?>();
    unawaited(_subscription?.cancel());
    _subscription = realtime?.changes.listen(_onChange);
  }

  void _onChange(RealtimeChange change) {
    final relevant =
        change.isResync || (widget.entities.contains(change.entity) && (widget.when?.call(change) ?? true));
    if (!relevant) return;
    _timer?.cancel();
    _timer = Timer(_delay, () {
      if (mounted) widget.onChange();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
