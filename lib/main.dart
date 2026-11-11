import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/player.dart';
import 'core/settings.dart';
import 'core/source.dart';
import 'sources/local/local_source.dart';
import 'sources/spotify/librespot.dart';
import 'sources/spotify/official_app.dart';
import 'sources/spotify/spotify_source.dart';
import 'ipod/ipod.dart';
import 'ipod/screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Fenêtre sans décor ni fond : l'iPod flotte seul sur le bureau.
  final window = _window;
  if (window != null) {
    window
      ..titleBarStyle = TitleBarStyle.hidden
      ..backgroundColor = Colors.transparent.toNative()
      ..title = 'KliqPlayer';
    if (Platform.isWindows) {
      // Windows dessine une ombre rectangulaire autour de chaque fenêtre :
      // autour d'une fenêtre transparente, elle trahirait le cadre. Et, faute
      // de gestionnaire qui range les fenêtres, celle-ci couvre toute la zone
      // de travail : l'iPod s'y déplace, le reste laisse voir (et cliquer) le
      // bureau.
      window.hasShadow = false;
      fillWorkArea(window);
    } else {
      window.setSize(IpodStage.savedModel.windowSize.toNative(), false);
    }
    window
      ..show()
      ..focus();
  }

  if (Platform.environment['LECTEUR_FPS'] != null) _logFrameTimings();

  // Restes d'anciennes versions.
  Settings.remove(const ['deck', 'ipod.zoom', 'spotify.device']);

  final player = _player();
  // Arrêté de l'extérieur (kill, fin de session) : on enregistre quand même.
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint, ProcessSignal.sighup]) {
    try {
      signal.watch().listen((_) {
        _beforeExit(player);
        exit(0);
      });
    } catch (_) {
      // (Signal inconnu de ce système : Windows n'a que SIGINT.)
    }
  }
  runApp(LecteurApp(player: player));
  player.loadLibrary();
}

/// Le lecteur, sur la source choisie dans Réglages › Bibliothèque.
PlayerController _player() {
  PlayerController? player;
  final spotify = SpotifyAccount(installedLibrespot: Librespot.find(), app: SpotifyApp.find());
  MusicSource sourceFor(String id) => switch (id) {
        'spotify' when spotify.connected => SpotifySource(spotify),
        _ => LocalSource(player?.musicDir ?? defaultMusicDirectory().path),
      };
  return player = PlayerController(
    sourceFor(Settings.getString('library.source') ?? 'local'),
    sourceFor: sourceFor,
    accounts: [spotify],
  );
}

/// Avant de quitter, d'où que vienne l'ordre (Échap, fenêtre fermée par le
/// système, signal) : ce qui tourne en arrière-plan s'arrête, ce qui
/// n'était pas encore écrit (préférences, écoutes) l'est.
void _beforeExit(PlayerController player) {
  for (final a in player.accounts) {
    a.shutdown();
  }
  Settings.flush();
}

/// La fenêtre de l'appli (null si le système ne la donne pas).
Window? get _window {
  try {
    return WindowManager.instance.getCurrent();
  } catch (_) {
    return null;
  }
}

/// LECTEUR_FPS=1 : chaque seconde d'animation, temps de construction (UI)
/// et de rendu (raster) des images, pour traquer les saccades.
void _logFrameTimings() {
  final ui = <double>[], raster = <double>[];
  var since = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      ui.add(t.buildDuration.inMicroseconds / 1000);
      raster.add(t.rasterDuration.inMicroseconds / 1000);
    }
    if (DateTime.now().difference(since).inMilliseconds < 1000) return;
    String stat(List<double> v) {
      final avg = v.reduce((a, b) => a + b) / v.length;
      final max = v.reduce((a, b) => a > b ? a : b);
      return 'moy ${avg.toStringAsFixed(1)} max ${max.toStringAsFixed(1)} ms';
    }
    final slow = [for (var i = 0; i < ui.length; i++) if (ui[i] > 16.7 || raster[i] > 16.7) i].length;
    stdout.writeln('[fps] ${ui.length} images · ui ${stat(ui)} · raster ${stat(raster)} · lentes $slow');
    ui.clear();
    raster.clear();
    since = DateTime.now();
  });
}

class LecteurApp extends StatefulWidget {
  const LecteurApp({super.key, required this.player});

  final PlayerController player;

  @override
  State<LecteurApp> createState() => _LecteurAppState();
}

class _LecteurAppState extends State<LecteurApp> {
  final _keys = FocusNode(debugLabel: 'raccourcis');

