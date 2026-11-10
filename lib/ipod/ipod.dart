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
  IpodModel? _incoming;

  /// Hauteur dont la prise est sortie, en unités de l'appareil (0 = enfoncée).
  final _plug = Spring(0, stiffness: 500, damping: 0.55);
  double _plugTarget = 0;
  double _plugHold = 0;
  bool _plugClicked = false;

  /// Le grésillement de la pointe qui entre a déjà été joué.
  bool _plugCrackled = false;

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
    widget.player.setForcedShuffle(!_model.hasScreen);
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

  /// LECTEUR_BENCH=1 : joue chaque animation l'une après l'autre (menus,
  /// Cover Flow, En lecture, tiroir, teintes, échanges) et affiche pour
  /// chacune les temps d'image (construction ui, rendu raster), puis quitte.
  /// Le son est coupé le temps du banc ; le modèle en main est remis à la fin.
  Future<void> _bench() async {
    final only = Platform.environment['LECTEUR_BENCH']!;
    final build = <double>[], raster = <double>[], at = <int>[];
    var recording = false;
    var t0 = 0;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      if (!recording) return;
      for (final t in timings) {
        build.add(t.buildDuration.inMicroseconds / 1000);
        raster.add(t.rasterDuration.inMicroseconds / 1000);
        at.add(t.timestampInMicroseconds(ui.FramePhase.vsyncStart) ~/ 1000 - t0);
      }
    });
    Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
    Future<void> run(String name, Future<void> Function() body) async {
      if (only != '1' && !only.split(',').contains(name)) return;
      build.clear();
      raster.clear();
      at.clear();
      t0 = now();
      recording = true;
      await body();
      await wait(400); // les derniers temps arrivent par paquets
      recording = false;
      if (raster.isEmpty) {
        stdout.writeln('[bench] ${name.padRight(14)} aucune image');
        return;
      }
      String f(double v) => v.toStringAsFixed(1).padLeft(5);
      final sorted = [...raster]..sort();
      double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
      final slowAt = [for (var i = 0; i < build.length; i++) if (build[i] > 16.7 || raster[i] > 16.7) i];
      final slow = '${slowAt.length} ${[for (final i in slowAt) '@${at[i]}ms:${raster[i].round()}']}';
      stdout.writeln('[bench] ${name.padRight(14)} ${raster.length.toString().padLeft(4)} img · '
          'raster moy${f(avg(raster))} p90${f(sorted[(sorted.length * 0.9).floor()])} max${f(sorted.last)} · '
          'ui moy${f(avg(build))} max${f(build.reduce(math.max))} · lentes $slow');
    }

    void goTo(String label) {
      final p = _nav.page;
      if (p is! MenuPage) return;
      final i = p.entries.indexWhere((e) => e.label == label);
      if (i < 0) return;
      _nav.scroll(i - p.selected);
      _nav.select();
    }

    Future<void> home() async {
      while (_nav.stack.length > 1) {
        _nav.menu();
        await wait(350);
      }
    }

    final volume = widget.player.volume;
    final start = _model;
    widget.player.setVolume(0);
    // Montée de l'iPod, puis la prise qui se branche et l'écran qui s'allume.
    await run('démarrage', () async {
      ipodLanded.addListener(() => stdout.writeln('[bench]   arrivé @${now() - t0}ms'));
      screenPower.addListener(() => stdout.writeln('[bench]   écran ${screenPower.value} @${now() - t0}ms'));
      await wait(3000);
    });

    await run('repos', () => wait(1500));
    await run('menu-entrer', () async {
      for (var i = 0; i < 3; i++) {
        goTo(tr('Musique'));
        await wait(450);
        _nav.menu();
        await wait(450);
      }
    });
    goTo(tr('Musique'));
    await wait(400);
    goTo(tr('Morceaux'));
    await wait(400);
    await run('menu-défiler', () async {
      for (var i = 0; i < 25; i++) {
        _nav.scroll(1);
        await wait(70);
      }
      for (var i = 0; i < 25; i++) {
        _nav.scroll(-1);
        await wait(70);
      }
      await wait(300);
    });
    _nav.select(); // joue le morceau, passe à En lecture
    await wait(800);
    await run('en-lecture', () async {
      await wait(2000);
      _nav.scroll(1); // volume
      await wait(1800);
    });
    await home();
    goTo(tr('Musique'));
    await wait(400);
    if (_nav.page case final MenuPage p when p.entries.any((e) => e.label == 'Cover Flow')) {
      goTo('Cover Flow');
      await wait(600);
      await run('coverflow', () async {
        for (var i = 0; i < 12; i++) {
          _nav.scroll(1);
          await wait(130);
        }
        await wait(500);
      });
      await run('coverflow-bis', () async {
        // Mêmes pochettes, déjà chargées.
        for (var i = 0; i < 12; i++) {
          _nav.scroll(-1);
          await wait(130);
        }
        await wait(500);
      });
      await run('pochette', () async {
        _nav.select();
        await wait(900);
        _nav.menu();
        await wait(900);
      });
    }
    await home();
    // Souris qui approche d'un coin du haut : les poignées sortent, rentrent.
    await run('poignées', () async {
      for (final side in [1, -1, 1]) {
        _setHoverSide(side, true);
        await wait(600);
        _setHoverSide(side, false);
        await wait(600);
      }
    });
    // L'iPod d'un bord à l'autre de la fenêtre, puis remis à sa place.
    final place = _placeTarget;
    if (_canPlace) {
      await run('déplacer', () async {
        for (final to in [-1, 1, 0]) {
          stdout.writeln('[bench]   vers $to @${now() - t0}ms');
          _moveTo(to);
          await wait(900);
        }
      });
      _moveTo(place);
      await wait(900);
    }
    await run('tiroir', () async {
      for (final open in [true, false, true, false]) {
        _setOpen(open);
        await wait(1100);
      }
    });
    _setOpen(true);
    await wait(1100);
    final family = _families.firstWhere((f) => f.first.family == _model.family);
    // Souris sur le tiroir, comme quand on clique une pastille.
    _drawerHover(true);
    await wait(500);
    await run('teinte', () async {
      for (final m in family.length > 1 ? [...family.skip(1), family.first] : <IpodModel>[]) {
        stdout.writeln('[bench]   choix @${now() - t0}ms');
        _choose(m);
        await wait(700);
      }
    });
    await run('quitte-tiroir', () async {
      _drawerHover(false);
      await wait(1200);
    });
    await run('échange', () async {
      final other = start.family == 'mini' ? ipodModels.firstWhere((m) => m.family == 'nano4') : ipodModels.firstWhere((m) => m.family == 'mini');
      _pick(other);
      await wait(4500);
      _setOpen(true);
      await wait(1100);
      _pick(start);
      await wait(4500);
    });
    if (_model.id != start.id) _choose(start);
    widget.player.setVolume(volume);
    widget.player.pause();
    await wait(300);
    Settings.flush();
    for (final a in widget.player.accounts) {
      a.shutdown();
    }
    exit(0);
  }

  static int now() => Timeline.now ~/ 1000;

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

  // --- Fenêtre réglée par l'appli (Windows, macOS) ---------------------------
  //
  // Sous Windows et macOS, l'appli place et taille elle-même sa fenêtre
  // autour de l'appareil, qui, lui, ne bouge pas à l'écran : elle va jusqu'au
  // bord de l'écran du côté du câble (on le voit partir jusqu'au bout), et
  // s'élargit du côté du tiroir quand il sort (l'appareil n'a plus à
  // rétrécir). Sous Linux, c'est le gestionnaire de fenêtres qui décide
  // (souvent en mosaïque) : on s'adapte à ce qu'il donne, comme avant.

  late final Window? _win = _remember && (Platform.isWindows || Platform.isMacOS) ? _currentWindow() : null;

  static Window? _currentWindow() {
    try {
      return WindowManager.instance.getCurrent();
    } catch (_) {
      return null;
    }
  }

  /// L'appareil à l'écran (coordonnées de l'écran), une fois la fenêtre
  /// prise en main.
  Rect? _anchor;

  /// Limites de la fenêtre demandées en dernier, et les précédentes : tant
  /// que Flutter n'a pas reçu la nouvelle taille, l'image se dessine encore
  /// dans l'ancienne fenêtre.
  Rect? _frame, _framePrev;

  /// La fenêtre fait la place au tiroir (ouvert, ou en train de bouger).
  bool _frameDrawer = false;

  /// Déplacement de la fenêtre à la main : d'où elle part, et l'appareil à
  /// ce moment-là ; on la réajuste quand elle ne bouge plus.
  Offset? _dragFrom;
  Rect? _dragAnchor;
  Timer? _dragSettle;

  Rect _windowRect() => _win!.contentBounds.toRect();

  static bool _near(Rect a, Rect b) =>
      (a.left - b.left).abs() < 0.5 && (a.top - b.top).abs() < 0.5 && (a.right - b.right).abs() < 0.5 && (a.bottom - b.bottom).abs() < 0.5;

  /// Largeur du tiroir quand la fenêtre lui fait la place : à la mesure de
  /// l'appareil, comme dans une grande fenêtre.
  double _managedDrawerW(double deviceW) => (deviceW * 1.3).clamp(230.0, 460.0);

  /// Ce que la fenêtre ajoute à côté de l'appareil pour le tiroir ouvert.
  double _drawerRoom(double deviceW) => _managedDrawerW(deviceW) - _tuck + 18;

  /// L'écran où est l'appareil.
  Rect _screenOf(Rect r) {
    Rect? best;
    try {
      for (final d in DisplayManager.instance.getAll()) {
        final screen = d.position.toOffset() & d.size.toSize();
        if (screen.contains(r.center)) return screen;
        best ??= screen;
      }
    } catch (_) {}
    return best ?? r.inflate(400);
  }

  /// Limites voulues pour la fenêtre, l'appareil [model] étant en [device]
  /// à l'écran.
  Rect _frameFor(IpodModel model, Rect device) => windowFrameFor(
        model,
        device,
        _screenOf(device),
        drawerSide: _frameDrawer ? _side : 0,
        drawerRoom: _drawerRoom(device.width),
      );

  /// Ajuste la fenêtre : autour de l'appareil en main (et, pendant un
  /// échange, aussi autour du nouveau, centré au même endroit).
  void _applyFrame() {
    final win = _win;
    final anchor = _anchor;
    if (win == null || anchor == null || _dragFrom != null) return;
    var frame = _frameFor(_model, anchor);
    final incoming = _incoming;
    if (incoming != null) {
      final other = Rect.fromCenter(center: anchor.center, width: incoming.size.width, height: incoming.size.height);
      frame = frame.expandToInclude(_frameFor(incoming, other));
    }
    if (_frame != null && _near(_frame!, frame)) return;
    _framePrev = _frame;
    _frame = frame;
    try {
      win.contentBounds = frame.toNative();
    } catch (_) {}
    setState(() {});
  }

  /// Première image : on note où est l'appareil à l'écran, puis la fenêtre
  /// se met à sa mesure autour de lui.
  void _takeWindow() {
    final win = _win;
    if (win == null || _anchor != null) return;
    final g = _geoShown;
    if (g == null) return;
    final origin = _windowRect().topLeft;
    // À sa vraie taille : la fenêtre va se faire à sa mesure.
    _anchor = Rect.fromCenter(center: g.device.center + origin, width: _model.size.width, height: _model.size.height);
    win.addListener((e) {
      if (e is WindowMovedEvent && _dragFrom != null && mounted) {
        // L'appareil suit la fenêtre qu'on déplace.
        // (La zone de contenu, comme [_dragFrom] : pas le cadre de la fenêtre.)
        _anchor = _dragAnchor!.shift(_windowRect().topLeft - _dragFrom!);
        _dragSettle?.cancel();
        _dragSettle = Timer(const Duration(milliseconds: 250), _endWindowDrag);
      }
    });
    _applyFrame();
  }

  /// On attrape l'appareil pour déplacer la fenêtre.
  void _beginWindowDrag() {
    if (_win == null || _anchor == null) return;
    _dragFrom = _windowRect().topLeft;
    _dragAnchor = _anchor;
    _dragSettle?.cancel();
    _dragSettle = Timer(const Duration(milliseconds: 600), _endWindowDrag);
  }

  /// Lâchée (elle ne bouge plus) : la fenêtre se réajuste à sa nouvelle place
  /// (jusqu'au bord de l'écran, peut-être un autre).
  void _endWindowDrag() {
    if (!mounted || _dragFrom == null) return;
    _dragFrom = null;
    _dragAnchor = null;
    _frame = null;
    _applyFrame();
  }

  /// Marges de l'appareil dans une fenêtre réglée par l'appli : il est là où
  /// il est à l'écran, à sa taille.
  EdgeInsets? _managedPadding(double w, double h) {
    final anchor = _anchor;
    if (_win == null || anchor == null) return null;
    final frame = _frame, prev = _framePrev;
    final Offset origin;
    if (_dragFrom != null || frame == null) {
      origin = _windowRect().topLeft;
    } else if (((frame.width - w).abs() < 1 && (frame.height - h).abs() < 1) || prev == null) {
      origin = frame.topLeft;
    } else {
      origin = prev.topLeft; // la nouvelle taille n'est pas encore arrivée
    }
    final left = anchor.left - origin.dx, top = anchor.top - origin.dy;
    return EdgeInsets.fromLTRB(left, top, w - left - anchor.width, h - top - anchor.height);
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
    _resumeOnPlug = widget.player.playing;
    if (_resumeOnPlug) widget.player.pause();
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
      _sway.velocity -= v * 0.9 * dt * 60 / 60;
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
    widget.player.setForcedShuffle(!m.hasScreen);
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

class IpodDevice extends StatefulWidget {
  const IpodDevice({super.key, required this.model, required this.player, required this.nav, this.onWindowDrag});

  final IpodModel model;
  final PlayerController player;

  /// Navigation de la scène, passée d'un appareil à l'autre.
  final IpodNav nav;

  /// On commence à déplacer la fenêtre en tenant l'appareil.
  final VoidCallback? onWindowDrag;

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
  const _HandlePainter(this.side, {this.arrow = false});

  /// 1 : elle dépasse à droite ; -1 : à gauche.
  final int side;

  /// Une flèche gravée vers l'extérieur au lieu de l'encoche (bouton qui
  /// déplace l'iPod).
  final bool arrow;

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
    if (arrow) {
      // Chevron gravé : un trait sombre, doublé d'un reflet en dessous.
      final c = Offset(size.width - 11, size.height / 2);
      final path = Path()
        ..moveTo(c.dx - 3, c.dy - 5)
        ..lineTo(c.dx + 2, c.dy)
        ..lineTo(c.dx - 3, c.dy + 5);
      Paint stroke() => Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      // Même teinte que l'encoche de l'autre poignée.
      final ink = stroke()
        ..shader = ui.Gradient.linear(
          Offset(c.dx - 4, c.dy),
          Offset(c.dx + 3, c.dy),
          const [Color(0xFF7C8085), Color(0xFFD2D5D8)],
        );
      canvas
        ..drawPath(path.shift(const Offset(0, 1)), stroke()..color = Colors.white.withValues(alpha: 0.7))
        ..drawPath(path, ink);
      return;
    }
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
  bool shouldRepaint(covariant _HandlePainter old) => old.side != side || old.arrow != arrow;
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
