import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'paths.dart';

/// Un fichier JSON du dossier de l'appli (~/.config/lecteur, ou
/// $XDG_CONFIG_HOME/lecteur ; sous Windows, %APPDATA%\lecteur ; sous macOS,
/// ~/Library/Application Support/lecteur), gardé en mémoire et réécrit un
/// peu après chaque changement.
class JsonStore {
  JsonStore(this.name) {
    _all.add(this);
  }

  /// Nom du fichier (« settings.json »).
  final String name;

  static final List<JsonStore> _all = [];

  File get _file => File(joinPath(configDir(), joinPath('lecteur', name)));

  Map<String, Object?>? _cache;

  /// Sous `flutter test`, tout reste en mémoire : les tests ne lisent ni
  /// n'écrivent les fichiers de l'utilisateur.
  static final bool inTest = Platform.environment.containsKey('FLUTTER_TEST');

  Map<String, Object?> get values {
    if (_cache != null) return _cache!;
    if (inTest) return _cache = {};
    final file = _file;
    String text;
    try {
      text = file.readAsStringSync();
    } catch (_) {
      return _cache = {}; // pas encore de fichier : valeurs par défaut
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) return _cache = decoded;
    } catch (_) {}
    // Illisible (modifié à la main, écriture coupée) : on repart de zéro,
    // mais sans l'écraser pour de bon. Il est mis de côté, récupérable.
    if (text.trim().isNotEmpty) {
      try {
        file.copySync('${file.path}.illisible');
      } catch (_) {}
    }
    return _cache = {};
  }

  /// Une valeur a changé : le fichier sera réécrit.
  void changed() {
    if (inTest) return;
    _changed = true;
    // Écrire le fichier bloquait l'appli ~60 ms, en pleine animation (choix
    // d'un iPod, d'une teinte) : on regroupe les changements et on écrit un
    // peu plus tard, en arrière-plan.
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 400), _save);
  }

  Timer? _pending;
  bool _changed = false;
  Future<void> _writing = Future.value();

  String get _text => const JsonEncoder.withIndent('  ').convert(values);

  void _save() {
    _pending = null;
    final text = _text;
    // Une écriture à la fois, dans l'ordre ; fichier temporaire puis
    // renommage, pour ne jamais laisser un fichier à moitié écrit.
    _writing = _writing.then((_) async {
      try {
        final tmp = File('${_file.path}.tmp');
        await _file.parent.create(recursive: true);
        await tmp.writeAsString(text);
        await tmp.rename(_file.path);
      } catch (_) {
        // Pas grave : le choix ne sera simplement pas retenu.
      }
    });
  }

  /// Avant de quitter : écrit tout de suite ce qui attend encore.
  void flush() {
    // (Même sans écriture en attente : celle en cours serait coupée.)
    if (!_changed) return;
    _pending?.cancel();
    _pending = null;
    try {
      _file.parent.createSync(recursive: true);
      // (Autre fichier temporaire que l'écriture en arrière-plan, qui peut
      // être en train de remplir le sien.)
      final tmp = File('${_file.path}.tmp-fin')..writeAsStringSync(_text);
      tmp.renameSync(_file.path);
    } catch (_) {}
  }

  /// Avant de quitter : tous les fichiers.
  static void flushAll() {
    for (final s in _all) {
      s.flush();
    }
  }
}

/// Préférences conservées d'un lancement à l'autre, dans settings.json.
class Settings {
  Settings._();

  static final _store = JsonStore('settings.json');

  static Map<String, Object?> get _values => _store.values;

  static String? getString(String key) {
    final v = _values[key];
    return v is String ? v : null;
  }

  static void setString(String key, String value) {
    if (_values[key] == value) return;
    _values[key] = value;
    _store.changed();
  }

  static Map<String, Object?> getMap(String key) {
    final v = _values[key];
    return v is Map<String, Object?> ? v : const {};
  }

  /// Oublie des préférences (anciennes versions, données déplacées).
  static void remove(Iterable<String> keys) {
    var any = false;
    for (final k in keys) {
      if (_values.containsKey(k)) {
        _values.remove(k);
        any = true;
      }
    }
    if (any) _store.changed();
  }

  /// Avant de quitter : écrit tout de suite ce qui attend encore
  /// (préférences et autres fichiers de l'appli).
  static void flush() => JsonStore.flushAll();
}
