import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
// ignore: deprecated_member_use
import 'package:window_manager/legacy.dart';

import 'core/player.dart';
import 'skins/skin.dart';
import 'skins/turntable/turntable_skin.dart';

/// Les skins disponibles, dans l'ordre de Tab.
const List<Skin> skins = [TurntableSkin()];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final options = WindowOptions(
    size: skins.first.windowSize,
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
  int _skin = 0;

  Skin get skin => skins[_skin];

  Future<void> _nextSkin() async {
    setState(() => _skin = (_skin + 1) % skins.length);
    await windowManager.setSize(skin.windowSize, animate: true);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final p = widget.player;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.space:
        p.playPause();
      case LogicalKeyboardKey.arrowRight:
        p.next();
      case LogicalKeyboardKey.arrowLeft:
        p.previous();
      case LogicalKeyboardKey.arrowUp:
        p.setVolume(p.volume + 5);
      case LogicalKeyboardKey.arrowDown:
        p.setVolume(p.volume - 5);
      case LogicalKeyboardKey.tab:
        _nextSkin();
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
          autofocus: true,
          onKeyEvent: _onKey,
          // La scène de chaque skin a sa propre taille ; on l'adapte à la fenêtre.
          child: FittedBox(
            child: skin.build(widget.player, windowManager.startDragging),
          ),
        ),
      ),
    );
  }
}
