import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/player.dart';
import '../core/settings.dart';
import '../physics.dart';
import 'classic.dart';
import 'click.dart';
import 'drawer.dart';
import 'mini.dart';
import 'model.dart';
import 'nav.dart';
import 'screen.dart';
import 'wheel.dart';

export 'wheel.dart' show IpodWheel, WheelStyle, WheelZone;

/// Tous les modèles et leurs teintes, dans l'ordre du tiroir.
const List<IpodModel> ipodModels = [
  ClassicModel(),
  MiniModel(MiniColor.argent),
  MiniModel(MiniColor.bleu),
  MiniModel(MiniColor.rose),
  MiniModel(MiniColor.vert),
  MiniModel(MiniColor.or),
];

/// L'appareil qui flotte au milieu de la fenêtre, et le tiroir des autres
/// modèles qui sort du bord droit (poignée au survol du bord, ou touche T).
///
/// Sans [initial], c'est le dernier modèle choisi dans le tiroir (retenu
/// d'un lancement à l'autre) ; avec, le modèle est imposé au départ et le
/// choix n'est pas enregistré (tests).
class IpodStage extends StatefulWidget {
  const IpodStage({super.key, required this.player, this.initial});

  final PlayerController player;
  final IpodModel? initial;

  /// Le modèle qui s'affichera au lancement.
  static IpodModel get savedModel => _IpodStageState._saved();

  @override
  State<IpodStage> createState() => _IpodStageState();
}

class _IpodStageState extends State<IpodStage> with SingleTickerProviderStateMixin {
  static const _settingsKey = 'ipod.model';

  late IpodModel _model = widget.initial ?? _saved();
  bool get _remember => widget.initial == null;

  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  /// Ouverture du tiroir (0 fermé, 1 ouvert ; un léger rebond dépasse 1).
  final _open = Spring(0, stiffness: 230, damping: 0.78);

  /// La façade qui dépasse quand la souris approche du bord.
  final _peek = Spring(0, stiffness: 420, damping: 0.9);
  bool _wantOpen = false;
  bool _nearEdge = false;

  /// Un emplacement par famille, dans l'ordre de [ipodModels].
  static final List<List<IpodModel>> _families = [
    for (final f in {for (final m in ipodModels) m.family})
      [for (final m in ipodModels) if (m.family == f) m],
  ];

  /// Teinte montrée dans l'emplacement de chaque famille.
  late final Map<String, IpodModel> _shown = {
    for (final f in _families) f.first.family: f.first,
    _model.family: _model,
  };

  static IpodModel _saved() {
    final id = Settings.getString(_settingsKey);
    return ipodModels.firstWhere((m) => m.id == id, orElse: () => ipodModels.first);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _kick() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = elapsed;
    _open.step(_wantOpen ? 1 : 0, dt);
    _peek.step(_nearEdge && !_wantOpen ? 1 : 0, dt);
    if (_open.isSettled) _open.value = _wantOpen ? 1 : 0;
    if (_peek.isSettled) _peek.value = _nearEdge && !_wantOpen ? 1 : 0;
    setState(() {});
    if (_open.isSettled && _peek.isSettled) _ticker.stop();
  }

  void _setOpen(bool open) {
    if (_wantOpen == open) return;
    _wantOpen = open;
    WheelClick.instance.play();
    _kick();
  }

  void _setNearEdge(bool near) {
    if (_nearEdge == near) return;
    _nearEdge = near;
    _kick();
  }

  void _choose(IpodModel m) {
    setState(() {
      _model = m;
      _shown[m.family] = m;
    });
    if (_remember) Settings.setString(_settingsKey, m.id);
  }

  /// Clic sur un appareil du tiroir : il passe en main, le tiroir se ferme.
  void _pick(IpodModel m) {
    _choose(m);
    _setOpen(false);
  }

  /// Clic sur une pastille : recolore la miniature, ou directement
  /// l'appareil en main si c'est sa famille (le tiroir reste ouvert).
  void _swatch(IpodModel m) {
    WheelClick.instance.play();
    if (m.family == _model.family) {
      _choose(m);
    } else {
      setState(() => _shown[m.family] = m);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.keyT) {
      _setOpen(!_wantOpen);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape && _wantOpen) {
      _setOpen(false);
      return KeyEventResult.handled; // sinon Échap quitterait l'appli
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final drawerW = (w * 0.36).clamp(190.0, 300.0);
        final open = _open.value;
        final openC = open.clamp(0.0, 1.0);
        final visible = open * drawerW + (1 - openC) * _peek.value * drawerFront;

        Widget device = AnimatedSwitcher(
          duration: const Duration(milliseconds: 480),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: Tween(begin: 0.82, end: 1.0).animate(anim), child: child),
          ),
          child: Center(
            key: ValueKey(_model.id),
            child: Padding(
              // Marge pour l'ombre portée.
              padding: _model.margin,
              child: FittedBox(child: IpodDevice(model: _model, player: widget.player)),
            ),
          ),
        );
        if (open != 0) {
          // L'appareil s'écarte et rétrécit pour laisser la place au tiroir.
          final room = ((w - drawerW) / w).clamp(0.55, 1.0);
          device = Transform.translate(
            offset: Offset(-open * drawerW / 2, 0),
            child: Transform.scale(scale: 1 + (room - 1) * openC, child: device),
          );
        }

        return Stack(
          children: [
            Positioned.fill(child: device),
            // Un clic à côté du tiroir le referme.
            if (_wantOpen)
              Positioned.fill(
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _setOpen(false)),
              ),
            // Bande sensible le long du bord droit : fait dépasser la façade.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 36,
              child: MouseRegion(
                onEnter: (_) => _setNearEdge(true),
                onExit: (_) => _setNearEdge(false),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _setOpen(true),
                ),
              ),
            ),
            if (visible > 0.5)
              Positioned(
                left: w - visible,
                top: 0,
                bottom: 0,
                // Plus large que nécessaire : le rebond ne laisse pas de vide.
                width: drawerW + 80,
                child: MouseRegion(
                  onEnter: (_) => _setNearEdge(true),
                  onExit: (_) => _setNearEdge(false),
                  child: IpodDrawer(
                    families: _families,
                    current: _model,
                    shown: _shown,
                    contentWidth: drawerW,
                    onPick: _pick,
                    onSwatch: _swatch,
                    onFront: () => _setOpen(!_wantOpen),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
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
        // Espace, T, Échap : gérés plus haut (scène, raccourcis globaux).
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
