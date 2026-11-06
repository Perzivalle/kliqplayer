import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart' show WindowManager;

import '../core/player.dart';
import '../core/settings.dart';
import '../physics.dart';
import 'classic.dart';
import 'click.dart';
import 'drawer.dart';
import 'jack.dart';
import 'mini.dart';
import 'nano.dart';
import 'nanos.dart';
import 'vintage.dart';
import 'model.dart';
import 'nav.dart';
import 'screen.dart';
import 'shuffle.dart';
import 'wheel.dart';

export 'wheel.dart' show IpodWheel, WheelStyle, WheelZone;

/// Tous les modèles et leurs teintes, dans l'ordre du tiroir : par date de
/// sortie.
final List<IpodModel> ipodModels = [
  const FirstGenModel(), // 2001
  const SecondGenModel(), // 2002
  const ThirdGenModel(), // 2003
  for (final c in MiniColor.values) MiniModel(c), // janvier 2004
  for (final c in FourthGenColor.values) FourthGenModel(c), // juillet 2004
  const PhotoModel(), // octobre 2004
  const Shuffle1Model(), // janvier 2005
  for (final c in Nano1Color.values) Nano1Model(c), // septembre 2005
  const VideoModel(), // octobre 2005
  const VideoModel(ClassicColor.noir),
  for (final c in nano2Colors) Nano2Model(c), // septembre 2006
  for (final c in shuffle2Colors) Shuffle2Model(c), // septembre 2006
  const ClassicModel(), // septembre 2007
  const ClassicModel(ClassicColor.noir),
  for (final c in NanoColor.values) NanoModel(c), // septembre 2007
  for (final c in nano4Colors) Nano4Model(c), // 2008
  for (final c in shuffle4Colors) Shuffle4Model(c), // septembre 2010
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

  /// Navigation dans les menus : elle appartient à la scène, pas à
  /// l'appareil, si bien qu'en changeant d'iPod on reste sur le même écran.
  late final IpodNav _nav = IpodNav(widget.player, look: _model.look);
  bool get _remember => widget.initial == null;

  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  /// Ouverture du tiroir (0 fermé, 1 ouvert ; un léger rebond dépasse 1).
  final _open = Spring(0, stiffness: 230, damping: 0.78);

  /// Côté où sort le tiroir : 1 à droite, -1 à gauche (la poignée tirée).
  int _side = 1;

  /// Les poignées derrière les coins du haut, qui dépassent un peu plus
  /// quand la souris les approche (gauche, droite).
  final _peekL = Spring(0, stiffness: 420, damping: 0.9);
  final _peekR = Spring(0, stiffness: 420, damping: 0.9);
  int _hoverSide = 0;
  bool _wantOpen = false;

  /// Décalage vertical du tiroir quand on le tire de travers : un ressort
  /// le ramène toujours dans l'axe.
  final _lift = Spring(0, stiffness: 320, damping: 0.55);

  // Tiroir tenu à la main.
  bool _dragging = false;
  double _dragStart = 0;
  Offset _drag = Offset.zero;
  double _drawerW = 300;

  /// Part du tiroir qui reste engagée derrière l'iPod, ouvert.
  static const double _tuck = 28;

  /// Au tout début de l'ouverture, son bord extérieur part de ce retrait
  /// derrière le flanc de l'iPod : juste à la ligne où il devient visible,
  /// pour qu'il apparaisse dès la première image.
  static const double _hideBack = _tuck + 4;

  /// Course du tiroir, de rangé à ouvert.
  double get _travel => _drawerW - _tuck + _hideBack;

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
    if (Platform.environment['LECTEUR_BENCH'] != null) _bench();
  }

  /// LECTEUR_BENCH=1 : ouvre et referme le tiroir plusieurs fois, puis quitte
  /// (avec LECTEUR_FPS=1 pour lire les temps d'image).
  Future<void> _bench() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    for (var i = 0; i < 4; i++) {
      for (final open in [true, false]) {
        _wantOpen = open;
        _kick();
        await Future<void>.delayed(const Duration(milliseconds: 1300));
      }
    }
    exit(0);
  }

  static IpodModel _saved() {
    final id = Settings.getString(_settingsKey);
    // Par défaut, le Classic.
    return ipodModels.firstWhere((m) => m.id == id, orElse: () => const ClassicModel());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _nav.dispose();
    _drawerSnap.dispose();
    _deviceSnap.dispose();
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
    for (final (peek, side) in [(_peekL, -1), (_peekR, 1)]) {
      final target = _hoverSide == side && !_wantOpen && !_dragging ? 1.0 : 0.0;
      peek.step(target, dt);
      if (peek.isSettled) peek.value = target;
    }
    if (_geoFrom != null) {
      _morph.step(1, dt);
      if (_morph.isSettled) {
        _morph.value = 1;
        _geoFrom = null;
      }
    }
    _stepSwap(dt);
    _stepSway(dt);
    _updateDrawerSnap();
    setState(() {});
    if (!_dragging &&
        _phase == _Swap.none &&
        _open.isSettled &&
        _peekL.isSettled &&
        _peekR.isSettled &&
        _lift.isSettled &&
        _sway.isSettled &&
        _geoFrom == null &&
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
    _revealSlot(_model.family);
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

  /// Fait défiler le tiroir jusqu'à l'emplacement de [family] s'il n'est pas
  /// entièrement visible : l'appareil va s'y ranger, il doit le voir.
  void _revealSlot(String family) {
    final context = _slotKeys[family]?.currentContext;
    if (context == null) return;
    final scrollable = Scrollable.maybeOf(context);
    final slot = _rectOf(_slotKeys[family]);
    final viewport = scrollable?.context.findRenderObject();
    final stage = _stageKey.currentContext?.findRenderObject();
    if (scrollable == null || slot == null || viewport is! RenderBox || stage is! RenderBox) return;
    final view = MatrixUtils.transformRect(viewport.getTransformTo(stage), Offset.zero & viewport.size);
    if (slot.top >= view.top && slot.bottom <= view.bottom) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
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
        WheelClick.instance.play(force: true);
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
        } else if (_plugOffscreen() || _plug.value > JackGeometry.away * 0.95) {
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

  /// La prise (avec sa pointe) est entièrement sortie de la fenêtre.
  bool _plugOffscreen() {
    final box = _deviceKeys[_model.id]?.currentContext?.findRenderObject();
    final stage = _stageKey.currentContext?.findRenderObject();
    if (box is! RenderBox || stage is! RenderBox || !box.hasSize) return true;
    final m = box.getTransformTo(stage);
    final scale = MatrixUtils.transformRect(m, Offset.zero & box.size).width / box.size.width;
    final socket = MatrixUtils.transformPoint(m, Offset(_model.jackX, _model.jackOnTop ? 0 : box.size.height));
    // Bout de la pointe : à la distance de sortie, moins sa longueur.
    final tipEnd = (_plug.value - JackGeometry.tipLength) * scale;
    return _model.jackOnTop ? socket.dy - tipEnd < -4 : socket.dy + tipEnd > stage.size.height + 4;
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
  /// Le vol entre la place de l'appareil ([natural], où il est mis en page)
  /// et son emplacement dans le tiroir. Les deux bouts sont remesurés à
  /// chaque image : le tiroir peut défiler ou changer de taille en même
  /// temps.
  Matrix4? _flightTransform(Rect natural) {
    if (_flyFrom == null || _flyTo == null || _natural == null) return null;
    final model = _phase == _Swap.stowing ? _model : _incoming;
    final slot = model == null ? null : _rectOf(_slotKeys[model.family]);
    final stowing = _phase == _Swap.stowing;
    final from = stowing ? natural : (slot ?? _flyFrom!);
    final to = stowing ? (slot ?? _flyTo!) : natural;
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
    // Pendant le vol, la prise est partie hors de la fenêtre. On ne la dessine
    // pas : sa distance suit l'échelle de l'appareil, qui rétrécit en volant
    // vers le tiroir, et la ramènerait sinon au-dessus de lui.
    final flying = _phase == _Swap.stowing || _phase == _Swap.unstowing;
    if (flying || _hideDevice || box is! RenderBox || stage is! RenderBox || !box.hasSize) {
      return const JackPainter(socket: null, scale: 1, lift: 0, anchorX: 0, sway: 0);
    }
    final m = box.getTransformTo(stage);
    final socket = MatrixUtils.transformPoint(m, Offset(_model.jackX, _model.jackOnTop ? 0 : box.size.height));
    final scale = MatrixUtils.transformRect(m, Offset.zero & box.size).width / box.size.width;
    return JackPainter(
      socket: socket,
      scale: scale,
      lift: _plug.value,
      // Le câble pend depuis là où serait la prise, tiroir fermé.
      anchorX: socket.dx - _deviceShift * 0.7,
      sway: _sway.value,
      fromBelow: !_model.jackOnTop,
    );
  }

  // --- Tirer le tiroir à la main ---------------------------------------------

  /// Élastique façon iOS : plus on tire au-delà de la butée, plus ça résiste,
  /// sans jamais dépasser [limit].
  static double _rubber(double over, double limit) {
    final x = over.abs();
    return over.sign * (1 - 1 / (x * 0.55 / limit + 1)) * limit;
  }

  /// On tire une poignée : le tiroir sortira de ce côté (s'il est rangé).
  void _dragBeginSide(int side, DragStartDetails d) {
    if (_open.value.abs() < 0.02 && !_wantOpen) _side = side;
    _dragBegin(d);
  }

  void _dragBegin(DragStartDetails _) {
    // Reprend le tiroir là où il est.
    _open.velocity = 0;
    _dragStart = _open.value;
    _drag = Offset(0, _lift.value);
    _dragging = true;
    _kick();
  }

  void _dragUpdate(DragUpdateDetails d) {
    _drag += d.delta;
    // Tirer vers l'extérieur l'ouvre.
    final raw = _dragStart + _side * _drag.dx / _travel;
    _open.value = raw <= 1 ? raw.clamp(0.0, 1.0) : 1 + _rubber(raw - 1, 0.35);
    _lift.value = _rubber(_drag.dy, 36);
    setState(() {});
  }

  void _dragEnd(DragEndDetails d) {
    _dragging = false;
    final v = d.velocity.pixelsPerSecond;
    // Vitesse en « tiroirs par seconde » ; on projette où l'élan l'emmène.
    final vel = (_side * v.dx / _travel).clamp(-14.0, 14.0);
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

  /// Clic sur une poignée : le tiroir sort de ce côté.
  void _openSide(int side) {
    if (!_wantOpen && _open.value.abs() < 0.02) _side = side;
    _setOpen(true);
  }

  void _setOpen(bool open) {
    if (_wantOpen == open) return;
    _wantOpen = open;
    WheelClick.instance.play();
    _kick();
  }

  /// Le tiroir est une photo, sauf quand il est immobile, ouvert, avec la
  /// souris dessus : là il redevient vivant (survol des appareils et des
  /// pastilles). La photo est prise d'avance, tiroir fermé, pour que
  /// l'ouverture ne coûte rien ; repeindre en vrai à chaque image est trop
  /// lourd (Impeller ne garde rien en cache, écran à l'échelle 1,5).
  void _updateDrawerSnap() {
    final still = !_dragging && _open.isSettled && _lift.isSettled;
    // Vivant aussi pendant un échange : il défile, il change de taille.
    final busy = _drawerLive || _phase != _Swap.none || _geoFrom != null;
    _drawerSnap.allowSnapshotting = !(busy && still && _wantOpen);
    _deviceSnap.allowSnapshotting = (_dragging || !_open.isSettled) && _phase == _Swap.none && !_hideDevice;
  }

  void _drawerHover(bool inside) {
    _liveTimer?.cancel();
    if (inside) {
      _drawerLive = true;
      _updateDrawerSnap();
    } else {
      // On laisse finir les animations de survol avant de reprendre la photo.
      _liveTimer = Timer(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        _drawerLive = false;
        _updateDrawerSnap();
      });
    }
  }

  void _setHoverSide(int side, bool inside) {
    final next = inside ? side : (_hoverSide == side ? 0 : _hoverSide);
    if (next == _hoverSide) return;
    _hoverSide = next;
    // La souris approche d'une poignée : le tiroir se prépare tout de suite
    // de ce côté (caché derrière l'iPod), pour que sa photo soit prête
    // avant le clic au lieu de coûter une image au début de l'ouverture.
    if (next != 0 && !_wantOpen && _open.value.abs() < 0.02) _side = next;
    _kick();
  }

  void _choose(IpodModel m) {
    _nav.fitLook(m.look);
    if (m.size != _model.size && _geoShown != null) {
      _geoFrom = _geoShown;
      _morph
        ..value = 0
        ..velocity = 0;
      _kick();
    }
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

  /// Clic sur une pastille : prend cet appareil, dans cette teinte. Si
  /// c'est la famille en main, il change juste de teinte (tiroir ouvert).
  void _swatch(IpodModel m) {
    if (m.family == _model.family) {
      if (m.id == _model.id) return;
      WheelClick.instance.play();
      _choose(m);
    } else {
      _pick(m);
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

  // Widgets réutilisés d'une image à l'autre : Flutter saute alors leur
  // reconstruction pendant les animations de la scène.
  Widget? _deviceCache, _drawerCache;
  final _drawerSnap = SnapshotController(allowSnapshotting: true);
  final _deviceSnap = SnapshotController();
  bool _drawerLive = false;
  Timer? _liveTimer;
  static const double _shadowPad = 64;
  Object? _deviceCacheKey, _drawerCacheKey;

  /// Rangé, immobile, et aucune poignée en vue.
  bool get _drawerIdle =>
      !_wantOpen && !_dragging && _open.value == 0 && _open.isSettled && _hoverSide == 0 && _phase == _Swap.none;

  /// Le tiroir et tout ce qui l'entoure, construits une fois pour toutes
  /// (tant que rien ne change) : pendant qu'il glisse, seule sa position
  /// change, Flutter ne reconstruit rien d'autre.
  Widget _drawer(double width, bool right) {
    final key = (width, right, _model.id, _shown.values.map((m) => m.id).join(','));
    if (key != _drawerCacheKey) {
      _drawerCacheKey = key;
      if (_drawerSnap.allowSnapshotting) {
        _drawerSnap.allowSnapshotting = false;
        _drawerSnap.allowSnapshotting = true;
      }
      // Impeller ne garde rien d'une image à l'autre : pendant que le tiroir
      // glisse, on fait glisser une photo de lui, prise une fois, au lieu de
      // tout repeindre (feutrine, grain, ombres floues, miniatures).
      _drawerCache = SnapshotWidget(
        controller: _drawerSnap,
        mode: SnapshotMode.permissive,
        child: Padding(
          // Place pour l'ombre du tiroir.
          padding: const EdgeInsets.all(_shadowPad),
          child: MouseRegion(
            onEnter: (_) => _drawerHover(true),
            onExit: (_) => _drawerHover(false),
            // On l'attrape n'importe où : façade, coque ou feutrine.
            child: GestureDetector(
              // Compte depuis le point d'appui : le tiroir colle au pointeur.
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: _dragBegin,
              onPanUpdate: _dragUpdate,
              onPanEnd: _dragEnd,
              child: RepaintBoundary(
                child: IpodDrawer(
          families: _families,
          current: _model,
          shown: Map.of(_shown),
          contentWidth: width,
          frontOnRight: right,
          onPick: _pick,
          onSwatch: _swatch,
          onFront: () => _setOpen(!_wantOpen),
          slotKeys: _slotKeys,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return _drawerCache!;
  }

  /// Décalage horizontal de l'appareil (tiroir ouvert), pour le câble.
  double _deviceShift = 0;

  /// Passage en douceur d'une mise en place à l'autre quand on change pour
  /// un modèle d'un autre format : le tiroir et l'appareil glissent vers
  /// leur nouvelle taille au lieu d'y sauter.
  final _morph = Spring(1, stiffness: 110, damping: 1);
  _Geo? _geoFrom;
  _Geo? _geoShown;

  /// Mise en place pour une fenêtre [w] × [h] : où est l'appareil au repos,
  /// la largeur du tiroir, et de combien l'appareil rétrécit et s'écarte
  /// (à droite ou à gauche) quand le tiroir est ouvert.
  _Geo _geometry(double w, double h) {
    // Comme la mise en page de l'appareil : centré, marges, réduit pour
    // tenir (jamais agrandi).
    final m = _model;
    final pad = _devicePadding(h);
    final f = math.min(1.0, math.min((w - pad.horizontal) / m.size.width, (h - pad.vertical) / m.size.height));
    final size = m.size * f;
    final left = (w - size.width - pad.horizontal) / 2 + pad.left;
    final top = (h - size.height - pad.vertical) / 2 + pad.top;
    final device = Rect.fromLTWH(left, top, size.width, size.height);

    // L'appareil (réduit jusqu'à 55 %) et le tiroir doivent tenir côte à
    // côte avec une petite marge.
    const margin = 14.0;
    final drawerW = math.max(140.0, math.min((w * 0.5).clamp(230.0, 460.0), w - 2 * margin - device.width * 0.55 + _tuck));
    final room = ((w - 2 * margin - drawerW + _tuck) / device.width).clamp(0.55, 1.0);
    final devW = device.width * room;
    final groupLeft = (w - (devW + drawerW - _tuck)) / 2;
    final cx = w / 2;
    final scaledCx = cx + (device.center.dx - cx) * room;
    return (
      device: device,
      cornerRadius: m.cornerRadius * f,
      drawerW: drawerW,
      room: room,
      shiftRight: groupLeft + devW / 2 - scaledCx,
      shiftLeft: w - groupLeft - devW / 2 - scaledCx,
      // Un peu moins haut que l'appareil au repos : il sort de derrière lui,
      // à sa mesure (en changeant d'appareil, il grandit ou rétrécit en
      // douceur, voir [_morph]).
      drawerHeight: device.height * 0.9,
    );
  }

  /// Marge autour de l'appareil : son ombre, et la place pour la prise.
  EdgeInsets _devicePadding(double h) => _model.jackOnTop
      ? _model.margin.copyWith(top: math.max(_model.margin.top, h * 0.2))
      : _model.margin.copyWith(bottom: math.max(_model.margin.bottom, h * 0.2));

  /// Poignée cachée derrière un coin du haut de l'appareil [dev] : quand la
  /// souris approche de ce coin, elle glisse dehors ; cliquée ou tirée, le
  /// tiroir sort de ce côté. Tiroir ouvert, elle n'a plus lieu d'être.
  Widget _handle(int side, Rect dev, double corner, double openC) {
    final peek = (side < 0 ? _peekL : _peekR).value;
    const width = 40.0, height = 46.0, reach = 22.0;
    // Zone sensible juste au-delà du flanc, même quand on ne voit rien.
    const zone = 30.0;
    final out = peek * reach;
    final top = dev.top + corner + 10;
    return Positioned(
      left: side > 0 ? dev.right - width : dev.left - zone,
      top: top - 8,
      width: width + zone,
      height: height + 16,
      child: IgnorePointer(
        ignoring: openC > 0.05,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHoverSide(side, true),
          onExit: (_) => _setHoverSide(side, false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openSide(side),
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (d) => _dragBeginSide(side, d),
            onPanUpdate: _dragUpdate,
            onPanEnd: _dragEnd,
            child: Stack(
              children: [
                Positioned(
                  left: side > 0 ? out : zone - out,
                  top: 8,
                  width: width,
                  height: height,
                  child: Opacity(
                    opacity: (peek.clamp(0.0, 1.0) * (1 - openC)).toDouble(),
                    child: CustomPaint(painter: _HandlePainter(side)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final target = _geometry(w, h);
          final from = _geoFrom;
          final g = _geoShown = from == null || _morph.value >= 1 ? target : _lerpGeo(from, target, _morph.value);
          final drawerW = _drawerW = g.drawerW;
          final open = _open.value;
          final openC = open.clamp(0.0, 1.0);
          final right = _side > 0;

          final deviceKey = (_model.id, box.maxHeight);
          if (deviceKey != _deviceCacheKey) {
            _deviceCacheKey = deviceKey;
            _deviceCache = Center(
              key: ValueKey(_model.id),
              child: Padding(
                // Marge pour l'ombre portée, et de la place en haut pour la
                // prise et le câble.
                padding: _devicePadding(box.maxHeight),
                // Couche à part : pendant que le tiroir bouge, l'appareil
                // n'est pas repeint, seulement déplacé.
                child: RepaintBoundary(
                  child: FittedBox(
                    child: IpodDevice(key: _deviceKey(_model), model: _model, player: widget.player, nav: _nav),
                  ),
                ),
              ),
            );
          }
          Widget device = AnimatedSwitcher(
            // Changement de teinte : fondu enchaîné, comme les miniatures du
            // tiroir. Pendant un échange, c'est le vol qui anime : pas de fondu.
            duration: _phase == _Swap.none ? const Duration(milliseconds: 260) : Duration.zero,
            switchInCurve: Curves.easeOut,
            // La nouvelle teinte apparaît par-dessus l'ancienne, qui reste
            // opaque dessous : pas de transparence à mi-chemin.
            transitionBuilder: (child, anim) =>
                child.key == ValueKey(_model.id) ? FadeTransition(opacity: anim, child: child) : child,
            child: _deviceCache,
          );
          // Pendant que le tiroir glisse, l'appareil rétrécit : on fait
          // rétrécir une photo de lui (ses ombres floues coûtent trop cher à
          // recalculer à chaque taille). Immobile, il redevient vivant.
          device = SnapshotWidget(controller: _deviceSnap, mode: SnapshotMode.permissive, child: device);
          // L'appareil s'écarte et rétrécit pour laisser la place au tiroir :
          // ensemble, ils restent centrés dans la fenêtre.
          final scale = 1 + (g.room - 1) * openC;
          final shift = _deviceShift = (right ? g.shiftRight : g.shiftLeft) * open;
          if (open != 0) {
            device = Transform.translate(
              offset: Offset(shift, 0),
              child: Transform.scale(scale: scale, child: device),
            );
          }
          // Où est l'appareil à l'écran en ce moment.
          final c = Offset(w / 2, h / 2);
          Offset place(Offset p) => c + (p - c) * scale + Offset(shift, 0);
          final dev = Rect.fromPoints(place(g.device.topLeft), place(g.device.bottomRight));
          // L'appareil, lui, est déjà mis en page à sa nouvelle place.
          final devActual = Rect.fromPoints(place(target.device.topLeft), place(target.device.bottomRight));

          // Le tiroir sort de derrière l'appareil : son bord extérieur part
          // d'un peu en retrait de son flanc et va jusqu'à [_travel] plus loin.
          final outer = right ? dev.right - _hideBack + open * _travel : dev.left + _hideBack - open * _travel;
          final drawerRect = Rect.fromLTWH(
            right ? outer - drawerW : outer,
            // Centré sur l'appareil, sans sortir de la fenêtre.
            (dev.center.dy - g.drawerHeight / 2).clamp(14.0, math.max(14.0, h - 14 - g.drawerHeight)) + _lift.value,
            drawerW,
            g.drawerHeight,
          ).shift(
            // Rangé, il attend hors de la fenêtre, sa photo prête : rien de
            // lui (pas même son ombre) ne dépasse de derrière l'iPod.
            open == 0 ? Offset(right ? w + 2 * _shadowPad - (outer - drawerW) : -(outer + 2 * _shadowPad + drawerW), 0) : Offset.zero,
          );

          if (_hideDevice) device = Opacity(opacity: 0, child: device);
          final flight = _flightTransform(devActual);
          if (flight != null) device = Transform(transform: flight, child: device);
          final deviceLayer = Positioned.fill(key: const ValueKey('appareil'), child: device);

          return IgnorePointer(
            ignoring: _phase != _Swap.none,
            child: Stack(
              key: _stageKey,
              children: [
                // Un clic à côté du tiroir le referme.
                if (_wantOpen)
                  Positioned.fill(
                    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _setOpen(false)),
                  ),
                // Les deux poignées, derrière les coins du haut.
                for (final side in const [-1, 1]) _handle(side, dev, g.cornerRadius * scale, openC),
                // Le tiroir, derrière l'appareil, d'où il émerge. Coupé au
                // flanc opposé : au début de l'ouverture, son autre bout ne
                // dépasse pas de l'autre côté.
                Positioned.fill(
                  child: ClipRect(
                    clipper: _SideClip(right ? dev.left + 4 : dev.right - 4, right),
                    child: Stack(
                      children: [
                        Positioned.fromRect(
                          rect: drawerRect.inflate(_shadowPad),
                          // Rangé et au repos, il n'est pas dessiné du tout
                          // (sa photo reste prête) : l'écran qui s'anime en
                          // lecture ne le recompose pas à chaque image.
                          child: Offstage(
                            offstage: _drawerIdle,
                            child: _drawer(drawerW - _tuck, right),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                deviceLayer,
                // Le câble et la prise, par-dessus tout.
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(child: CustomPaint(painter: _LiveJackPainter(_jack))),
                  ),
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
  const IpodDevice({super.key, required this.model, required this.player, required this.nav});

  final IpodModel model;
  final PlayerController player;

  /// Navigation de la scène, passée d'un appareil à l'autre.
  final IpodNav nav;

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
  }

  @override
  void dispose() {
    _endHold();
    _ledTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
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
    switch (e.logicalKey) {
      // Comme dans vim : j k pour descendre et monter, l pour entrer
      // (valider), h pour revenir (MENU).
      case LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.keyK:
        _scroll(-1);
      case LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.keyJ:
        _scroll(1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter || LogicalKeyboardKey.keyL:
        if (e is KeyRepeatEvent) return KeyEventResult.handled;
        WheelClick.instance.play();
        _press(WheelZone.center);
      case LogicalKeyboardKey.backspace || LogicalKeyboardKey.keyH:
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
    try {
      WindowManager.instance.getCurrent()?.startDragging();
    } catch (_) {}
  }

  void _scroll(int delta) {
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
                onPanStart: (_) => _moveWindow(),
                child: CustomPaint(painter: m.body),
              ),
            ),
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
                    child: IpodScreen(nav: _nav, player: widget.player, look: m.look),
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
      child: CustomPaint(painter: HoldPainter(h)),
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

/// Le curseur du verrou, qui dépasse à peine de la tranche.
class HoldPainter extends CustomPainter {
  const HoldPainter(this.hold);

  final HoldSwitch hold;

  /// Ce qui dépasse de la tranche.
  static const double depth = 3;

  @override
  void paint(Canvas canvas, Size size) {
    // Vers l'extérieur de l'appareil : le haut pour un verrou du haut.
    if (!hold.onTop) {
      canvas.translate(0, size.height);
      canvas.scale(1, -1);
    }
    final w = size.width, h = size.height;
    switch (hold.kind) {
      case HoldKind.pin:
        // Demi-perle de métal poli, avec son reflet.
        final dome = Rect.fromLTWH(0, 0, w, h * 2);
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, w, h + 0.5));
        canvas.drawOval(
          dome,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.6),
              radius: 0.9,
              colors: hold.knob ?? const [Color(0xFFFFFFFF), Color(0xFFC3C7CC), Color(0xFF7D8287)],
              stops: const [0, 0.45, 1],
            ).createShader(dome),
        );
        canvas.restore();
      case HoldKind.plastic || HoldKind.metal:
        final knob = RRect.fromRectAndCorners(
          Rect.fromLTWH(0, 0, w, h + 0.5),
          topLeft: const Radius.circular(1.5),
          topRight: const Radius.circular(1.5),
        );
        final colors =
            hold.knob ??
            (hold.kind == HoldKind.metal
                ? const [Color(0xFFE9EBED), Color(0xFFA3A7AC), Color(0xFFD5D8DB)]
                : const [Color(0xFFFFFFFF), Color(0xFFE3E5E7), Color(0xFFC7CACE)]);
        canvas.drawRRect(
          knob,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ).createShader(knob.outerRect),
        );
        canvas.drawRRect(
          knob,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6
            ..color = Colors.black.withValues(alpha: 0.25),
        );
    }
  }

  @override
  bool shouldRepaint(covariant HoldPainter old) => old.hold != hold;
}

/// Ne laisse voir que ce qui est au-delà de [x], du côté où sort le tiroir.
class _SideClip extends CustomClipper<Rect> {
  const _SideClip(this.x, this.right);

  final double x;
  final bool right;

  @override
  Rect getClip(Size size) =>
      right ? Rect.fromLTRB(x, -1e4, size.width + 1e4, 1e4) : Rect.fromLTRB(-1e4, -1e4, x, 1e4);

  @override
  bool shouldReclip(_SideClip old) => old.x != x || old.right != right;
}

/// Poignée du tiroir : une languette d'aluminium microbillé, arrondie du
/// côté qui dépasse, avec une encoche pour le doigt.
class _HandlePainter extends CustomPainter {
  const _HandlePainter(this.side);

  /// 1 : elle dépasse à droite ; -1 : à gauche.
  final int side;

  @override
  void paint(Canvas canvas, Size size) {
    if (side < 0) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final r = Offset.zero & size;
    final shape = RRect.fromRectAndCorners(
      r,
      topRight: const Radius.circular(9),
      bottomRight: const Radius.circular(9),
    );
    canvas.drawRRect(
      shape.shift(const Offset(1, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = ui.Gradient.linear(
          r.topCenter,
          r.bottomCenter,
          const [Color(0xFFE2E5E8), Color(0xFFC6CACE), Color(0xFFA9AEB3)],
          const [0, 0.5, 1],
        ),
    );
    // Arête : un filet de lumière en haut, plus sombre en bas.
    canvas.drawRRect(
      shape.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = ui.Gradient.linear(
          r.topCenter,
          r.bottomCenter,
          [Colors.white.withValues(alpha: 0.9), Colors.black.withValues(alpha: 0.2)],
        ),
    );
    // Encoche pour le doigt, près du bout.
    final notch = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width - 8, size.height / 2), width: 4, height: size.height * 0.5),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      notch,
      Paint()
        ..shader = ui.Gradient.linear(
          notch.outerRect.centerLeft,
          notch.outerRect.centerRight,
          const [Color(0xFF7C8085), Color(0xFFD2D5D8)],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _HandlePainter old) => old.side != side;
}

/// Voyant d'état d'un shuffle, sur la tranche du haut : éteint, ou vert vif
/// avec son halo.
class _LedPainter extends CustomPainter {
  const _LedPainter(this.on);

  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 3);
    if (on) {
      canvas.drawCircle(
        c,
        7,
        Paint()
          ..color = const Color(0xAA4CFF6A)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawCircle(c, 2.6, Paint()..color = on ? const Color(0xFFB8FFC4) : const Color(0xFF3B4A3E));
  }

  @override
  bool shouldRepaint(covariant _LedPainter old) => old.on != on;
}

/// Mise en place de la scène pour un modèle (voir `_geometry`).
typedef _Geo = ({
  Rect device,
  double cornerRadius,
  double drawerW,
  double room,
  double shiftRight,
  double shiftLeft,
  double drawerHeight,
});

_Geo _lerpGeo(_Geo a, _Geo b, double t) {
  double l(double x, double y) => x + (y - x) * t;
  return (
    device: Rect.lerp(a.device, b.device, t)!,
    cornerRadius: l(a.cornerRadius, b.cornerRadius),
    drawerW: l(a.drawerW, b.drawerW),
    room: l(a.room, b.room),
    shiftRight: l(a.shiftRight, b.shiftRight),
    shiftLeft: l(a.shiftLeft, b.shiftLeft),
    drawerHeight: l(a.drawerHeight, b.drawerHeight),
  );
}
