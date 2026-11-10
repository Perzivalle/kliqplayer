import 'dart:async';
import 'dart:io';

import '../../core/paths.dart';
import '../../core/tied_process.dart';

/// L'appli Spotify officielle, lancée par TinyPod quand aucun appareil
/// n'est prêt : c'est elle qui joue le son, sans qu'on ait à l'ouvrir.
///
/// Sous Linux, si Xvfb est installé, elle tourne sur un écran virtuel (qui
/// n'existe qu'en mémoire) : on ne voit jamais sa fenêtre. Elle vit alors
/// avec TinyPod et s'arrête avec lui, ce qui laisse ouvrir son Spotify
/// habituel ensuite. Sous macOS, elle est lancée masquée ; sous Windows,
/// réduite.
class SpotifyApp {
  SpotifyApp._(this._command, this._args);

  final String _command;
  final List<String> _args;

  /// Comment la lancer sur ce système (null si elle n'est pas installée).
  static SpotifyApp? find() {
    if (Platform.isMacOS) {
      // -g : sans prendre le premier plan ; -j : masquée.
      if (Directory('/Applications/Spotify.app').existsSync() ||
          Directory('${homeDir()}/Applications/Spotify.app').existsSync()) {
        return SpotifyApp._('open', ['-g', '-j', '-a', 'Spotify']);
      }
      return null;
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      final exe = appData == null ? null : '$appData\\Spotify\\Spotify.exe';
      if (exe != null && File(exe).existsSync()) return SpotifyApp._(exe, ['--minimized']);
      return null;
    }
    // Linux : le paquet officiel, spotify-launcher (Arch), ou Flatpak.
    for (final name in ['spotify', 'spotify-launcher']) {
      final bin = _which(name);
      if (bin != null) return SpotifyApp._(bin, const []);
    }
    final flatpak = _which('flatpak');
    if (flatpak != null &&
        (Directory('/var/lib/flatpak/app/com.spotify.Client').existsSync() ||
            Directory('${homeDir()}/.local/share/flatpak/app/com.spotify.Client').existsSync())) {
      return SpotifyApp._(flatpak, ['run', 'com.spotify.Client']);
    }
    return null;
  }

  static String? _which(String name) {
    for (final d in [...(Platform.environment['PATH'] ?? '').split(':'), '/usr/bin', '/usr/local/bin']) {
      if (d.isEmpty) continue;
      final f = '$d/$name';
      if (File(f).existsSync()) return f;
    }
    return null;
  }

  /// L'écran virtuel (Linux), s'il est installé.
  static final String? _xvfb = Platform.isLinux ? _which('Xvfb') : null;

  /// Elle tournera sans qu'on voie sa fenêtre.
  bool get hidden => !Platform.isLinux || _xvfb != null;

  static String get _stateDir => joinPath(configDir(), joinPath('lecteur', 'spotify-app'));

  TiedProcess? _display, _app;
  DateTime _launched = DateTime(0);

  /// Lancée par nous et toujours là.
  bool get running => _app != null;

  /// La lance (pas deux fois de suite).
  Future<void> launch() async {
    if (_app != null || DateTime.now().difference(_launched) < const Duration(seconds: 30)) return;
    _launched = DateTime.now();
    final xvfb = _xvfb;
    if (xvfb == null) {
      // Visible, indépendante de TinyPod, comme si on l'avait ouverte.
      await Process.start(_command, _args, mode: ProcessStartMode.detached);
      return;
    }
    // Un écran virtuel : Xvfb choisit un numéro libre et l'écrit sur sa
    // sortie (-displayfd 1).
    final display = await TiedProcess.start(
      xvfb,
      ['-displayfd', '1', '-screen', '0', '1280x800x24', '-nolisten', 'tcp'],
      pidFile: File(joinPath(_stateDir, 'xvfb.pid')),
    );
    final String number;
    try {
      number = (await display.firstLine.timeout(const Duration(seconds: 10))).trim();
    } catch (_) {
      display.kill();
      rethrow;
    }
    _display = display;
    final app = await TiedProcess.start(
      _command,
      _args,
      // Sur l'écran virtuel, en X11 (pas sur l'écran Wayland de la session).
      environment: {'DISPLAY': ':$number', 'WAYLAND_DISPLAY': '', 'XDG_SESSION_TYPE': 'x11'},
      pidFile: File(joinPath(_stateDir, 'spotify.pid')),
    );
    _app = app;
    app.exitCode.then((_) {
      if (identical(_app, app)) stop();
    });
  }

  /// Arrête celle qu'on a lancée cachée (pas une appli ouverte par soi).
  void stop() {
    final app = _app, display = _display;
    _app = _display = null;
    _launched = DateTime(0); // on pourra la relancer tout de suite
    app?.kill();
    // L'écran en dernier : ce qui resterait de Spotify s'arrête avec lui.
    if (display != null) Timer(const Duration(seconds: 2), display.kill);
  }
}
