import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
// ignore: deprecated_member_use
import 'package:window_manager/legacy.dart';

import 'core/player.dart';
import 'ipod/ipod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final options = WindowOptions(
    size: IpodStage.savedModel.windowSize,
    title: 'Lecteur',
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  if (Platform.environment['LECTEUR_FPS'] != null) _logFrameTimings();

  final player = PlayerController();
  runApp(LecteurApp(player: player));
  player.loadLibrary();
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
        windowManager.close();
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