  /// La fenêtre fermée par le système (gestionnaire de fenêtres, Alt+F4…) :
  /// même sortie propre qu'avec Échap.
  late final _lifecycle = AppLifecycleListener(onExitRequested: () async {
    _beforeExit(widget.player);
    return AppExitResponse.exit;
  });

  @override
  void initState() {
    super.initState();
    _lifecycle; // (créé maintenant : il n'écoute qu'une fois construit)
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _keys.dispose();
    super.dispose();
  }

  /// Raccourcis globaux. Le baladeur gère lui-même ↑ ↓ ← → Entrée,
  /// Retour arrière, T et les lettres de Réglages › Touches ; ce qu'il
  /// n'utilise pas remonte jusqu'ici (en Z Q S D, Q sert à revenir : on
  /// quitte avec Échap).
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.space:
        widget.player.playPause();
      case LogicalKeyboardKey.escape || LogicalKeyboardKey.keyQ:
        _beforeExit(widget.player);
        exit(0);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KliqPlayer',
      color: Colors.transparent,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: Material(
        type: MaterialType.transparency,
        child: Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: _RiseIn(child: IpodStage(player: widget.player)),
        ),
      ),
    );
  }
}

/// Au lancement, l'iPod monte du bas de la fenêtre jusqu'à sa place.
///
/// Pendant la montée, l'iPod est une photo (SnapshotWidget) : chaque image
/// ne fait que déplacer cette photo au lieu de redessiner tout l'appareil.
/// L'iPod monte débranché, écran éteint ; une fois arrivé, la prise
/// descend se brancher et l'écran s'allume au clic.
/// La montée attend que la première image soit affichée, pour ne pas se
/// disputer le démarrage (compilation des shaders, chargement de la
/// bibliothèque) et sauter des images.
/// Montée « à la Apple » : la vitesse suit une cloche de Gauss (un peu
/// penchée vers l'avant). Départ tout en douceur, une vraie poussée au
/// milieu, et une longue arrivée feutrée — bien plus contrastée qu'un
/// easeInOutSine, sans le départ brutal d'un easeOutCubic.
class _GaussianRise extends Curve {
  const _GaussianRise();

  /// Sommet de la vitesse, et largeur de la cloche avant/après.
  static const _peak = 0.38, _rising = 0.13, _settling = 0.21;
  static const _steps = 512;

  /// Position cumulée (intégrale de la cloche), normalisée de 0 à 1.
  static final List<double> _table = () {
    double speed(double t) {
      final d = (t - _peak) / (t < _peak ? _rising : _settling);
      return math.exp(-0.5 * d * d);
    }

    final table = List<double>.filled(_steps + 1, 0);
    for (var i = 1; i <= _steps; i++) {
      final a = (i - 1) / _steps, b = i / _steps;
      table[i] = table[i - 1] + (speed(a) + speed(b)) / 2;
    }
    final first = table.first, total = table.last - first;
    // Les queues de la cloche ne valent pas tout à fait zéro : on recale
    // pour finir exactement à 0 et 1.
    return [for (final v in table) (v - first) / total];
  }();

  @override
  double transformInternal(double t) {
    final x = t * _steps;
    final i = x.floor().clamp(0, _steps - 1);
    return _table[i] + (_table[i + 1] - _table[i]) * (x - i);
  }
}

class _RiseIn extends StatefulWidget {
  const _RiseIn({required this.child});

  final Widget child;

  @override
  State<_RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<_RiseIn> with SingleTickerProviderStateMixin {
  late final _rise = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  late final _offset = Tween(begin: const Offset(0, 1), end: Offset.zero)
      .animate(CurvedAnimation(parent: _rise, curve: const _GaussianRise()));
  final _snap = SnapshotController(allowSnapshotting: true);

  @override
  void initState() {
    super.initState();
    screenPower.value = false;
    ipodLanded.value = false;
    _rise.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      _snap.allowSnapshotting = false;
      ipodLanded.value = true; // la prise descend, l'écran s'allumera au clic
    });
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (mounted) _rise.forward();
    });
  }

  @override
  void dispose() {
    _rise.dispose();
    _snap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offset,
      child: SnapshotWidget(
        controller: _snap,
        mode: SnapshotMode.permissive,
        // La fenêtre prend sa taille définitive pendant la montée : la photo
        // est reprise, sinon elle serait étirée.
        autoresize: true,
        child: widget.child,
      ),
    );
  }
}
