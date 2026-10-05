import 'dart:async';
import 'dart:convert';

import 'package:valmag/core/realtime/realtime_service.dart';

/// Faux WebSocket temps réel : aucune connexion réseau. Un test peut simuler le serveur
/// ([ready], [announce]) ou une coupure ([drop]).
class FakeRealtime {
  final List<Uri> connections = [];
  _FakeSocket? _current;

  RealtimeSocket connect(Uri uri) {
    connections.add(uri);
    return _current = _FakeSocket();
  }

  /// Le serveur confirme la connexion (abonnement actif).
  void ready() => _current?.send({'type': 'ready'});

  /// Le serveur annonce des changements, ex. `{'entity': 'sale', 'action': 'created', 'id': 1}`.
  void announce(List<Map<String, Object?>> changes) => _current?.send({'type': 'changes', 'changes': changes});

  /// Le serveur ferme la connexion avec ce code.
  void drop([int code = 1006]) => _current?.closeWith(code);
}

class _FakeSocket implements RealtimeSocket {
  final _messages = StreamController<dynamic>();
  int? _closeCode;

  void send(Map<String, Object?> message) => _messages.add(jsonEncode(message));

  void closeWith(int code) {
    _closeCode = code;
    unawaited(_messages.close());
  }

  @override
  Stream<dynamic> get messages => _messages.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  void close() => unawaited(_messages.close());
}
