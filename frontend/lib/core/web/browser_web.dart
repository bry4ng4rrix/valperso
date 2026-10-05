import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../storage/key_value_store.dart';

/// Dans le navigateur, le stockage chiffré exige HTTPS (WebCrypto) : les jetons sont gardés
/// dans le localStorage du site, comme pour toute application web.
KeyValueStore createAppStore() => _LocalStorageKeyValueStore();

class _LocalStorageKeyValueStore implements KeyValueStore {
  static const _prefix = 'valmag.';

  web.Storage get _storage => web.window.localStorage;

  @override
  Future<String?> read(String key) async => _storage.getItem('$_prefix$key');

  @override
  Future<void> write(String key, String value) async => _storage.setItem('$_prefix$key', value);

  @override
  Future<void> delete(String key) async => _storage.removeItem('$_prefix$key');
}

/// Fait télécharger le fichier par le navigateur (dossier Téléchargements de l'utilisateur).
void downloadFile(List<int> bytes, String fileName) {
  final blob = web.Blob(<JSAny>[Uint8List.fromList(bytes).toJS].toJS, web.BlobPropertyBag(type: _mimeType(fileName)));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  // Firefox ne télécharge que si le lien est dans la page.
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Laisse au navigateur le temps de lire le fichier avant de libérer la mémoire.
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
}

String _mimeType(String fileName) => switch (fileName.split('.').last.toLowerCase()) {
  'pdf' => 'application/pdf',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  _ => 'application/octet-stream',
};
