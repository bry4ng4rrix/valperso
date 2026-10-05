/// Ce qui diffère dans le navigateur (version web) : stockage des jetons et téléchargement de fichiers.
/// Hors navigateur (Android, Linux), les versions de `browser_io.dart` sont utilisées.
library;

export 'browser_io.dart' if (dart.library.js_interop) 'browser_web.dart';
