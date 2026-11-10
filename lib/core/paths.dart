import 'dart:io';

import 'settings.dart';

/// Chemins propres à chaque système (Linux, Windows, macOS). Les fonctions
/// prennent [windows] pour pouvoir être essayées depuis n'importe quel
/// système ; par défaut, c'est celui sur lequel on tourne.

final bool _isWindows = Platform.isWindows;

Map<String, String> get _env => Platform.environment;

/// Dossier personnel de l'utilisateur.
String homeDir() => _env['HOME'] ?? _env['USERPROFILE'] ?? '.';

/// Dossier où ranger les préférences de l'appli.
String configDir() {
  if (_isWindows) return _env['APPDATA'] ?? '${homeDir()}\\AppData\\Roaming';
  if (Platform.isMacOS) return '${homeDir()}/Library/Application Support';
  return _env['XDG_CONFIG_HOME'] ?? '${homeDir()}/.config';
}

/// Dernier élément d'un chemin, que les séparateurs soient / ou \
/// (« C:\ » donne « C: », « / » reste « / »).
String lastSegment(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// Le chemin est-il absolu ? (« /musique », « C:\musique », « \\serveur\partage »)
bool isAbsolutePath(String path, {bool? windows}) {
  if (!(windows ?? _isWindows)) return path.startsWith('/');
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\') || path.startsWith('/');
}

/// Joint [relative] à [dir], avec le séparateur du système.
String joinPath(String dir, String relative, {bool? windows}) {
  final w = windows ?? _isWindows;
  final sep = w ? r'\' : '/';
  final rel = w ? relative.replaceAll('/', r'\') : relative;
  return dir.endsWith('/') || dir.endsWith(r'\') ? '$dir$rel' : '$dir$sep$rel';
}

/// Même fichier, même écriture : sous Windows, les / deviennent des \ (les
/// listes .m3u mélangent souvent les deux).
String normalizePath(String path, {bool? windows}) =>
    (windows ?? _isWindows) ? path.replaceAll('/', r'\') : path;

/// Lecteurs présents sous Windows (« C:\ », « D:\ »…), sans A: et B:
/// (anciens lecteurs de disquettes, lents à interroger).
List<String> windowsDrives() => [
      for (var c = 'C'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++)
        if (Directory('${String.fromCharCode(c)}:\\').existsSync()) '${String.fromCharCode(c)}:\\',
    ];

/// Dossier de musique : $LECTEUR_MUSIC s'il est donné, sinon celui choisi
/// dans Réglages › Bibliothèque, sinon celui de MPD.
Directory defaultMusicDirectory() {
  final home = homeDir();
  final override = Platform.environment['LECTEUR_MUSIC'];
  if (override != null && override.isNotEmpty) return Directory(override);
  final chosen = Settings.getString('library.folder');
  if (chosen != null && chosen.isNotEmpty) return Directory(chosen);
  return Directory(joinPath(home, joinPath('Music', 'Musique Ipod')));
}

/// Dossier où garder ce qui peut se retélécharger (pochettes en ligne).
String cacheDir() {
  if (_isWindows) return _env['LOCALAPPDATA'] ?? '${homeDir()}\\AppData\\Local';
  if (Platform.isMacOS) return '${homeDir()}/Library/Caches';
  return _env['XDG_CACHE_HOME'] ?? '${homeDir()}/.cache';
}

/// Écrit [text] dans [file] lisible par l'utilisateur seul (jetons de
/// connexion) : fichier temporaire restreint, puis renommage. Sous Windows,
/// le dossier de l'utilisateur est déjà privé.
Future<void> writePrivate(File file, String text) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString('');
  if (!_isWindows) await Process.run('chmod', ['600', tmp.path]);
  await tmp.writeAsString(text);
  await tmp.rename(file.path);
}
