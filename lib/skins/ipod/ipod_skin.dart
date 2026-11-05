import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/player.dart';
import '../skin.dart';
import 'classic.dart';
import 'click.dart';
import 'model.dart';
import 'nav.dart';
import 'screen.dart';
import 'wheel.dart';

export 'wheel.dart' show IpodWheel, WheelStyle, WheelZone;

/// Un baladeur à molette ; [model] en fixe l'apparence.
class IpodSkin extends Skin {
  const IpodSkin([this.model = const ClassicModel()]);

  final IpodModel model;

  @override
  String get name => model.name;

  @override
  Size get windowSize => model.windowSize;

  /// L'appareil seul, qui flotte au milieu d'une fenêtre transparente.
  @override
  Widget build(PlayerController player) => Center(
        child: Padding(
          // Marge pour l'ombre portée.
          padding: model.margin,
          child: FittedBox(child: IpodDevice(key: ValueKey(model), model: model, player: player)),
        ),
      );
}

class IpodDevice extends StatefulWidget {
  const IpodDevice({super.key, required this.model, required this.player});

  final IpodModel model;
  final PlayerController player;

  @override
  State<IpodDevice> createState() => _IpodDeviceState();
}

class _IpodDeviceState extends State<IpodDevice> {
  late final IpodNav _nav = IpodNav(widget.player, visibleRows: widget.model.look.visibleRows);
  final _focus = FocusNode(debugLabel: 'baladeur');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    WheelClick.instance.warmUp();
  }

  @override
  void dispose() {
    _endHold();
    _nav.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    // ← → se comportent comme les côtés de la molette : appui bref pour
    // changer de morceau, appui long pour avancer / reculer.
    final side = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowRight => WheelZone.next,
      LogicalKeyboardKey.arrowLeft => WheelZone.previous,
      _ => null,
    };
    if (side != null) {
      if (e is KeyDownEvent) _down(side);
      if (e is KeyUpEvent) _up(side);
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _scroll(-1);
      case LogicalKeyboardKey.arrowDown:
        _scroll(1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        WheelClick.instance.play();
        _press(WheelZone.center);
      case LogicalKeyboardKey.backspace:
        WheelClick.instance.play();
        _press(WheelZone.menu);
      default:
        // Espace, Tab, Échap : raccourcis communs à toutes les skins.
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _scroll(int delta) {
    if (_nav.scroll(delta)) WheelClick.instance.play();
  }

  // --- Appui long sur ⏮ / ⏭ : recherche dans le morceau ---------------------

  /// Délai avant qu'un appui devienne une recherche.
  static const _holdDelay = Duration(milliseconds: 450);

  Timer? _holdTimer;
  Timer? _seekTimer;
  WheelZone? _held;
  bool _seeking = false;
  final _seekClock = Stopwatch();

  /// Bouton enfoncé : le clic sonne tout de suite, l'action attend le
  /// relâchement (ou la fin du délai pour une recherche).
  void _down(WheelZone zone) {
    if (zone == WheelZone.none || _held != null) return;
    WheelClick.instance.play();
    _held = zone;
    if (zone == WheelZone.next || zone == WheelZone.previous) {
      _holdTimer = Timer(_holdDelay, () => _startSeek(zone == WheelZone.next ? 1 : -1));
    }
  }

  void _up(WheelZone zone) {
    if (_held != zone) return;
    final wasSeeking = _seeking;
    _endHold();
    if (!wasSeeking) _press(zone);
  }

  /// Le doigt a glissé (rotation) : l'appui est annulé sans action.
  void _cancelPress() => _endHold();

  void _endHold() {
    _holdTimer?.cancel();
    _seekTimer?.cancel();
    _holdTimer = _seekTimer = null;
    _held = null;
    _seeking = false;
    _seekClock
      ..stop()
      ..reset();
  }

  /// Avance (dir = 1) ou recule de plus en plus vite tant qu'on tient :
  /// ×4 au début, ×10 après 1,5 s, ×24 après 4 s.
  void _startSeek(int dir) {
    _seeking = true;
    _seekClock.start();
    const tick = Duration(milliseconds: 80);
    _seekTimer = Timer.periodic(tick, (_) {
      final p = widget.player;
      final total = p.duration.inMilliseconds;
      if (total <= 0) return;
      final t = _seekClock.elapsedMilliseconds / 1000;
      final speed = t < 1.5 ? 4 : (t < 4 ? 10 : 24);
      final pos = p.smoothPosition.inMilliseconds + dir * speed * tick.inMilliseconds;
      p.seekProgress(pos.clamp(0, total - 500) / total);
      _nav.showScrub();
    });
  }

  void _press(WheelZone zone) {
    final p = widget.player;
    switch (zone) {
      case WheelZone.menu:
        _nav.menu();
      case WheelZone.next:
        p.next();
      case WheelZone.previous:
        p.previous();
      case WheelZone.playPause:
        p.playPause();
      case WheelZone.center:
        _nav.select();
      case WheelZone.none:
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final wheelRect = Rect.fromCircle(center: m.wheelCenter, radius: m.wheel.radius);
    final glass = m.glass;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: SizedBox.fromSize(
        size: m.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: m.body)),
            Positioned.fromRect(
              rect: m.screen,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(m.screenCornerRadius),
                child: FittedBox(
                  child: SizedBox.fromSize(
                    size: m.look.size,
                    child: IpodScreen(nav: _nav, player: widget.player, look: m.look),
                  ),
                ),
              ),
            ),
            if (glass != null) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: glass))),
            Positioned.fromRect(
              rect: wheelRect,
              child: IpodWheel(style: m.wheel, onScroll: _scroll, onDown: _down, onUp: _up, onCancel: _cancelPress),
            ),
          ],
        ),
      ),
    );
  }
}
