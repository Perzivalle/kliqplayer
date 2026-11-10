import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../../core/paths.dart';
import '../../core/tied_process.dart';

/// Le lecteur Spotify intégré : librespot (client Spotify Connect libre,
/// https://github.com/librespot-org/librespot), lancé en arrière-plan.
/// TinyPod devient lui-même un appareil Spotify, « TinyPod » : plus besoin
/// d'ouvrir l'appli Spotify.
///
/// librespot existe pour Linux, macOS et Windows : on le prend à côté de
/// l'appli s'il y est livré, sinon dans le PATH ($LECTEUR_LIBRESPOT pour
/// un autre chemin). La première fois, il demande sa propre connexion
/// (une page Spotify dans le navigateur) ; il la garde ensuite dans
/// ~/.config/lecteur/librespot/credentials.json.
class Librespot {
  Librespot._(this.binary);

  /// Nom de l'appareil, tel qu'il apparaît dans Spotify.
  static const deviceName = 'TinyPod';

  /// Port du retour de sa connexion (différent de celui de TinyPod).
  static const oauthPort = 43820;

  /// librespot s'il est installé, sinon null.
  static Librespot? find() {
    final bin = _locate();
    return bin == null ? null : Librespot._(bin);
  }

  static String? _locate() {
    final exe = Platform.isWindows ? 'librespot.exe' : 'librespot';
    final env = Platform.environment['LECTEUR_LIBRESPOT'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
    // Livré avec l'appli (à côté de l'exécutable).
    final bundled = joinPath(File(Platform.resolvedExecutable).parent.path, exe);
    if (File(bundled).existsSync()) return bundled;
    final dirs = (Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':');
    for (final d in [...dirs, if (!Platform.isWindows) ...['/usr/bin', '/usr/local/bin', '/opt/homebrew/bin']]) {
      if (d.isEmpty) continue;
      final f = joinPath(d, exe);
      if (File(f).existsSync()) return f;
    }
    return null;
  }

  final String binary;
  TiedProcess? _process;
  Completer<void>? _exited;

  /// Dernières lignes de son journal (pour comprendre un échec).
  final List<String> log = [];

  static String get _stateDir => joinPath(configDir(), joinPath('lecteur', 'librespot'));
  static File get _pidFile => File(joinPath(_stateDir, 'pid'));

  /// Déjà connecté à Spotify une fois (sinon le premier lancement ouvre la
  /// page de connexion).
  bool get hasCredentials => File(joinPath(_stateDir, 'credentials.json')).existsSync();

  bool get running => _process != null;

  /// Lance librespot s'il ne tourne pas.
  Future<void> start() async {
    if (_process != null) return;
    final args = [
      '--name', deviceName,
      '--device-type', 'computer',
      // Identifiants et volume ici ; morceaux en cache à part (jetables).
      '--system-cache', _stateDir,
      '--cache', joinPath(cacheDir(), joinPath('lecteur', 'librespot')),
      '--cache-size-limit', '1G',
      '--bitrate', '320',
      // On le pilote par l'API : pas besoin qu'il s'annonce sur le réseau.
      '--disable-discovery',
      if (Platform.isLinux && await _hasPulse()) ...['--backend', 'pulseaudio'],
      if (!hasCredentials) ...['--enable-oauth', '--oauth-port', '$oauthPort'],
      '--quiet',
    ];
    await Directory(_stateDir).create(recursive: true);
    final p = await TiedProcess.start(binary, args, pidFile: _pidFile);
    _process = p;
    final exited = _exited = Completer<void>();
    p.lines.listen((l) {
      log.add(l);
      if (log.length > 40) log.removeAt(0);
      // Première connexion : il donne l'adresse de la page Spotify.
      const prefix = 'Browse to: ';
      final at = l.indexOf(prefix);
      if (at >= 0) {
        launchUrl(Uri.parse(l.substring(at + prefix.length).trim()), mode: LaunchMode.externalApplication);
      }
    });
    p.exitCode.then((_) {
      if (identical(_process, p)) _process = null;
      exited.complete();
    });
  }

  static Future<bool> _hasPulse() async {
    try {
      return (await Process.run('pactl', ['info'])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Arrête librespot (en quittant).
  void stop() {
    final p = _process;
    if (p == null) return;
    _process = null;
    p.kill();
  }

  /// Attend qu'il s'arrête (échec de connexion…), au plus [timeout].
  Future<void> exited(Duration timeout) => (_exited?.future ?? Future.value()).timeout(timeout, onTimeout: () {});
}
