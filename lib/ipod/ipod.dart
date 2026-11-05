import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/player.dart';
import '../core/settings.dart';
import '../physics.dart';
import 'classic.dart';
import 'click.dart';
import 'drawer.dart';
import 'jack.dart';
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

/// Étapes d'un changement d'appareil.
enum _Swap {
  none,

  /// La prise sort d'un coup sec, puis remonte hors de la fenêtre.
  unplugging,

  /// L'appareil en main vole jusqu'à son emplacement du tiroir.
  stowing,

  /// Le nouveau sort de son emplacement et vient au centre.
  unstowing,

  /// La prise redescend et s'enfiche.
  plugging,
}

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

  /// Décalage vertical du tiroir quand on le tire de travers : un ressort
  /// le ramène toujours dans l'axe.
  final _lift = Spring(0, stiffness: 320, damping: 0.55);

  // Tiroir tenu à la main.
  bool _dragging = false;
  double _dragStart = 0;
  Offset _drag = Offset.zero;
  double _drawerW = 300;

  /// Un emplacement par famille, dans l'ordre de [ipodModels].
  static final List<List<IpodModel>> _families = [
    for (final f in {for (final m in ipodModels) m.family})
      [
        for (final m in ipodModels)
          if (m.family == f) m,
      ],
  ];

  /// Teinte montrée dans l'emplacement de chaque famille.
  late final Map<String, IpodModel> _shown = {
    for (final f in _families) f.first.family: f.first,
    _model.family: _model,
  };

  // --- Prise jack et changement d'appareil ------------------------------------

  _Swap _phase = _Swap.none;
  IpodModel? _incoming;

  /// Hauteur dont la prise est sortie, en unités de l'appareil (0 = enfoncée).
  final _plug = Spring(0, stiffness: 500, damping: 0.55);
  double _plugTarget = 0;
  double _plugHold = 0;
  bool _plugClicked = false;

  /// La musique jouait quand on a débranché : elle reprendra au branchement.
  bool _resumeOnPlug = false;

  /// Hauteur du « pop » quand on arrache la prise, avant qu'elle s'en aille.
  static const double _popHeight = 46;

  /// Vol d'un appareil entre le centre et le tiroir (0 → 1).
  final _fly = Spring(0, stiffness: 150, damping: 0.86);
  Rect? _natural; // où l'appareil serait sans le vol
  Rect? _flyFrom;
  Rect? _flyTo;
  bool _hideDevice = false;

  /// Ballant du câble, relancé quand l'appareil bouge.
  final _sway = Spring(0, stiffness: 55, damping: 0.28);
  double? _lastSocketX;

  final _stageKey = GlobalKey();
  final Map<String, GlobalKey> _deviceKeys = {};
  late final Map<String, GlobalKey> _slotKeys = {for (final f in _families) f.first.family: GlobalKey()};

  GlobalKey _deviceKey(IpodModel m) => _deviceKeys.putIfAbsent(m.id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    if (_remember) {
      // Au lancement, la prise vient se brancher.
      _plug.value = JackGeometry.away;
      _startPlugging();
    }
  }

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
    if (!_dragging) {
      _open.step(_wantOpen ? 1 : 0, dt);
      _lift.step(0, dt);
      if (_open.isSettled) _open.value = _wantOpen ? 1 : 0;
      if (_lift.isSettled) _lift.value = 0;
    }
    _peek.step(_nearEdge && !_wantOpen && !_dragging ? 1 : 0, dt);
    if (_peek.isSettled) _peek.value = _nearEdge && !_wantOpen && !_dragging ? 1 : 0;
    _stepSwap(dt);
    _stepSway(dt);
    setState(() {});
    if (!_dragging &&
        _phase == _Swap.none &&
        _open.isSettled &&
        _peek.isSettled &&
        _lift.isSettled &&
        _sway.isSettled &&
        _plug.isSettled) {
      _ticker.stop();
    }
  }

  // --- Changement d'appareil : débrancher, ranger, sortir, brancher ----------

  /// Rectangle d'un widget dans le repère de la scène (transformations comprises).
  Rect? _rectOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    final stage = _stageKey.currentContext?.findRenderObject();
    if (box is! RenderBox || stage is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(box.getTransformTo(stage), Offset.zero & box.size);
  }

  void _startSwap(IpodModel to) {
    // Prise arrachée : plus de son, comme avec de vrais écouteurs.
    _resumeOnPlug = widget.player.playing;
    if (_resumeOnPlug) widget.player.pause();
    _incoming = to;
    _phase = _Swap.unplugging;
    _plugTarget = _popHeight;
    _plug
      ..stiffness = 520
      ..damping = 0.5;
    _plugHold = 0;
    _kick();
  }

  void _startPlugging() {
    _phase = _Swap.plugging;
    _plugTarget = 0;
    _plugClicked = false;
    _plug
      ..stiffness = 170
      ..damping = 0.9
      ..velocity = 0;
    _kick();
  }

  void _stepSwap(double dt) {
    _plug.step(_plugTarget, dt);
    // La prise bute au fond de la prise femelle : petit rebond et clic.
    if (_plug.value < 0) {
      _plug.value = 0;
      if (_plug.velocity < 0) _plug.velocity = -_plug.velocity * 0.22;
      if (!_plugClicked) {
        _plugClicked = true;
        WheelClick.instance.play();
        // Rebranchée : la musique reprend là où elle s'était arrêtée.
        if (_resumeOnPlug) {
          _resumeOnPlug = false;
          widget.player.play();
        }
      }
    }

    switch (_phase) {
      case _Swap.none:
        break;
      case _Swap.unplugging:
        if (_plugTarget == _popHeight) {
          // Arrachée : elle marque un temps, puis s'en va vers le haut.
          if (_plug.value > _popHeight * 0.8) _plugHold += dt;
          if (_plugHold > 0.14) {
            _plugTarget = JackGeometry.away;
            _plug
              ..stiffness = 40
              ..damping = 1;
          }
        } else if (_plug.value > JackGeometry.away * 0.45) {
          _beginFlight(stowing: true);
        }
      case _Swap.stowing:
        _fly.step(1, dt);
        if (_fly.value > 0.995 && _fly.velocity.abs() < 0.2) _landStowed();
      case _Swap.unstowing:
        if (_flyFrom == null) {
          // L'appareil vient d'être construit (invisible) : on mesure.
          _beginFlight(stowing: false);
        } else {
          _fly.step(1, dt);
          if (_fly.value > 0.995 && _fly.velocity.abs() < 0.2) _landOut();
        }
      case _Swap.plugging:
        if (_plugClicked && _plug.isSettled) {
          _plug.value = 0;
          _phase = _Swap.none;
          _wantOpen = false; // le tiroir se referme une fois branché
        }
    }
  }

  void _beginFlight({required bool stowing}) {
    final model = stowing ? _model : _incoming!;
    final natural = _rectOf(_deviceKey(model));
    final slot = _rectOf(_slotKeys[model.family]);
    if (natural == null || slot == null) {
      // Rien à mesurer (fenêtre minuscule…) : on échange sans voler.
      _flyFrom = null;
      if (stowing) {
        _landStowed();
      } else {
        _landOut();
      }
      return;
    }
    _natural = natural;
    _flyFrom = stowing ? natural : slot;
    _flyTo = stowing ? slot : natural;
    _fly
      ..value = 0
      ..velocity = 0;
    _hideDevice = false;
    _phase = stowing ? _Swap.stowing : _Swap.unstowing;
  }

  void _landStowed() {
    _choose(_incoming!);
    // Le nouveau est construit au centre mais caché, le temps de le mesurer.
    _hideDevice = true;
    _flyFrom = null;
    _phase = _Swap.unstowing;
  }

  void _landOut() {
    _flyFrom = _flyTo = _natural = null;
    _hideDevice = false;
    _incoming = null;
    _startPlugging();
  }

  /// Transformation qui amène l'appareil de sa place naturelle à sa
  /// position de vol (avec un petit arc vers le haut).
  Matrix4? _flightTransform() {
    final from = _flyFrom, to = _flyTo, natural = _natural;
    if (from == null || to == null || natural == null) return null;
    final t = _fly.value;
    final r = Rect.lerp(from, to, t)!.shift(Offset(0, -math.sin(t.clamp(0.0, 1.0) * math.pi) * 36));
    return Matrix4.identity()
      ..translateByDouble(r.left, r.top, 0, 1)
      ..scaleByDouble(r.width / natural.width, r.height / natural.height, 1, 1)
      ..translateByDouble(-natural.left, -natural.top, 0, 1);
  }

  /// Le câble ondule quand l'appareil se déplace.
  void _stepSway(double dt) {
    final rect = _rectOf(_deviceKeys[_model.id]);
    final x = rect?.left;
    if (x != null && _lastSocketX != null && dt > 0) {
      final v = (x - _lastSocketX!) / dt;
      _sway.velocity -= v * 0.9 * dt * 60 / 60;
    }
    _lastSocketX = x;
    _sway.step(0, dt);
  }

  /// Câble et prise, recalculés au moment de peindre (toujours collés à
  /// l'appareil, même quand il bouge).
  JackPainter _jack() {
    final box = _deviceKeys[_model.id]?.currentContext?.findRenderObject();
    final stage = _stageKey.currentContext?.findRenderObject();
    if (_hideDevice || box is! RenderBox || stage is! RenderBox || !box.hasSize) {
      return const JackPainter(socket: null, scale: 1, lift: 0, anchorX: 0, sway: 0);
    }
    final m = box.getTransformTo(stage);
    final socket = MatrixUtils.transformPoint(m, Offset(_model.jackX, 0));
    final scale = MatrixUtils.transformRect(m, Offset.zero & box.size).width / box.size.width;
    return JackPainter(
      socket: socket,
      scale: scale,
      lift: _plug.value,
      // Le câble pend depuis là où serait la prise, tiroir fermé.
      anchorX: socket.dx + _open.value.clamp(0.0, 1.0) * _drawerW * 0.35,
      sway: _sway.value,
    );
  }

  // --- Tirer le tiroir à la main ---------------------------------------------

  /// Élastique façon iOS : plus on tire au-delà de la butée, plus ça résiste,
  /// sans jamais dépasser [limit].
  static double _rubber(double over, double limit) {
    final x = over.abs();
    return over.sign * (1 - 1 / (x * 0.55 / limit + 1)) * limit;
  }

  void _dragBegin(DragStartDetails _) {
    // Reprend le tiroir là où il est (y compris la façade qui dépasse).
    final visible = _open.value * _drawerW + (1 - _open.value.clamp(0.0, 1.0)) * _peek.value * drawerFront;
    _open
      ..value = visible / _drawerW
      ..velocity = 0;
    _peek
      ..value = 0
      ..velocity = 0;
    _dragStart = _open.value;
    _drag = Offset(0, _lift.value);
    _dragging = true;
    _kick();
  }

  void _dragUpdate(DragUpdateDetails d) {
    _drag += d.delta;
    final raw = _dragStart - _drag.dx / _drawerW;
    _open.value = raw <= 1 ? raw.clamp(0.0, 1.0) : 1 + _rubber(raw - 1, 0.35);
    _lift.value = _rubber(_drag.dy, 36);
    setState(() {});
  }

  void _dragEnd(DragEndDetails d) {
    _dragging = false;
    final v = d.velocity.pixelsPerSecond;
    // Vitesse en « tiroirs par seconde » ; on projette où l'élan l'emmène.
    final vel = (-v.dx / _drawerW).clamp(-14.0, 14.0);
    final open = _open.value + vel * 0.18 > 0.5;
    if (open != _wantOpen) {
      _wantOpen = open;
      WheelClick.instance.play();
    }
    // Le ressort repart avec la vitesse de la main : pas d'à-coup au lâcher.
    _open.velocity = vel;
    _lift.velocity = v.dy.clamp(-1500.0, 1500.0) * 0.4;
    _kick();
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

  /// Clic sur un appareil du tiroir : on débranche celui en main, il se
  /// range, l'autre sort et se branche, puis le tiroir se referme.
  void _pick(IpodModel m) {
    if (_phase != _Swap.none || m.id == _model.id) return;
    setState(() => _shown[m.family] = m);
    _startSwap(m);
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
    // Débranché : Espace ne relance pas la musique dans le vide.
    if (_phase != _Swap.none && e.logicalKey == LogicalKeyboardKey.space) return KeyEventResult.handled;
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
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final drawerW = _drawerW = (w * 0.36).clamp(190.0, 300.0);
          final open = _open.value;
          final openC = open.clamp(0.0, 1.0);
          final visible = open * drawerW + (1 - openC) * _peek.value * drawerFront;

          Widget device = AnimatedSwitcher(
            // Pendant un échange, c'est le vol qui anime : pas de fondu.
            duration: _phase == _Swap.none ? const Duration(milliseconds: 480) : Duration.zero,
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(scale: Tween(begin: 0.82, end: 1.0).animate(anim), child: child),
            ),
            child: Center(
              key: ValueKey(_model.id),
              child: Padding(
                // Marge pour l'ombre portée, et de la place en haut pour la
                // prise et le câble.
                padding: _model.margin.copyWith(top: math.max(_model.margin.top, box.maxHeight * 0.2)),
                child: FittedBox(
                  child: IpodDevice(key: _deviceKey(_model), model: _model, player: widget.player),
                ),
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

          if (_hideDevice) device = Opacity(opacity: 0, child: device);
          final flight = _flightTransform();
          if (flight != null) device = Transform(transform: flight, child: device);
          // En vol, l'appareil passe au-dessus du tiroir.
          final flying = _phase == _Swap.stowing || _phase == _Swap.unstowing;
          final deviceLayer = Positioned.fill(key: const ValueKey('appareil'), child: device);

          return IgnorePointer(
            ignoring: _phase != _Swap.none,
            child: Stack(
              key: _stageKey,
              children: [
                if (!flying) deviceLayer,
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
                      // Compte depuis le point d'appui : le tiroir colle au pointeur.
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: _dragBegin,
                      onPanUpdate: _dragUpdate,
                      onPanEnd: _dragEnd,
                    ),
                  ),
                ),
                if (visible > 0.5)
                  Positioned(
                    left: w - visible,
                    top: _lift.value,
                    bottom: -_lift.value,
                    // Plus large que nécessaire : le rebond et l'élastique ne
                    // laissent jamais de vide au bord de la fenêtre.
                    width: drawerW * 1.4 + 40,
                    child: MouseRegion(
                      onEnter: (_) => _setNearEdge(true),
                      onExit: (_) => _setNearEdge(false),
                      // On l'attrape n'importe où : façade, coque ou feutrine.
                      child: GestureDetector(
                        // Compte depuis le point d'appui : le tiroir colle au pointeur.
                        dragStartBehavior: DragStartBehavior.down,
                        onPanStart: _dragBegin,
                        onPanUpdate: _dragUpdate,
                        onPanEnd: _dragEnd,
                        child: IpodDrawer(
                          families: _families,
                          current: _model,
                          shown: _shown,
                          contentWidth: drawerW,
                          onPick: _pick,
                          onSwatch: _swatch,
                          onFront: () => _setOpen(!_wantOpen),
                          slotKeys: _slotKeys,
                        ),
                      ),
                    ),
                  ),
                if (flying) deviceLayer,
                // Le câble et la prise, par-dessus tout.
                Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(painter: _LiveJackPainter(_jack))),
                ),
              ],
            ),
          );
        },
      ),
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
            if (glass != null)
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: glass)),
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
}

/// Peintre qui recalcule la prise au moment de peindre, une fois toute la
/// mise en page (et les transformations de l'appareil) connue.
class _LiveJackPainter extends CustomPainter {
  const _LiveJackPainter(this.build);

  final JackPainter Function() build;

  @override
  void paint(Canvas canvas, Size size) => build().paint(canvas, size);

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
