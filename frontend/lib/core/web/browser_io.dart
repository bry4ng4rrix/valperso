import '../storage/key_value_store.dart';

/// Stockage de l'application : jetons chiffrés (Keystore sur Android, libsecret sur Linux).
KeyValueStore createAppStore() => SecureKeyValueStore();

/// Téléchargement par le navigateur : uniquement dans la version web (voir `kIsWeb`).
void downloadFile(List<int> bytes, String fileName) =>
    throw UnsupportedError('Téléchargement réservé à la version web');
