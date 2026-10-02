import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'auth_repository.dart';
import 'current_user.dart';

enum SessionStatus { unknown, authenticated, unauthenticated }

/// État de la session : qui est connecté et avec quelles permissions.
/// Le routeur écoute ce contrôleur pour rediriger vers l'écran de connexion.
class SessionController extends ChangeNotifier {
  SessionController({required this._auth, required this._api}) {
    _api.onSessionExpired = _onSessionExpired;
  }

  final AuthRepository _auth;
  final ApiClient _api;

  SessionStatus _status = SessionStatus.unknown;
  CurrentUser? _user;
  CurrentUser? _lastUser;
  String? expiredMessage;

  SessionStatus get status => _status;
  CurrentUser? get user => _user;

  /// Utilisateur connecté, ou le dernier connu pendant la transition vers l'écran de connexion
  /// (les écrans encore affichés pendant l'animation de sortie restent ainsi valides).
  /// À n'utiliser que dans les écrans réservés aux utilisateurs connectés.
  CurrentUser get requireUser => (_user ?? _lastUser)!;
  CurrentUser? get lastUser => _user ?? _lastUser;
  bool get isAuthenticated => _status == SessionStatus.authenticated;

  bool can(String permission) => _user?.can(permission) ?? false;

  /// Au lancement : reprend la session si des jetons valides existent (renouvelés au besoin).
  Future<void> restore() async {
    await _api.tokens.load();
    if (!_api.tokens.hasSession) return _setUser(null);
    try {
      _setUser(await _auth.me());
    } on ApiException catch (error) {
      // Serveur injoignable : on garde les jetons et on laisse l'utilisateur réessayer depuis le login.
      if (error.isNetwork) {
        expiredMessage = 'Serveur injoignable. Vérifiez l\'adresse du serveur puis reconnectez-vous.';
      } else {
        await _api.tokens.clear();
      }
      _setUser(null);
    }
  }

  Future<void> login(String identifier, String password) async {
    await _auth.login(identifier, password);
    expiredMessage = null;
    _setUser(await _auth.me());
  }

  /// Recharge le profil (après une modification de ses propres informations par exemple).
  Future<void> reloadProfile() async => _setUser(await _auth.me());

  Future<void> logout() async {
    await _auth.logout();
    _setUser(null);
  }

  void _onSessionExpired() {
    if (_status != SessionStatus.authenticated) return;
    expiredMessage = 'Votre session a expiré. Reconnectez-vous.';
    _setUser(null);
  }

  void _setUser(CurrentUser? user) {
    _user = user;
    if (user != null) _lastUser = user;
    _status = user == null ? SessionStatus.unauthenticated : SessionStatus.authenticated;
    notifyListeners();
  }
}
