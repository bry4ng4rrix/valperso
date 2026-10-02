import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeHandler = Object? Function(RequestOptions request);

/// Réponse avec un code HTTP choisi par le handler (ex. 401 la première fois, 200 ensuite).
class FakeResponse {
  const FakeResponse(this.status, this.body);

  final int status;
  final Object? body;
}

class _Route {
  _Route(this.handler, this.status);

  final FakeHandler handler;
  final int status;
}

/// Faux serveur pour les tests : remplace le réseau de Dio.
/// Les routes sont déclarées par « MÉTHODE /chemin » (sans /api/v1) et chaque requête est enregistrée.
class FakeApi implements HttpClientAdapter {
  final Map<String, _Route> _routes = {};
  final List<RequestOptions> requests = [];

  /// Requêtes sans réponse prévue (« MÉTHODE /chemin ») : un écran a appelé une route non simulée.
  final List<String> unmatched = [];

  /// Déclare une réponse. [handler] reçoit la requête (corps dans `request.data`).
  void on(String method, String path, FakeHandler handler, {int status = 200}) {
    _routes['${method.toUpperCase()} $path'] = _Route(handler, status);
  }

  /// Réponse d'erreur au format de l'API : `{detail, code, errors?}`.
  void onError(
    String method,
    String path, {
    required int status,
    required String code,
    String? detail,
    List<Object>? errors,
  }) {
    on(method, path, (_) => {'detail': detail ?? code, 'code': code, 'errors': ?errors}, status: status);
  }

  /// Requêtes reçues pour une route (ex. `calls('POST', '/sales')`).
  List<RequestOptions> calls(String method, String path) => requests
      .where((request) => request.method.toUpperCase() == method.toUpperCase() && _path(request) == path)
      .toList();

  static String _path(RequestOptions request) {
    final path = request.uri.path;
    return path.startsWith('/api/v1') ? path.substring('/api/v1'.length) : path;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final route = _routes['${options.method.toUpperCase()} ${_path(options)}'];
    if (route == null) {
      unmatched.add('${options.method.toUpperCase()} ${_path(options)}');
      return _json({'detail': 'Route non simulée : ${options.method} ${_path(options)}', 'code': 'NOT_FOUND'}, 404);
    }
    final body = route.handler(options);
    if (body is FakeResponse) return _json(body.body, body.status);
    if (route.status == 204) return ResponseBody.fromString('', 204);
    return _json(body, route.status);
  }

  ResponseBody _json(Object? body, int status) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
