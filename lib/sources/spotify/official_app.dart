import 'dart:async';
import 'dart:io';

import '../../core/paths.dart';
import '../../core/tied_process.dart';

/// L'appli Spotify officielle, lancée par KliqPlayer quand aucun appareil
/// n'est prêt : c'est elle qui joue le son, sans qu'on ait à l'ouvrir.
///
/// Sous Linux, si Xvfb est installé, elle tourne sur un écran virtuel (qui
/// n'existe qu'en mémoire) : on ne voit jamais sa fenêtre. Elle vit alors
/// avec KliqPlayer et s'arrête avec lui, ce qui laisse ouvrir son Spotify
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
      final command = windowsCommand(
        appData: Platform.environment['APPDATA'],
        localAppData: Platform.environment['LOCALAPPDATA'],
        // (Sans suivre le lien : le raccourci du Microsoft Store n'est pas
        // un fichier ordinaire.)
        exists: (path) => FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.notFound,
        protocolRegistered: _spotifyProtocol,
      );
      return command == null ? null : SpotifyApp._(command.first, command.sublist(1));
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

  /// Comment lancer Spotify sous Windows, réduite (null : pas installée) :
  /// - l'installeur classique de spotify.com la met dans %APPDATA% ;
  /// - la version empaquetée (Microsoft Store, et l'installeur récent de
  ///   spotify.com) n'y est pas : elle a un raccourci dans WindowsApps ;
  /// - à défaut, le lien « spotify: », que toute installation enregistre.
  /// Les deux dernières passent par « start », qui sait ouvrir un raccourci
  /// d'appli comme un lien, et demande une fenêtre réduite.
  static List<String>? windowsCommand({
    required String? appData,
    required String? localAppData,
    required bool Function(String path) exists,
    required bool Function() protocolRegistered,
  }) {
    if (appData != null) {
      final exe = '$appData\\Spotify\\Spotify.exe';
      if (exists(exe)) return [exe, '--minimized'];
    }
    if (localAppData != null) {
      final alias = '$localAppData\\Microsoft\\WindowsApps\\Spotify.exe';
      if (exists(alias)) return ['cmd', '/c', 'start', '', '/min', alias, '--minimized'];
    }
    if (protocolRegistered()) return const ['cmd', '/c', 'start', '', '/min', 'spotify:'];
    return null;
  }

  /// Le lien « spotify: » est enregistré sur ce PC (une appli Spotify est
  /// installée, d'où qu'elle vienne).
  static bool _spotifyProtocol() {
    try {
      return Process.runSync('reg', ['query', r'HKCR\spotify', '/ve']).exitCode == 0;
    } catch (_) {
      return false;
    }
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

  /// Un numéro d'écran X que personne n'utilise : ni verrou, ni prise
  /// (Hyprland nomme la sienne « X0_ »).
  static int _freeDisplay() {
    bool there(String path) => FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.notFound;
    for (var n = 90; n < 190; n++) {
      if (!there('/tmp/.X$n-lock') && !there('/tmp/.X11-unix/X$n') && !there('/tmp/.X11-unix/X${n}_')) return n;
    }
    throw StateError('Xvfb : aucun écran libre');
  }

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
      // Visible, indépendante de KliqPlayer, comme si on l'avait ouverte.
      await Process.start(_command, _args, mode: ProcessStartMode.detached);
      return;
    }
    // Un écran virtuel, sous un numéro libre choisi ici. (Laissé choisir
    // seul, Xvfb ne regarde pas les verrous : sous Hyprland il prenait :0,
    // l'écran des applis X11 de la session, qui ne pouvaient plus s'ouvrir.)
    final wanted = _freeDisplay();
    final display = await TiedProcess.start(
      xvfb,
      [':$wanted', '-displayfd', '1', '-screen', '0', '1280x800x24', '-nolisten', 'tcp'],
      pidFile: File(joinPath(_stateDir, 'xvfb.pid')),
    );
    // Prêt : il écrit son numéro sur sa sortie (-displayfd 1).
    final String number;
    try {
      number = (await display.firstLine.timeout(const Duration(seconds: 10))).trim();
      if (number != '$wanted') throw StateError('Xvfb : $number');
    } catch (_) {
      display.kill();
      _launched = DateTime(0);
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
