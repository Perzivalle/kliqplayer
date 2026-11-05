import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/player.dart';
import '../skin.dart';
import 'click.dart';
import 'nav.dart';
import 'painters.dart';
import 'screen.dart';

class IpodSkin extends Skin {
  const IpodSkin();

  @override
  String get name => 'Baladeur';

  @override
  Size get windowSize => const Size(440, 740);

  /// L'appareil seul, qui flotte au milieu d'une fenêtre transparente.
  @override
  Widget build(PlayerController player) => Center(
        child: Padding(
          // Marge pour l'ombre portée.
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: FittedBox(child: IpodDevice(player: player)),
        ),
      );
}

class IpodDevice extends StatefulWidget {
  const IpodDevice({super.key, required this.player});

  final PlayerController player;

  @override
  State<IpodDevice> createState() => _IpodDeviceState();
}

class _IpodDeviceState extends State<IpodDevice> {
  late final IpodNav _nav = IpodNav(widget.player);
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
    final wheelRect = Rect.fromLTWH(
      G.wheelCenter.dx - G.wheelRadius,
      G.wheelCenter.dy - G.wheelRadius,
      G.wheelRadius * 2,
      G.wheelRadius * 2,
    );
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: SizedBox.fromSize(
        size: G.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(child: CustomPaint(painter: BodyPainter())),
            Positioned.fromRect(
              rect: G.screen,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: FittedBox(
                  child: SizedBox.fromSize(
                    size: G.screenUi,
                    child: IpodScreen(nav: _nav, player: widget.player),
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: GlassPainter()))),
            Positioned.fromRect(rect: wheelRect, child: IpodWheel(onScroll: _scroll, onDown: _down, onUp: _up, onCancel: _cancelPress)),
          ],
        ),
      ),
    );
  }
}

/// Molette tactile : on la fait tourner en glissant en cercle (ou à la
/// molette de la souris), on clique sur ses quatre côtés ou au centre.
class IpodWheel extends StatefulWidget {
  const IpodWheel({super.key, required this.onScroll, required this.onDown, required this.onUp, required this.onCancel});

  final ValueChanged<int> onScroll;
  final ValueChanged<WheelZone> onDown;
  final ValueChanged<WheelZone> onUp;
  final VoidCallback onCancel;

  @override
  State<IpodWheel> createState() => _IpodWheelState();
}

class _IpodWheelState extends State<IpodWheel> {
  /// Un cran tous les 18° : un tour complet fait défiler 20 lignes.
  static const _step = 2 * math.pi / 20;

  WheelZone _pressed = WheelZone.none;
  Offset _downAt = Offset.zero;
  double? _lastAngle;

  /// Au-delà de ce déplacement, un appui devient une rotation et s'annule.
  /// (Un clic au pavé tactile bouge souvent de quelques pixels.)
  static const _clickTolerance = 8.0;

  void _cancelPress() {
    if (_pressed == WheelZone.none) return;
    setState(() => _pressed = WheelZone.none);
    widget.onCancel();
  }
  double _accum = 0;

  static const _c = Offset(G.wheelRadius, G.wheelRadius);

  WheelZone _zoneAt(Offset p) {
    final v = p - _c;
    final d = v.distance;
    if (d > G.wheelRadius) return WheelZone.none;
    if (d <= G.buttonRadius) return WheelZone.center;
    final a = math.atan2(v.dy, v.dx);
    if (a.abs() <= math.pi / 4) return WheelZone.next;
    if (a.abs() >= 3 * math.pi / 4) return WheelZone.previous;
    return a < 0 ? WheelZone.menu : WheelZone.playPause;
  }

  void _panStart(DragStartDetails d) {
    final v = d.localPosition - _c;
    _lastAngle = v.distance > G.buttonRadius * 0.6 ? math.atan2(v.dy, v.dx) : null;
    _accum = 0;
  }

  void _panUpdate(DragUpdateDetails d) {
    final v = d.localPosition - _c;
    if (v.distance < G.buttonRadius * 0.6) return; // trop près du centre : angle instable
    final a = math.atan2(v.dy, v.dx);
    final last = _lastAngle;
    _lastAngle = a;
    if (last == null) return;
    var delta = a - last;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _accum += delta;
    while (_accum >= _step) {
      _accum -= _step;
      widget.onScroll(1);
    }
    while (_accum <= -_step) {
      _accum += _step;
      widget.onScroll(-1);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Les appuis passent par les événements bruts du pointeur (réaction
    // immédiate, appui long possible) ; la rotation, par le glissement.
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
          widget.onScroll(e.scrollDelta.dy > 0 ? 1 : -1);
        }
      },
      onPointerDown: (e) {
        if (e.buttons != kPrimaryButton) return;
        final zone = _zoneAt(e.localPosition);
        if (zone == WheelZone.none) return;
        _downAt = e.localPosition;
        setState(() => _pressed = zone);
        widget.onDown(zone);
      },
      onPointerMove: (e) {
        if ((e.localPosition - _downAt).distance > _clickTolerance) _cancelPress();
      },
      onPointerUp: (_) {
        final zone = _pressed;
        if (zone == WheelZone.none) return;
        setState(() => _pressed = WheelZone.none);
        widget.onUp(zone);
      },
      onPointerCancel: (_) => _cancelPress(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _panStart,
        onPanUpdate: _panUpdate,
        onPanEnd: (_) => _lastAngle = null,
        child: CustomPaint(painter: WheelPainter(_pressed)),
      ),
    );
  }
}
