import 'dart:convert';
import 'dart:io';

import 'paths.dart';

/// Préférences conservées d'un lancement à l'autre, dans
/// ~/.config/lecteur/settings.json (ou $XDG_CONFIG_HOME/lecteur ; sous
/// Windows, %APPDATA%\lecteur ; sous macOS, ~/Library/Application Support/lecteur).
class Settings {
  Settings._();

  static File get _file => File(joinPath(configDir(), joinPath('lecteur', 'settings.json')));

  static Map<String, Object?>? _cache;

  /// Sous `flutter test`, les préférences restent en mémoire : les tests ne
  /// lisent ni n'écrivent celles de l'utilisateur.
  static final bool _inTest = Platform.environment.containsKey('FLUTTER_TEST');

  static Map<String, Object?> get _values {
    if (_cache != null) return _cache!;
    if (_inTest) return _cache = {};
    try {
      final decoded = jsonDecode(_file.readAsStringSync());
      _cache = decoded is Map<String, Object?> ? decoded : {};
    } catch (_) {
      _cache = {}; // fichier absent ou illisible : valeurs par défaut
    }
    return _cache!;
  }

  static String? getString(String key) {
    final v = _values[key];
    return v is String ? v : null;
  }

  static void setString(String key, String value) => _set(key, value);

  static Map<String, Object?> getMap(String key) {
    final v = _values[key];
    return v is Map<String, Object?> ? v : const {};
  }

  static void setMap(String key, Map<String, Object?> value) => _set(key, value);

  static void _set(String key, Object? value) {
    _values[key] = value;
    if (_inTest) return;
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_values));
    } catch (_) {
      // Pas grave : le choix ne sera simplement pas retenu.
    }
  }
}
