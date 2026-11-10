import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:nativeapi/nativeapi.dart' show DisplayManager;
import 'package:window_manager/window_manager.dart';

import '../core/player.dart';
import '../core/settings.dart';
import '../core/strings.dart';
import '../physics.dart';
import 'classic.dart';
import 'click.dart';
import 'jack_static.dart';
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

part 'ipod_bench.dart';
part 'ipod_device.dart';
part 'ipod_painters.dart';
part 'ipod_window.dart';

/// Un shuffle joue dans le désordre, sauf si son interrupteur est sur
/// « dans l'ordre » (retenu d'une fois sur l'autre).
bool _shuffles(IpodModel m) => !m.hasScreen && Settings.getString('shuffle.order') != 'on';


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

/// Limites de la fenêtre autour de l'appareil [model], posé en [device] sur
/// l'écran [screen] (tout en coordonnées de l'écran) : la place de ses
/// poignées et de son ombre sur les côtés, jusqu'au bord de l'écran du côté
/// de son câble, et [drawerRoom] de plus du côté du tiroir ([drawerSide] :
/// 1 à droite, -1 à gauche, 0 tiroir rentré).
@visibleForTesting
Rect windowFrameFor(IpodModel model, Rect device, Rect screen, {int drawerSide = 0, double drawerRoom = 0}) {
  final margin = model.margin;
  final side = math.max(margin.left, (model.windowSize.width - device.width) / 2);
  var left = device.left - side, right = device.right + side;
  if (drawerSide > 0) right += drawerRoom;
  if (drawerSide < 0) left -= drawerRoom;
  final top = model.jackOnTop ? math.min(screen.top, device.top - margin.top) : device.top - margin.top;
  final bottom = model.jackOnTop ? device.bottom + margin.bottom : math.max(screen.bottom, device.bottom + margin.bottom);
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Faux tant que l'iPod monte à l'ouverture de l'appli (main.dart) : la
/// prise attend qu'il soit arrivé pour se brancher.
final ipodLanded = ValueNotifier(true);

/// Étapes d'un changement d'appareil.
enum _Swap {
  none,

  /// L'écran s'éteint d'abord.
  poweringOff,

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

class _IpodStageState extends State<IpodStage> with SingleTickerProviderStateMixin, _ManagedWindow {
  static const _settingsKey = 'ipod.model';

  @override
  late IpodModel _model = widget.initial ?? _saved();

  /// Navigation dans les menus : elle appartient à la scène, pas à
  /// l'appareil, si bien qu'en changeant d'iPod on reste sur le même écran.
  late final IpodNav _nav = IpodNav(widget.player, look: _model.look);
  @override
  bool get _remember => widget.initial == null;

  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  /// Ouverture du tiroir (0 fermé, 1 ouvert ; un léger rebond dépasse 1).
  final _open = Spring(0, stiffness: 230, damping: 0.78);

  /// Côté où sort le tiroir : 1 à droite, -1 à gauche (la poignée tirée).
  @override
  int _side = 1;

  /// Les poignées derrière les coins du haut, qui dépassent un peu plus
  /// quand la souris les approche (gauche, droite).
  final _peekL = Spring(0, stiffness: 420, damping: 0.9);
  final _peekR = Spring(0, stiffness: 420, damping: 0.9);
  int _hoverSide = 0;
  bool _wantOpen = false;

  // --- Place de l'iPod dans la fenêtre : à gauche, au milieu, à droite -------

  static const _placeKey = 'ipod.place';
  static const _placeNames = {-1: 'gauche', 0: 'milieu', 1: 'droite'};

  /// Où l'iPod se tient, tiroir fermé : -1 à gauche, 0 au milieu, 1 à droite
  /// (retenu d'un lancement à l'autre).
  late int _placeTarget = _remember
      ? _placeNames.entries.firstWhere((e) => e.value == Settings.getString(_placeKey), orElse: () => const MapEntry(0, '')).key
      : 0;

  /// Position actuelle, en route vers [_placeTarget].
  late final _place = Spring(_placeTarget.toDouble(), stiffness: 150, damping: 0.86);

  /// Les boutons de déplacement, sous les poignées du tiroir : ils sortent
  /// avec elles quand la souris approche d'un coin du haut (gauche, droite).
  final _movePeekL = Spring(0, stiffness: 420, damping: 0.9);
  final _movePeekR = Spring(0, stiffness: 420, damping: 0.9);
  int _hoverMove = 0;

  /// Course possible de l'iPod jusqu'au bord, à la dernière mise en page.
  double _placeReach = 0;

  /// Sous ce débattement, la fenêtre est trop étroite pour qu'on déplace
  /// l'iPod (ou c'est l'appli qui règle la fenêtre autour de lui).
  bool get _canPlace => _placeReach >= 40 && !_wantOpen && _phase == _Swap.none && ipodLanded.value;

  /// Il reste de la place de ce côté (à gauche, on ne va pas plus à gauche).
  bool _canMove(int side) => _canPlace && (_placeTarget + side).abs() <= 1;

  void _setHoverMove(int side, bool inside) {
    final next = inside ? side : (_hoverMove == side ? 0 : _hoverMove);
    if (next == _hoverMove) return;
    _hoverMove = next;
    _kick();
  }

  /// D'un cran vers [side] : de droite au milieu, du milieu à gauche…
  void _nudge(int side) {
    if (!_canMove(side)) return;
    _moveTo(_placeTarget + side);
    WheelClick.instance.play();
  }

  void _moveTo(int place) {
    if (!_canPlace || place == _placeTarget) return;
    _placeTarget = place;
    if (_remember) Settings.setString(_placeKey, _placeNames[place]!);
    _kick();
  }

  /// Décalage vertical du tiroir quand on le tire de travers : un ressort
  /// le ramène toujours dans l'axe.
  final _lift = Spring(0, stiffness: 420, damping: 0.8);

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

  /// Teinte montrée dans l'emplacement de chaque famille : la première ;
  /// celle de l'appareil en main reste la sienne.
  late final Map<String, IpodModel> _shown = {
    for (final f in _families) f.first.family: f.first,
    _model.family: _model,
  };

  // --- Prise jack et changement d'appareil ------------------------------------

  _Swap _phase = _Swap.none;
  @override
  IpodModel? _incoming;

  /// Hauteur dont la prise est sortie, en unités de l'appareil (0 = enfoncée).
  final _plug = Spring(0, stiffness: 500, damping: 0.55);
  double _plugTarget = 0;
  double _plugHold = 0;
  bool _plugClicked = false;

  /// Le grésillement de la pointe qui entre a déjà été joué.
  bool _plugCrackled = false;

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
    widget.player.setForcedShuffle(_shuffles(_model));
    if (_win != null) WidgetsBinding.instance.addPostFrameCallback((_) => _takeWindow());
    if (_remember) {
      // Au lancement, la prise vient se brancher, une fois l'iPod arrivé
      // (voir main.dart) ; l'écran s'allume au branchement.
      // (La cible aussi : la scène peut s'animer pendant la montée, souris
      // sur la fenêtre, et le ressort ramènerait sinon la prise jusqu'à la
      // prise femelle sans qu'on la voie, déjà branchée à l'arrivée.)
      _plug.value = _plugTarget = JackGeometry.away;
      if (ipodLanded.value) {
        _startPlugging();
      } else {
        ipodLanded.addListener(_landed);
      }
    }
    if (Platform.environment['LECTEUR_BENCH'] != null) _bench();
  }

  void _landed() {
    if (!ipodLanded.value) return;
    ipodLanded.removeListener(_landed);
    if (mounted) _startPlugging();
  }

  static IpodModel _saved() {
    final id = Settings.getString(_settingsKey);
    // Par défaut, le Classic.
    return ipodModels.firstWhere((m) => m.id == id, orElse: () => const ClassicModel());
  }

  @override
  void dispose() {
    ipodLanded.removeListener(_landed);
    _liveTimer?.cancel();
    _dragSettle?.cancel();
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
      if (_open.isSettled) {
        _open.value = _wantOpen ? 1 : 0;
        // Rentré : la fenêtre reprend sa taille.
        if (!_wantOpen && _frameDrawer && _phase == _Swap.none) {
          _frameDrawer = false;
          _applyFrame();
        }
      }
      if (_lift.isSettled) _lift.value = 0;
    }
    _place.step(_placeTarget.toDouble(), dt);
    if (_place.isSettled) _place.value = _placeTarget.toDouble();
    for (final (peek, side) in [(_peekL, -1), (_peekR, 1)]) {
      // Les deux boutons d'un coin sortent ensemble, quel que soit celui
      // qu'on approche.
      final near = _hoverSide == side || _hoverMove == side;
      final target = near && !_wantOpen && !_dragging ? 1.0 : 0.0;
      peek.step(target, dt);
      if (peek.isSettled) peek.value = target;
    }
    for (final (peek, side) in [(_movePeekL, -1), (_movePeekR, 1)]) {
      final near = _hoverSide == side || _hoverMove == side;
      final target = near && _canMove(side) && !_dragging ? 1.0 : 0.0;
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
    if (_powerOnPending && _phase == _Swap.none && !_dragging && _open.isSettled && _open.value == (_wantOpen ? 1 : 0)) {
      _powerOnPending = false;
      screenPower.value = true;
    }
    _stepSway(dt);
    _updateDrawerSnap();
    setState(() {});
    if (!_dragging &&
        _phase == _Swap.none &&
        _open.isSettled &&
        _peekL.isSettled &&
        _peekR.isSettled &&
        _lift.isSettled &&
        _place.isSettled &&
        _movePeekL.isSettled &&
        _movePeekR.isSettled &&
        _swaySettled &&
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
    _incoming = to;
    // La fenêtre fait la place aux deux, le temps de l'échange.
    _applyFrame();
    // L'écran s'éteint, puis on débranche : l'appareil voyage éteint, en
    // photo, sans redessiner son écran à chaque image.
    screenPower.value = false;
    _offHold = 0;
    _phase = _Swap.poweringOff;
    _kick();
  }

  double _offHold = 0;
  bool _powerOnPending = false;

  void _startUnplugging() {
    // Prise arrachée : plus de son, comme avec de vrais écouteurs.
    widget.player.unplug();
    JackStatic.instance.unplug();
    _phase = _Swap.unplugging;
    _plugTarget = _popHeight;
    _plug
      ..stiffness = 520
      ..damping = 0.5;
    _plugHold = 0;
    _kick();
  }

  /// Le tiroir défile vers l'emplacement d'où va sortir le nouvel appareil :
  /// il attend d'y être pour s'envoler.
  bool _revealing = false;

  /// Fait défiler le tiroir jusqu'à l'emplacement de [family] s'il n'est pas
  /// entièrement visible : l'appareil va s'y ranger (ou en sortir), on doit
  /// le voir.
  Future<void> _revealSlot(String family) async {
    final context = _slotKeys[family]?.currentContext;
    if (context == null) return;
    final scrollable = Scrollable.maybeOf(context);
    final slot = _rectOf(_slotKeys[family]);
    final viewport = scrollable?.context.findRenderObject();
    final stage = _stageKey.currentContext?.findRenderObject();
    if (scrollable == null || slot == null || viewport is! RenderBox || stage is! RenderBox) return;
    final view = MatrixUtils.transformRect(viewport.getTransformTo(stage), Offset.zero & viewport.size);
    if (slot.top >= view.top && slot.bottom <= view.bottom) return;
    await Scrollable.ensureVisible(
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
    _plugCrackled = false;
    _plug
      ..stiffness = 170
      ..damping = 0.9
      ..velocity = 0;
    _kick();
  }

  void _stepSwap(double dt) {
    _plug.step(_plugTarget, dt);
    // La pointe touche les lamelles de la prise femelle : ça grésille.
    if (_phase == _Swap.plugging && !_plugCrackled && _plug.value < JackGeometry.tipLength) {
      _plugCrackled = true;
      JackStatic.instance.plugIn();
    }
    // La prise bute au fond de la prise femelle : petit rebond (sans clic,
    // le grésillement suffit).
    if (_plug.value < 0) {
      _plug.value = 0;
      if (_plug.velocity < 0) _plug.velocity = -_plug.velocity * 0.22;
      if (!_plugClicked) {
        _plugClicked = true;
        // Rebranchée : le son revient.
        widget.player.plug();
      }
    }

    switch (_phase) {
      case _Swap.none:
        break;
      case _Swap.poweringOff:
        _offHold += dt;
        if (_offHold > 0.26) _startUnplugging();
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
          // L'appareil vient d'être construit (invisible) : on mesure, une
          // fois le tiroir arrivé sur son emplacement.
          if (!_revealing) _beginFlight(stowing: false);
        } else {
          _fly.step(1, dt);
          if (_fly.value > 0.995 && _fly.velocity.abs() < 0.2) _landOut();
        }
      case _Swap.plugging:
        if (_plugClicked && _plug.isSettled) {
          _plug.value = 0;
          _phase = _Swap.none;
          // Branché : l'écran s'allumera une fois le tiroir rentré (pendant
          // qu'il rentre, l'appareil n'est qu'une photo, qui figerait
          // l'écran à moitié allumé).
          _powerOnPending = true;
          _applyFrame(); // à la mesure du nouveau
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
    final incoming = _incoming!;
    _revealing = true;
    _revealSlot(incoming.family).whenComplete(() => _revealing = false);
    _choose(incoming);
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
      _sway.velocity -= v * 0.9 * dt;
    }
    _lastSocketX = x;
    _sway.step(0, dt);
    if (_swaySettled) {
      _sway
        ..value = 0
        ..velocity = 0;
    }
  }

  /// Le câble ne bouge plus à l'œil (le ressort, très peu amorti, mettrait
  /// sinon 3 à 4 s de plus à s'arrêter tout à fait, en redessinant toute la
  /// scène à chaque image).
  bool get _swaySettled => _sway.value.abs() < 0.05 && _sway.velocity.abs() < 0.5;

  /// Câble et prise, recalculés au moment de peindre (toujours collés à
  /// l'appareil, même quand il bouge).
  JackPainter _jack() {
    final box = _deviceKeys[_model.id]?.currentContext?.findRenderObject();
    final stage = _stageKey.currentContext?.findRenderObject();
    // Pendant le vol, la prise est partie hors de la fenêtre. On ne la dessine
    // pas : sa distance suit l'échelle de l'appareil, qui rétrécit en volant
    // vers le tiroir, et la ramènerait sinon au-dessus de lui.
    // Au lancement, pas de prise tant que l'iPod monte : elle descendra
    // une fois qu'il sera arrivé.
    final flying = _phase == _Swap.stowing || _phase == _Swap.unstowing || !ipodLanded.value;
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

  /// On tire une poignée : le tiroir sortira de ce côté (s'il est rangé).
  void _dragBeginSide(int side, DragStartDetails d) {
    if (_open.value.abs() < 0.02 && !_wantOpen) _side = side;
    _dragBegin(d);
  }

  /// Avant que le tiroir sorte, la fenêtre s'élargit de son côté.
  void _makeRoomForDrawer() {
    if (_win == null || _frameDrawer) return;
    _frameDrawer = true;
    _applyFrame();
  }

  void _dragBegin(DragStartDetails _) {
    _makeRoomForDrawer();
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
    _open.value = raw <= 1 ? raw.clamp(0.0, 1.0) : 1 + rubberBand(raw - 1, 0.35);
    _lift.value = rubberBand(_drag.dy, 12); // il bouge à peine en hauteur
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
    _lift.velocity = v.dy.clamp(-1500.0, 1500.0) * 0.1;
    _kick();
  }

  /// Clic sur une poignée : le tiroir sort de ce côté.
  void _openSide(int side) {
    if (!_wantOpen && _open.value.abs() < 0.02) _side = side;
    _setOpen(true);
  }

  void _setOpen(bool open) {
    if (_wantOpen == open) return;
    if (open) _makeRoomForDrawer();
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
    // Pendant l'échange (écran éteint, la prise à part), l'appareil n'est
    // qu'une photo : débranché, en vol, rebranché. Impeller repeindrait
    // sinon à chaque image tout l'appareil, ombres floues comprises.
    final flying = _phase != _Swap.none && _phase != _Swap.poweringOff;
    final moving = _dragging || !_open.isSettled || !_place.isSettled;
    _deviceSnap.allowSnapshotting = (moving && _phase == _Swap.none || flying) && !_hideDevice;
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
    // Le nouveau prend la place de l'ancien à l'écran, centré au même endroit.
    final anchor = _anchor;
    if (anchor != null) _anchor = Rect.fromCenter(center: anchor.center, width: m.size.width, height: m.size.height);
    _nav.fitLook(m.look);
    widget.player.setForcedShuffle(_shuffles(m));
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
    if (_phase != _Swap.none || _swatchPending || m.id == _model.id) return;
    setState(() => _shown[m.family] = m);
    _startSwap(m);
  }

  /// Une teinte choisie attend que l'éventail soit rangé pour partir en main.
  bool _swatchPending = false;

  /// Clic sur une pastille : prend cet appareil, dans cette teinte. Si
  /// c'est la famille en main, il change juste de teinte (tiroir ouvert).
  /// Sinon, chaque chose à son tour : l'appareil de l'emplacement prend la
  /// teinte, les autres teintes se rangent derrière lui, et seulement alors
  /// on débranche et on échange.
  void _swatch(IpodModel m, Future<void> folded) {
    if (m.family == _model.family) {
      if (m.id == _model.id) return;
      WheelClick.instance.play();
      _choose(m);
      return;
    }
    if (_phase != _Swap.none || _swatchPending) return;
    _swatchPending = true;
    setState(() => _shown[m.family] = m);
    folded.whenComplete(() {
      _swatchPending = false;
      if (mounted) _pick(m);
    });
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
  Widget _drawer(double width, bool right, Size layoutSize) {
    // (La langue aussi : noms des modèles et des teintes, mini-écrans.)
    final key = (width, right, layoutSize, Lang.current, _model.id, _shown.values.map((m) => m.id).join(','));
    if (key != _drawerCacheKey) {
      _drawerCacheKey = key;
      if (_drawerSnap.allowSnapshotting) {
        _drawerSnap.allowSnapshotting = false;
        _drawerSnap.allowSnapshotting = true;
      }
      // Impeller ne garde rien d'une image à l'autre : pendant que le tiroir
      // glisse, on fait glisser une photo de lui, prise une fois, au lieu de
      // tout repeindre (mousse, grain, ombres floues, miniatures).
      _drawerCache = SnapshotWidget(
        controller: _drawerSnap,
        mode: SnapshotMode.permissive,
        child: Padding(
          // Place pour l'ombre du tiroir.
          padding: const EdgeInsets.all(_shadowPad),
          child: MouseRegion(
            onEnter: (_) => _drawerHover(true),
            onExit: (_) => _drawerHover(false),
            // On l'attrape n'importe où : façade, coque ou mousse.
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
          layoutSize: layoutSize,
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
  @override
  _Geo? _geoShown;

  /// Mise en place pour une fenêtre [w] × [h] : où est l'appareil au repos,
  /// la largeur du tiroir, et de combien l'appareil rétrécit et s'écarte
  /// (à droite ou à gauche) quand le tiroir est ouvert.
  _Geo _geometry(double w, double h) {
    // Comme la mise en page de l'appareil : centré, marges, réduit pour
    // tenir (jamais agrandi).
    final m = _model;
    final pad = _devicePadding(w, h);
    final f = math.min(1.0, math.min((w - pad.horizontal) / m.size.width, (h - pad.vertical) / m.size.height));
    final size = m.size * f;
    final left = (w - size.width - pad.horizontal) / 2 + pad.left;
    final top = (h - size.height - pad.vertical) / 2 + pad.top;
    final device = Rect.fromLTWH(left, top, size.width, size.height);

    if (_managedPadding(w, h) != null) {
      // La fenêtre fait la place au tiroir : l'appareil ne bouge pas.
      return (
        device: device,
        cornerRadius: m.cornerRadius * f,
        drawerW: _managedDrawerW(device.width),
        room: 1.0,
        shiftRight: 0.0,
        shiftLeft: 0.0,
        drawerHeight: device.height * 0.9,
      );
    }
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

  /// Marge autour de l'appareil : son ombre, et la place pour la prise (ou,
  /// fenêtre réglée par l'appli, ce qui le met là où il est à l'écran).
  EdgeInsets _devicePadding(double w, double h) =>
      _managedPadding(w, h) ??
      (_model.jackOnTop
          ? _model.margin.copyWith(top: math.max(_model.margin.top, h * 0.2))
          : _model.margin.copyWith(bottom: math.max(_model.margin.bottom, h * 0.2)));

  /// Poignée cachée derrière un coin du haut de l'appareil [dev] : quand la
  /// souris approche de ce coin, elle glisse dehors ; cliquée ou tirée, le
  /// tiroir sort de ce côté. Tiroir ouvert, elle n'a plus lieu d'être.
  Widget _handle(int side, Rect dev, double corner, double openC) {
    final peek = (side < 0 ? _peekL : _peekR).value;
    const width = 40.0, height = 46.0, reach = 22.0;
    // Zone sensible bien au-delà du flanc, même quand on ne voit rien : au
    // dessus de la poignée, et en dessous jusqu'à mi-chemin du bouton de
    // déplacement (qui prend la suite, voir [_moveHandle]).
    const zone = 60.0, above = 24.0, below = 4.0;
    final out = peek * reach;
    final top = dev.top + corner + 10;
    return Positioned(
      left: side > 0 ? dev.right - width : dev.left - zone,
      top: top - above,
      width: width + zone,
      height: above + height + below,
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
                  top: above,
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

  /// Bouton de déplacement, juste sous la poignée du tiroir, du même métal :
  /// une flèche à la place de l'encoche. Cliqué, l'iPod va d'un cran de ce
  /// côté de la fenêtre.
  Widget _moveHandle(int side, Rect dev, double corner, double openC) {
    final peek = (side < 0 ? _movePeekL : _movePeekR).value;
    // Zone sensible : même largeur que celle de la poignée du tiroir, depuis
    // la fin de la sienne (mi-écart) jusqu'un peu sous le bouton.
    const width = 40.0, height = 30.0, reach = 22.0, zone = 60.0, above = 4.0, below = 20.0;
    final out = peek * reach;
    // Sous la poignée du tiroir (46 de haut), avec un petit écart.
    final top = dev.top + corner + 10 + 46 + 8;
    final active = _canMove(side) && openC < 0.05;
    return Positioned(
      left: side > 0 ? dev.right - width : dev.left - zone,
      top: top - above,
      width: width + zone,
      height: above + height + below,
      child: IgnorePointer(
        ignoring: openC > 0.05,
        child: MouseRegion(
          cursor: active ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => _setHoverMove(side, true),
          onExit: (_) => _setHoverMove(side, false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _nudge(side),
            child: Stack(
              children: [
                Positioned(
                  left: side > 0 ? out : zone - out,
                  top: above,
                  width: width,
                  height: height,
                  child: Opacity(
                    opacity: (peek.clamp(0.0, 1.0) * (1 - openC)).toDouble(),
                    child: CustomPaint(painter: _HandlePainter(side, arrow: true)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Sur la façade de l'appareil (qui est dessiné par-dessus les poignées),
  /// le prolongement de leurs zones sensibles vers l'intérieur, jusqu'à mordre
  /// un peu sur l'écran : la souris qui y passe fait sortir les poignées de
  /// ce coin. Survol seulement, les clics vont toujours à l'iPod.
  List<Widget> _hoverInside(int side, Rect dev, double corner, double openC) {
    const inside = 72.0;
    final top = dev.top + corner + 10;
    Widget region(double from, double to, void Function(int, bool) hover) => Positioned(
          left: side > 0 ? dev.right - inside : dev.left,
          top: from,
          width: inside,
          height: to - from,
          child: IgnorePointer(
            ignoring: openC > 0.05,
            child: MouseRegion(
              opaque: false,
              hitTestBehavior: HitTestBehavior.translucent,
              onEnter: (_) => hover(side, true),
              onExit: (_) => hover(side, false),
            ),
          ),
        );
    // Mêmes bornes verticales que [_handle] et [_moveHandle].
    return [
      region(top - 24, top + 50, _setHoverSide),
      region(top + 50, top + 104, _setHoverMove),
    ];
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

          final devicePad = _devicePadding(w, h);
          final deviceKey = (_model.id, devicePad);
          if (deviceKey != _deviceCacheKey) {
            _deviceCacheKey = deviceKey;
            _deviceCache = Center(
              key: ValueKey(_model.id),
              child: Padding(
                // Marge pour l'ombre portée, et de la place en haut pour la
                // prise et le câble.
                padding: devicePad,
                // Couche à part : pendant que le tiroir bouge, l'appareil
                // n'est pas repeint, seulement déplacé.
                child: RepaintBoundary(
                  child: FittedBox(
                    child: IpodDevice(
                        key: _deviceKey(_model),
                        model: _model,
                        player: widget.player,
                        nav: _nav,
                        onWindowDrag: _beginWindowDrag,
                      ),
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
                child.key == ValueKey(_model.id) ? FadeTransition(opacity: anim, child: _FadePhoto(anim, child)) : child,
            child: _deviceCache,
          );
          // Pendant que le tiroir glisse, l'appareil rétrécit : on fait
          // rétrécir une photo de lui (ses ombres floues coûtent trop cher à
          // recalculer à chaque taille). Immobile, il redevient vivant.
          device = SnapshotWidget(controller: _deviceSnap, mode: SnapshotMode.permissive, child: device);
          // L'appareil s'écarte et rétrécit pour laisser la place au tiroir :
          // ensemble, ils restent centrés dans la fenêtre.
          final scale = 1 + (g.room - 1) * openC;
          // Sa place à gauche ou à droite : tiroir ouvert, il revient au
          // milieu avec lui.
          _placeReach = _managedPadding(w, h) != null ? 0 : math.max(0.0, g.device.left - 14);
          final placed = _place.value * _placeReach;
          final shift = (_deviceShift = (right ? g.shiftRight : g.shiftLeft) * open) + placed * (1 - openC);
          if (shift != 0 || scale != 1) {
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
                // Un clic à côté du tiroir le referme. Toujours là (inactif
                // tiroir fermé) : l'ajouter ou l'enlever décalerait les
                // enfants suivants, et Flutter reconstruirait tout le tiroir
                // (et sa photo) à chaque ouverture et fermeture.
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_wantOpen,
                    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _setOpen(false)),
                  ),
                ),
                // Les deux poignées, derrière les coins du haut.
                for (final side in const [-1, 1]) _handle(side, dev, g.cornerRadius * scale, openC),
                // Et sous chacune, le bouton qui décale l'iPod de ce côté.
                for (final side in const [-1, 1]) _moveHandle(side, dev, g.cornerRadius * scale, openC),
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
                            // Disposé pour sa taille d'arrivée : pendant qu'il
                            // change de taille, seule la coque suit.
                            child: _drawer(target.drawerW - _tuck, right, Size(target.drawerW, target.drawerHeight)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                deviceLayer,
                for (final side in const [-1, 1]) ..._hoverInside(side, dev, g.cornerRadius * scale, openC),
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

/// Pendant le fondu d'un changement de teinte, l'appareil qui apparaît
/// n'est qu'une photo : fondre l'appareil vivant (ombres floues, écran)
/// obligerait à le repeindre entier dans une couche à part à chaque image.
class _FadePhoto extends StatefulWidget {
  const _FadePhoto(this.anim, this.child);

  final Animation<double> anim;
  final Widget child;

  @override
  State<_FadePhoto> createState() => _FadePhotoState();
}

class _FadePhotoState extends State<_FadePhoto> {
  final _snap = SnapshotController();

  @override
  void initState() {
    super.initState();
    widget.anim.addStatusListener(_status);
    _status(widget.anim.status);
  }

  void _status(AnimationStatus s) => _snap.allowSnapshotting = s.isAnimating;

  @override
  void dispose() {
    widget.anim.removeStatusListener(_status);
    _snap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SnapshotWidget(controller: _snap, mode: SnapshotMode.permissive, autoresize: true, child: widget.child);
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
