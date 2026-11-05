import 'package:flutter/material.dart';
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

  final player = PlayerController();
  runApp(LecteurApp(player: player));
  player.loadLibrary();
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
