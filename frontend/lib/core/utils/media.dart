/// Adresse complète d'un fichier : adresse web telle quelle, ou chemin servi par l'API (/media/...).
String? resolveMediaUrl(String? path, String apiBaseUrl) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return '$apiBaseUrl$path';
}
