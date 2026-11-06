import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/player.dart';
import 'ipod/ipod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Fenêtre sans décor ni fond : l'iPod flotte seul sur le bureau.
  final window = _window;
  if (window != null) {
    window
      ..titleBarStyle = TitleBarStyle.hidden
      ..setSize(IpodStage.savedModel.windowSize.toNative(), false)
      ..backgroundColor = Colors.transparent.toNative()
      ..title = 'Lecteur'
      ..show()
      ..focus();
  }

  if (Platform.environment['LECTEUR_FPS'] != null) _logFrameTimings();

  final player = PlayerController();
  runApp(LecteurApp(player: player));
  player.loadLibrary();
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

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  /// Raccourcis globaux. Le baladeur gère lui-même ↑ ↓ ← → Entrée,
  /// Retour arrière et T ; ce qu'il n'utilise pas remonte jusqu'ici.
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.space:
        widget.player.playPause();
      case LogicalKeyboardKey.escape || LogicalKeyboardKey.keyQ:
        widget.player.savePlays();
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
      title: 'Lecteur',
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
          child: IpodStage(player: widget.player),
        ),
      ),
    );
  }
}
