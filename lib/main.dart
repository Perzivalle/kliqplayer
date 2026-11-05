import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
// ignore: deprecated_member_use
import 'package:window_manager/legacy.dart';

import 'core/player.dart';
import 'skins/skin.dart';
import 'skins/ipod/ipod_skin.dart';
import 'skins/ipod/mini.dart';
import 'skins/turntable/turntable_skin.dart';

/// Les skins disponibles, dans l'ordre de Tab.
const List<Skin> skins = [IpodSkin(), IpodSkin(MiniModel()), TurntableSkin()];

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
  final _keys = FocusNode(debugLabel: 'raccourcis');

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  Skin get skin => skins[_skin];

  Future<void> _nextSkin() async {
    setState(() => _skin = (_skin + 1) % skins.length);
    // La skin quittée avait peut-être le focus : on le reprend (la nouvelle
    // peut le redemander juste après).
    WidgetsBinding.instance.addPostFrameCallback((_) => _keys.requestFocus());
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    // Pendant qu'on écrit (recherche), les touches vont au texte. Les autres
    // touches non utilisées par la skin remontent jusqu'ici.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) return KeyEventResult.ignored;
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
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: skin.build(widget.player),
        ),
      ),
    );
  }
}
