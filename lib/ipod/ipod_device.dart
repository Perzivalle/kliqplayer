part of 'ipod.dart';

class IpodDevice extends StatefulWidget {
  const IpodDevice({
    super.key,
    required this.model,
    required this.player,
    required this.nav,
    this.onWindowDrag,
    this.onHoldBegin,
    this.onHoldUpdate,
    this.onHoldEnd,
  });

  final IpodModel model;
  final PlayerController player;

  /// Navigation de la scène, passée d'un appareil à l'autre.
  final IpodNav nav;

  /// On commence à déplacer la fenêtre en tenant l'appareil.
  final VoidCallback? onWindowDrag;

  /// On tient l'appareil pour le glisser dans la fenêtre (plein écran, sous
  /// Windows) au lieu de déplacer la fenêtre : position du pointeur à
  /// l'écran, du début à la fin. [onHoldBegin] répond faux quand la scène
  /// ne s'en charge pas : c'est alors la fenêtre qu'on déplace.
  final bool Function(Offset pointer)? onHoldBegin;
  final ValueChanged<Offset>? onHoldUpdate;
  final VoidCallback? onHoldEnd;

  @override
  State<IpodDevice> createState() => _IpodDeviceState();
}

class _IpodDeviceState extends State<IpodDevice> {
  IpodNav get _nav => widget.nav;
  final _focus = FocusNode(debugLabel: 'baladeur');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    WheelClick.instance.warmUp();
    JackStatic.instance.warmUp();
  }

  @override
  void dispose() {
    _endHold();
    _ledTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// Le verrou est mis : molette, boutons et touches ne font plus rien.
  bool get _locked => widget.model.hasScreen && _nav.locked;

  /// L'interrupteur de la tranche : le verrou, ou sur un shuffle (qui n'a
  /// pas d'écran à verrouiller) le choix entre lecture dans l'ordre et
  /// aléatoire.
  bool get _switchOn => widget.model.hasScreen ? _nav.locked : !widget.player.forcedShuffle;

  void _flipSwitch() {
    WheelClick.instance.play();
    if (widget.model.hasScreen) {
      _nav.toggleLock();
    } else {
      final ordered = widget.player.forcedShuffle;
      Settings.setString('shuffle.order', ordered ? 'on' : 'off');
      widget.player.setForcedShuffle(!ordered);
      _blink();
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (_locked) {
      // Les touches du baladeur sont prises (sans effet) ; les autres
      // (Espace, T, Échap) passent.
      final keys = _nav.keys;
      final ours = {
        LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter,
        LogicalKeyboardKey.backspace, keys.up, keys.down, keys.enter, keys.back,
      };
      return ours.contains(e.logicalKey) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (e is KeyDownEvent) _nav.touch();
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
    // Les lettres choisies dans Réglages › Touches (H J K L comme dans
    // vim, W A S D ou Z Q S D) : monter, descendre, entrer, revenir (MENU).
    final keys = _nav.keys;
    final k = e.logicalKey;
    switch (k) {
      case LogicalKeyboardKey.arrowUp:
      case _ when k == keys.up:
        _scroll(-1);
      case LogicalKeyboardKey.arrowDown:
      case _ when k == keys.down:
        _scroll(1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
      case _ when k == keys.enter:
        if (e is KeyRepeatEvent) return KeyEventResult.handled;
        WheelClick.instance.play();
        _press(WheelZone.center);
      case LogicalKeyboardKey.backspace:
      case _ when k == keys.back:
        if (e is KeyRepeatEvent) return KeyEventResult.handled;
        WheelClick.instance.play();
        _press(WheelZone.menu);
      default:
        // Espace, T, Échap : gérés plus haut (scène, raccourcis globaux).
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Voyant du shuffle : un éclair vert à chaque appui.
  bool _led = false;
  Timer? _ledTimer;

  void _blink() {
    _ledTimer?.cancel();
    setState(() => _led = true);
    _ledTimer = Timer(const Duration(milliseconds: 380), () {
      if (mounted) setState(() => _led = false);
    });
  }

  /// Le gestionnaire de fenêtres prend la main : la fenêtre suit le
  /// pointeur jusqu'au relâchement (sans effet sans vraie fenêtre, dans
  /// les tests).
  void _moveWindow() {
    widget.onWindowDrag?.call();
    try {
      WindowManager.instance.getCurrent()?.startDragging();
    } catch (_) {}
  }

  void _scroll(int delta) {
    if (_locked) return;
    _nav.touch();
    // Sans écran (shuffle), la molette de la souris règle le volume.
    if (!widget.model.hasScreen) {
      widget.player.setVolume(widget.player.volume - delta * 4);
      return;
    }
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
    if (_locked) return;
    _nav.touch();
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
    if (!widget.model.hasScreen) {
      _blink();
      // Anneau d'un shuffle : + et − en haut et en bas, ⏯ au centre.
      switch (zone) {
        case WheelZone.menu:
          p.setVolume(p.volume + 8);
        case WheelZone.playPause:
          p.setVolume(p.volume - 8);
        case WheelZone.center:
          p.playPause();
        case WheelZone.next:
          p.next();
        case WheelZone.previous:
          p.previous();
        case WheelZone.none:
      }
      return;
    }
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
            ?_hold(m),
            // On attrape l'iPod n'importe où (sauf la molette et les boutons,
            // posés par-dessus) pour déplacer la fenêtre.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  if (!(widget.onHoldBegin?.call(d.globalPosition) ?? false)) _moveWindow();
                },
                onPanUpdate: (d) => widget.onHoldUpdate?.call(d.globalPosition),
                onPanEnd: (_) => widget.onHoldEnd?.call(),
                onPanCancel: () => widget.onHoldEnd?.call(),
                child: CustomPaint(painter: m.body),
              ),
            ),
            ?_holdTouch(m),
            if (m.led case final x?)
              Positioned(
                left: x - 7,
                top: -5,
                width: 14,
                height: 8,
                child: IgnorePointer(child: CustomPaint(painter: _LedPainter(_led))),
              ),
            if (m.hasScreen) Positioned.fromRect(
              rect: m.screen,
              // L'écran laisse passer la main jusqu'au boîtier.
              child: IgnorePointer(child: ClipRRect(
                borderRadius: BorderRadius.circular(m.screenCornerRadius),
                child: FittedBox(
                  child: SizedBox.fromSize(
                    size: m.look.size,
                    // Couche à part : l'écran s'anime (menus, Cover Flow,
                    // progression) sans faire repeindre la coque autour.
                    child: RepaintBoundary(child: IpodScreen(nav: _nav, player: widget.player, look: m.look)),
                  ),
                ),
              )),
            ),
            if (glass != null)
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: glass)),
              ),
            for (final b in m.buttons)
              Positioned.fromRect(
                rect: Rect.fromCircle(center: b.center, radius: b.radius),
                child: _HardButton(
                  paint: (pressed) => m.buttonPainter(b, pressed: pressed)!,
                  onDown: () => _down(b.zone),
                  onUp: () => _up(b.zone),
                  onCancel: _cancelPress,
                ),
              ),
            Positioned.fromRect(
              rect: wheelRect,
              child: IpodWheel(style: m.wheel, onScroll: _scroll, onDown: _down, onUp: _up, onCancel: _cancelPress),
            ),
          ],
        ),
      ),
    );
  }

  /// Le verrou, qui dépasse de la tranche.
  Widget? _hold(IpodModel m) {
    final h = m.hold;
    if (h == null) return null;
    return Positioned(
      left: h.x - h.width / 2,
      top: h.onTop ? -HoldPainter.depth : null,
      bottom: h.onTop ? null : -HoldPainter.depth,
      width: h.width,
      height: HoldPainter.depth,
      child: ListenableBuilder(
        listenable: Listenable.merge([_nav, widget.player]),
        builder: (context, _) => CustomPaint(painter: HoldPainter(h, on: _switchOn)),
      ),
    );
  }

  /// Où on clique pour le pousser : le bord du boîtier, juste sous lui (ce
  /// qui dépasse est trop fin, et hors du boîtier).
  Widget? _holdTouch(IpodModel m) {
    final h = m.hold;
    if (h == null) return null;
    return Positioned(
      left: h.x - h.width / 2 - 4,
      top: h.onTop ? 0 : null,
      bottom: h.onTop ? null : 0,
      width: h.width + 8,
      height: 12,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('hold'),
          behavior: HitTestBehavior.opaque,
          onTap: _flipSwitch,
        ),
      ),
    );
  }
}

/// Bouton rond à part (3e génération) : enfoncé dès qu'on appuie, action
/// au relâchement (ou appui long), comme les côtés de la molette.
class _HardButton extends StatefulWidget {
  const _HardButton({required this.paint, required this.onDown, required this.onUp, required this.onCancel});

  final CustomPainter Function(bool pressed) paint;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final VoidCallback onCancel;

  @override
  State<_HardButton> createState() => _HardButtonState();
}

class _HardButtonState extends State<_HardButton> {
  bool _pressed = false;
  Offset _downAt = Offset.zero;

  void _cancel() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (e.buttons != kPrimaryButton) return;
        _downAt = e.localPosition;
        setState(() => _pressed = true);
        widget.onDown();
      },
      onPointerMove: (e) {
        if ((e.localPosition - _downAt).distance > 8) _cancel();
      },
      onPointerUp: (_) {
        if (!_pressed) return;
        setState(() => _pressed = false);
        widget.onUp();
      },
      onPointerCancel: (_) => _cancel(),
      child: CustomPaint(painter: widget.paint(_pressed)),
    );
  }
}
