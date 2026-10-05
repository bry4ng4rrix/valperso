import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../auth/session_controller.dart';
import '../utils/json.dart';

/// Un changement annoncé par le serveur : [entity] (sale, product, stock, movement, transfer, payment,
/// customer, category, store, user, role, company, audit, message, conversation), [action]
/// (created, updated, deleted) et [id] (pour stock : le produit ; pour message : la conversation).
class RealtimeChange {
  const RealtimeChange({required this.entity, required this.action, this.id, this.actorId, this.label});

  factory RealtimeChange.fromJson(Json json) => RealtimeChange(
    entity: '${json['entity']}',
    action: '${json['action']}',
    id: json['id'] == null ? null : toInt(json['id']),
    actorId: json['actor_id'] == null ? null : toInt(json['actor_id']),
    label: toStringOrNull(json['label']),
  );

  /// Après une reconnexion, des changements ont pu être manqués : tous les écrans se rechargent.
  static const resync = RealtimeChange(entity: '*', action: 'resync');

  final String entity;
  final String action;
  final int? id;

  /// Utilisateur à l'origine du changement (null : opération du serveur).
  final int? actorId;

  /// Libellé lisible quand le serveur le fournit (numéro de facture, nom du produit).
  final String? label;

  bool get isResync => identical(this, resync);
}

/// Connexion WebSocket ouverte. Remplacée dans les tests (pas de serveur).
abstract interface class RealtimeSocket {
  Stream<dynamic> get messages;

  /// Code de fermeture envoyé par le serveur, une fois la connexion fermée.
  int? get closeCode;

  void close();
}

typedef RealtimeConnector = RealtimeSocket Function(Uri uri);

RealtimeSocket connectWebSocket(Uri uri) => _ChannelSocket(WebSocketChannel.connect(uri));

class _ChannelSocket implements RealtimeSocket {
  _ChannelSocket(this._channel) {
    // Un échec de connexion arrive aussi dans [messages] (erreur puis fin) : rien à faire ici.
    _channel.ready.ignore();
  }

  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  int? get closeCode => _channel.closeCode;

  @override
  void close() => unawaited(_channel.sink.close());
}

/// Adresse du WebSocket à partir de celle de l'API : http → ws, https → wss.
Uri realtimeUri(String baseUrl, String token) {
  final base = Uri.parse(baseUrl);
  return base.replace(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    path: '${base.path}${ApiConfig.apiPrefix}/ws',
    queryParameters: {'token': token},
  );
}

/// Changements en temps réel annoncés par le serveur (WebSocket `/api/v1/ws`).
///
/// Connecté tant que la session est ouverte, avec reconnexion automatique. Les écrans écoutent
/// [changes] (voir `LiveRefresh`) et rechargent leurs données par l'API REST, qui reste la référence.
class RealtimeService extends ChangeNotifier {
  RealtimeService({required this._api, required this._session, RealtimeConnector? connector})
    : _connector = connector ?? connectWebSocket {
    _session.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  /// Codes de fermeture du serveur : jeton refusé, ou reconnexion demandée (droits modifiés...).
  static const closeUnauthorized = 4401;
  static const closeReconnect = 4000;

  /// Attente avant chaque nouvelle tentative (secondes), plafonnée à 30 s.
  static const _retryDelays = [1, 2, 5, 10, 20, 30];

  final ApiClient _api;
  final SessionController _session;
  final RealtimeConnector _connector;
  final _changes = StreamController<RealtimeChange>.broadcast();

  RealtimeSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  int _attempt = 0;
  bool _connected = false;
  bool _wasConnected = false;
  bool _disposed = false;

  Stream<RealtimeChange> get changes => _changes.stream;

  /// Connexion authentifiée par le serveur : les changements arrivent en direct.
  bool get isConnected => _connected;

  void _onSessionChanged() {
    if (!_session.isAuthenticated) {
      _close();
    } else if (_socket == null && _retry == null) {
      _open();
    }
  }

  void _open() {
    _retry = null;
    final token = _api.tokens.accessToken;
    if (_disposed || !_session.isAuthenticated || token == null) return;
    final socket = _socket = _connector(realtimeUri(_api.baseUrl, token));
    _subscription = socket.messages.listen(_onMessage, onError: (_) {}, onDone: () => _onClosed(socket));
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    final message = jsonDecode(data);
    if (message is! Map) return;
    switch (message['type']) {
      case 'ready':
        _attempt = 0;
        _setConnected(true);
        if (_wasConnected) _changes.add(RealtimeChange.resync);
        _wasConnected = true;
      case 'changes':
        for (final item in message['changes'] as List? ?? const []) {
          final change = RealtimeChange.fromJson(Json.from(item as Map));
          _changes.add(change);
          // Mon compte a changé (rôle, magasin, permissions) : menus et droits sont relus.
          if (change.entity == 'user' && change.id == _session.user?.id) unawaited(_reloadProfile());
        }
    }
  }

  Future<void> _onClosed(RealtimeSocket socket) async {
    if (!identical(socket, _socket)) return;
    final code = socket.closeCode;
    _socket = null;
    _subscription = null;
    _setConnected(false);
    if (_disposed || !_session.isAuthenticated) return;
    // Jeton expiré ou révoqué : l'appel REST le renouvelle (ou ferme la session s'il ne peut plus l'être).
    if (code == closeUnauthorized) await _reloadProfile();
    if (_disposed || !_session.isAuthenticated || _socket != null) return;
    final delay = code == closeReconnect ? 1 : _retryDelays[min(_attempt, _retryDelays.length - 1)];
    _attempt++;
    _retry = Timer(Duration(seconds: delay), _open);
  }

  Future<void> _reloadProfile() async {
    try {
      await _session.reloadProfile();
    } on Exception {
      // Réseau indisponible : la prochaine tentative de connexion réessaiera.
    }
  }

  void _close() {
    _retry?.cancel();
    _retry = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _socket?.close();
    _socket = null;
    _attempt = 0;
    _wasConnected = false;
    _setConnected(false);
  }

  void _setConnected(bool value) {
    if (_connected == value || _disposed) return;
    _connected = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session.removeListener(_onSessionChanged);
    _close();
    unawaited(_changes.close());
    super.dispose();
  }
}
