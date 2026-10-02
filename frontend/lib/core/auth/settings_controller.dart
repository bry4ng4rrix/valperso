import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../storage/key_value_store.dart';

/// Préférences de l'appareil : thème (sombre par défaut) et adresse de l'API.
class SettingsController extends ChangeNotifier {
  SettingsController({required this._store, required this._api});

  final KeyValueStore _store;
  final ApiClient _api;

  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;
  String get apiUrl => _api.baseUrl;

  Future<void> load() async {
    _themeMode = await _store.read(StorageKeys.themeMode) == 'light' ? ThemeMode.light : ThemeMode.dark;
    final savedUrl = await _store.read(StorageKeys.apiUrl);
    if (savedUrl != null && savedUrl.isNotEmpty) _api.updateBaseUrl(savedUrl);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _store.write(StorageKeys.themeMode, mode == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  Future<void> setApiUrl(String url) async {
    final normalized = ApiConfig.normalize(url);
    _api.updateBaseUrl(normalized);
    await _store.write(StorageKeys.apiUrl, normalized);
    notifyListeners();
  }
}
