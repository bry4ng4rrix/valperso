import 'package:dio/dio.dart';

import '../storage/key_value_store.dart';
import 'api_config.dart';
import 'api_exception.dart';
import 'paged.dart';

/// Jetons d'authentification, gardés en mémoire et enregistrés dans le stockage sécurisé.
/// Le mot de passe n'est jamais enregistré.
class TokenStore {
  TokenStore(this._store);

  final KeyValueStore _store;
  String? accessToken;
  String? refreshToken;

  bool get hasSession => refreshToken != null;

  Future<void> load() async {
    accessToken = await _store.read(StorageKeys.accessToken);
    refreshToken = await _store.read(StorageKeys.refreshToken);
  }

  Future<void> save({required String access, required String refresh}) async {
    accessToken = access;
    refreshToken = refresh;
    await _store.write(StorageKeys.accessToken, access);
    await _store.write(StorageKeys.refreshToken, refresh);
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    await _store.delete(StorageKeys.accessToken);
    await _store.delete(StorageKeys.refreshToken);
  }
}

/// Client HTTP unique de l'application. Les écrans ne l'appellent jamais directement :
/// ils passent par les repositories de chaque fonctionnalité.
///
/// - ajoute l'access token à chaque requête ;
/// - si l'API répond 401, renouvelle les jetons avec le refresh token puis rejoue la requête ;
/// - si le renouvellement échoue, efface la session et appelle [onSessionExpired] (retour au login) ;
/// - convertit toutes les erreurs en [ApiException] avec un message lisible.
class ApiClient {
  ApiClient({required String baseUrl, required this.tokens, HttpClientAdapter? adapter}) {
    final options = BaseOptions(
      baseUrl: _withPrefix(baseUrl),
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );
    _dio = Dio(options);
    // Client sans intercepteur, pour le renouvellement des jetons et le rejeu des requêtes.
    _plainDio = Dio(options);
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _plainDio.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(QueuedInterceptorsWrapper(onRequest: _onRequest, onError: _onError));
    _baseUrl = ApiConfig.normalize(baseUrl);
  }

  final TokenStore tokens;
  late final Dio _dio;
  late final Dio _plainDio;
  late String _baseUrl;

  /// Appelé quand la session ne peut plus être renouvelée.
  void Function()? onSessionExpired;

  String get baseUrl => _baseUrl;

  void updateBaseUrl(String url) {
    _baseUrl = ApiConfig.normalize(url);
    _dio.options.baseUrl = _withPrefix(_baseUrl);
    _plainDio.options.baseUrl = _withPrefix(_baseUrl);
  }

  static String _withPrefix(String url) => '${ApiConfig.normalize(url)}${ApiConfig.apiPrefix}';

  // --- Méthodes HTTP -------------------------------------------------------------------------

  Future<dynamic> get(String path, {Map<String, Object?>? query}) =>
      _send(() => _dio.get(path, queryParameters: cleanQuery(query ?? const {})));

  Future<dynamic> post(String path, {Object? data, bool authenticated = true}) => _send(
        () => _dio.post(path, data: data, options: Options(extra: {'skipAuth': !authenticated})),
      );

  Future<dynamic> put(String path, {Object? data}) => _send(() => _dio.put(path, data: data));

  Future<dynamic> patch(String path, {Object? data}) => _send(() => _dio.patch(path, data: data));

  Future<dynamic> delete(String path) => _send(() => _dio.delete(path));

  /// Télécharge un fichier binaire depuis une adresse complète (ex. logo de la société).
  Future<List<int>> getBytes(String url) async {
    final response = await _send(
      () => _plainDio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes)),
    );
    return response as List<int>;
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (error) {
      if (error.error is ApiException) throw error.error as ApiException;
      throw ApiException.fromDio(error);
    }
  }

  // --- Authentification et renouvellement des jetons -------------------------------------

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokens.accessToken;
    if (options.extra['skipAuth'] != true && token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException error, ErrorInterceptorHandler handler) async {
    final options = error.requestOptions;
    final isUnauthorized = error.response?.statusCode == 401;
    if (!isUnauthorized || options.extra['skipAuth'] == true || options.extra['retried'] == true) {
      return handler.next(error);
    }

    try {
      // Une autre requête a peut-être déjà renouvelé les jetons pendant que celle-ci attendait.
      final usedToken = '${options.headers['Authorization'] ?? ''}'.replaceFirst('Bearer ', '');
      if (tokens.accessToken == null || usedToken == tokens.accessToken) {
        await _refreshTokens();
      }
      options.extra['retried'] = true;
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      handler.resolve(await _plainDio.fetch(options));
    } on DioException catch (retryError) {
      if (retryError.response?.statusCode == 401) await _expireSession();
      handler.next(retryError);
    } catch (_) {
      await _expireSession();
      handler.next(error);
    }
  }

  Future<void> _refreshTokens() async {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null) throw StateError('Aucune session à renouveler');
    final response = await _plainDio.post('/auth/refresh', data: {'refresh_token': refreshToken});
    final data = response.data as Map;
    await tokens.save(access: '${data['access_token']}', refresh: '${data['refresh_token']}');
  }

  Future<void> _expireSession() async {
    await tokens.clear();
    onSessionExpired?.call();
  }
}
