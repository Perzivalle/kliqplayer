import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Un programme lancé en arrière-plan qui vit et meurt avec TinyPod : si
/// TinyPod disparaît sans prévenir (fenêtre fermée par le gestionnaire de
/// fenêtres, plantage), un petit gardien `sh` l'arrête quand même.
/// (Sous Windows, pas de gardien : il est arrêté à la sortie normale.)
class TiedProcess {
  TiedProcess._(this._process, this._pidFile);

  final Process _process;
  final File? _pidFile;

  int get processId => _process.pid;

  /// Ses lignes de sortie (stdout et stderr).
  final _lines = StreamController<String>.broadcast();
  Stream<String> get lines => _lines.stream;

  /// Sa première ligne de sortie (gardée même si personne n'écoutait).
  final _first = Completer<String>();
  Future<String> get firstLine => _first.future;

  void _add(String line) {
    if (!_first.isCompleted) _first.complete(line);
    _lines.add(line);
  }

  Future<int> get exitCode => _process.exitCode;

  /// Lance [executable]. [pidFile] : où noter son numéro, pour arrêter au
  /// lancement suivant un reste d'une session précédente.
  static Future<TiedProcess> start(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    File? pidFile,
  }) async {
    if (pidFile != null) await killStale(pidFile);
    final Process p;
    if (Platform.isWindows) {
      p = await Process.start(executable, args, environment: environment);
    } else {
      p = await Process.start('sh', [
        '-c',
        r'"$@" & child=$!; trap "kill $child 2>/dev/null" TERM INT; '
            r'while kill -0 $PARENT 2>/dev/null && kill -0 $child 2>/dev/null; do sleep 1; done; '
            r'kill $child 2>/dev/null; wait $child',
        'tinypod-tied',
        executable,
        ...args,
      ], environment: {...?environment, 'PARENT': '$pid'});
    }
    final t = TiedProcess._(p, pidFile);
    if (pidFile != null) {
      try {
        await pidFile.parent.create(recursive: true);
        await pidFile.writeAsString('${p.pid}');
      } catch (_) {}
    }
    for (final s in [p.stdout, p.stderr]) {
      s.transform(utf8.decoder).transform(const LineSplitter()).listen(t._add, onError: (_) {});
    }
    p.exitCode.then((_) => t._lines.close());
    return t;
  }

  /// Arrête un reste de session précédente noté dans [pidFile] (seulement
  /// si c'est bien un des nôtres : le numéro a pu être repris).
  static Future<void> killStale(File pidFile) async {
    if (Platform.isWindows) return;
    try {
      final old = int.tryParse(await pidFile.readAsString());
      if (old == null || old == pid) return;
      final ps = await Process.run('ps', ['-p', '$old', '-o', 'command=']);
      if ('${ps.stdout}'.contains('tinypod-tied')) Process.killPid(old);
    } catch (_) {}
  }

  void kill() {
    _process.kill();
    try {
      _pidFile?.deleteSync();
    } catch (_) {}
  }
}
