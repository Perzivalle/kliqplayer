part of 'ipod.dart';

/// Zone de travail (l'écran sans la barre des tâches) de l'écran où se
/// trouve [window], parmi [screens] (chacun : ses limites et sa zone de
/// travail). Si elle couvre l'écran entier (barre des tâches masquée), on
/// lui retire une ligne : Windows prend une fenêtre qui couvre exactement
/// l'écran pour une appli en plein écran, passe la barre des tâches derrière
/// et coupe les notifications.
@visibleForTesting
Rect? workAreaFor(Rect window, List<({Rect bounds, Rect work})> screens) {
  if (screens.isEmpty) return null;
  final screen = screens.firstWhere((s) => s.bounds.contains(window.center), orElse: () => screens.first);
  final work = screen.work.isEmpty ? screen.bounds : screen.work;
  return work == screen.bounds ? Rect.fromLTRB(work.left, work.top, work.right, work.bottom - 1) : work;
}

/// Étend [window] à toute la zone de travail de son écran (Windows) : la
/// fenêtre, transparente et sans bord, est la scène où l'iPod se déplace.
Rect? fillWorkArea(Window window) {
  try {
    final now = window.contentBounds.toRect();
    final area = _workAreaOf(now);
    if (area == null || area.isEmpty) return null;
    final exact = (now.left - area.left).abs() < 0.5 &&
        (now.top - area.top).abs() < 0.5 &&
        (now.right - area.right).abs() < 0.5 &&
        (now.bottom - area.bottom).abs() < 0.5;
    if (!exact) window.contentBounds = area.toNative();
    return area;
  } catch (_) {
    return null;
  }
}

Rect? _workAreaOf(Rect window) => workAreaFor(window, [
      for (final d in DisplayManager.instance.getAll())
        (bounds: d.position.toOffset() & d.size.toSize(), work: d.workArea.toRect()),
    ]);

/// Ce qu'est devenue la fenêtre plein écran après que Windows l'a déplacée
/// ou retaillée.
enum WindowFit {
  /// Elle couvre la zone de travail : rien à faire.
  fills,

  /// Windows l'a rangée dans une zone (Win+flèche, zones d'ancrage) : elle y
  /// reste, l'iPod vit dedans.
  docked,

  /// Ailleurs sans avoir été rangée (autre écran, sortie de sa zone, écran
  /// qui change) : on la recale sur la zone de travail.
  refit,
}

/// Où en est la fenêtre, en [now], sur un écran dont la zone de travail est
/// [area]. [lastFill] : la taille qu'on lui a donnée en dernier pour couvrir
/// un écran. Rangée, elle est nettement plus petite que la zone de travail ;
/// si elle a gardé la taille d'un plein écran, c'est qu'elle a seulement
/// changé de place.
@visibleForTesting
WindowFit windowFit(Rect now, Rect area, Size? lastFill) {
  bool near(double a, double b) => (a - b).abs() <= 12;
  if (near(now.left, area.left) && near(now.top, area.top) && near(now.right, area.right) && near(now.bottom, area.bottom)) {
    return WindowFit.fills;
  }
  final kept = lastFill != null && near(now.width, lastFill.width) && near(now.height, lastFill.height);
  final smaller = now.width < area.width * 0.92 || now.height < area.height * 0.92;
  return smaller && !kept ? WindowFit.docked : WindowFit.refit;
}

/// Contour d'un seul tenant qui englobe [zones] (des rectangles qui se
/// touchent), sommet par sommet : à chaque hauteur, du bord le plus à gauche
/// au bord le plus à droite. C'est la découpe de la fenêtre plein écran :
/// hors d'elle, rien n'est dessiné et les clics vont aux fenêtres du dessous.
@visibleForTesting
List<Offset> outlineOf(List<Rect> zones) {
  final rects = [for (final z in zones) if (!z.isEmpty) z];
  if (rects.isEmpty) return const [];
  final ys = ({for (final r in rects) ...[r.top, r.bottom]}.toList())..sort();
  // Par tranche horizontale : bord gauche et bord droit.
  final bands = <({double top, double bottom, double left, double right})>[];
  for (var i = 0; i + 1 < ys.length; i++) {
    final top = ys[i], bottom = ys[i + 1];
    double? left, right;
    for (final r in rects) {
      if (r.top <= top && r.bottom >= bottom) {
        left = left == null ? r.left : math.min(left, r.left);
        right = right == null ? r.right : math.max(right, r.right);
      }
    }
    if (left == null || right == null) {
      // Un vide entre deux zones : un pont étroit, pour rester d'un seul tenant.
      if (bands.isEmpty) continue;
      final mid = (bands.last.left + bands.last.right) / 2;
      left = mid - 1;
      right = mid + 1;
    }
    if (bands.isNotEmpty && bands.last.left == left && bands.last.right == right) {
      bands[bands.length - 1] = (top: bands.last.top, bottom: bottom, left: left, right: right);
    } else {
      bands.add((top: top, bottom: bottom, left: left, right: right));
    }
  }
  final points = <Offset>[];
  void add(Offset p) {
    if (points.isEmpty || points.last != p) points.add(p);
  }

  // Le flanc droit en descendant, puis le gauche en remontant.
  for (final b in bands) {
    add(Offset(b.right, b.top));
    add(Offset(b.right, b.bottom));
  }
  for (final b in bands.reversed) {
    add(Offset(b.left, b.bottom));
    add(Offset(b.left, b.top));
  }
  return points;
}

/// La fenêtre que l'appli règle elle-même : autour de l'appareil (macOS),
/// ou en plein écran transparent découpé autour de lui (Windows). À part de
/// la scène : ce qu'elle a besoin d'en savoir tient en quelques lignes.
mixin _ManagedWindow on State<IpodStage> {
  IpodModel get _model;
  IpodModel? get _incoming;
  int get _side;
  _Geo? get _geoShown;
  bool get _remember;

  // --- Fenêtre réglée par l'appli (Windows, macOS) ---------------------------
  //
  // Sous Windows et macOS, l'appli place et taille elle-même sa fenêtre
  // autour de l'appareil, qui, lui, ne bouge pas à l'écran : elle va jusqu'au
  // bord de l'écran du côté du câble (on le voit partir jusqu'au bout), et
  // s'élargit du côté du tiroir quand il sort (l'appareil n'a plus à
  // rétrécir). Sous Linux, c'est le gestionnaire de fenêtres qui décide
  // (souvent en mosaïque) : on s'adapte à ce qu'il donne, comme avant.

  late final Window? _win = _remember && Platform.isMacOS ? _currentWindow() : null;

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
  double _drawerRoom(double deviceW) => _managedDrawerW(deviceW) - _IpodStageState._tuck + 18;

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

  // --- Plein écran transparent (Windows) ------------------------------------
  //
  // Sous Windows, pas de gestionnaire qui range les fenêtres : la fenêtre
  // couvre toute la zone de travail, transparente, et l'iPod s'y tient à
  // gauche, au milieu ou à droite, comme dans une grande fenêtre sous Linux.
  // Pour qu'elle ne confisque pas les clics du bureau, elle est découpée
  // autour de l'appareil et de son câble tant que rien ne bouge ; tiroir
  // sorti, échange, déplacement : elle redevient entière (un clic à côté
  // referme le tiroir).

  late final Window? _full = _remember && Platform.isWindows ? _currentWindow() : null;

  // Rangée par Windows dans une zone (Win+flèche, zones d'ancrage en haut
  // de l'écran) : la fenêtre garde cette zone, et l'iPod y vit comme dans
  // une tuile sous Linux. Agrandie (Win+Haut) ou sortie de sa zone, elle
  // redevient le plein écran.
  bool _docked = false;

  /// Taille donnée en dernier à la fenêtre pour couvrir un écran.
  Size? _lastFill;

  /// L'iPod se déplace dans la fenêtre quand on le tient (au lieu de
  /// déplacer la fenêtre) : en plein écran, pas dans une zone.
  bool get _dragsInside => (_full != null && !_docked) || IpodStage.debugDragInside;

  Timer? _refit;
  List<Offset>? _shape;
  Size? _shapeFor;

  /// La fenêtre est prête : au premier plan si on l'a demandé ; et à chaque
  /// fois qu'elle bouge ou change de taille, on regarde ce qu'elle est
  /// devenue.
  void _takeFullWindow() {
    final win = _full;
    if (win == null) return;
    void onTop() {
      try {
        win.isAlwaysOnTop = windowOnTop.value;
      } catch (_) {}
    }

    onTop();
    windowOnTop.addListener(onTop);
    try {
      _lastFill = win.contentBounds.toRect().size;
      win.addListener((e) {
        if (!mounted || (e is! WindowMovedEvent && e is! WindowResizedEvent)) return;
        _refit?.cancel();
        _refit = Timer(const Duration(milliseconds: 300), _windowSettled);
      });
    } catch (_) {}
  }

  /// La fenêtre ne bouge plus : rangée dans une zone, elle y reste ; sinon
  /// elle couvre la zone de travail de son écran.
  void _windowSettled() {
    final win = _full;
    if (win == null || !mounted) return;
    // Encore tenue à la souris (on hésite au-dessus des zones d'ancrage) :
    // on attend qu'elle soit lâchée, sans la lui reprendre des mains.
    if (_mouseHeld()) {
      _refit = Timer(const Duration(milliseconds: 200), _windowSettled);
      return;
    }
    try {
      final now = win.contentBounds.toRect();
      final area = _workAreaOf(now);
      if (area == null || area.isEmpty) return;
      final fit = win.isMaximized ? WindowFit.refit : windowFit(now, area, _lastFill);
      if (fit == WindowFit.refit) {
        if (win.isMaximized) win.unmaximize();
        _lastFill = (fillWorkArea(win) ?? area).size;
      }
      final docked = fit == WindowFit.docked;
      if (docked != _docked) setState(() => _docked = docked);
    } catch (_) {}
  }

  static final int Function(int)? _keyState = () {
    if (!Platform.isWindows) return null;
    try {
      return ffi.DynamicLibrary.open('user32.dll')
          .lookupFunction<ffi.Int16 Function(ffi.Int32), int Function(int)>('GetAsyncKeyState');
    } catch (_) {
      return null;
    }
  }();

  /// Un bouton de la souris est enfoncé (gauche ou droit : ils peuvent être
  /// inversés).
  static bool _mouseHeld() {
    final state = _keyState;
    if (state == null) return false;
    try {
      return state(0x01) & 0x8000 != 0 || state(0x02) & 0x8000 != 0;
    } catch (_) {
      return false;
    }
  }

  /// Tiré vers le haut pendant qu'on le tient : on passe la main à Windows,
  /// qui déplace la fenêtre et propose ses zones d'ancrage.
  void _handToSystem() {
    try {
      _full?.startDragging();
    } catch (_) {}
  }

  /// Découpe la fenêtre ([w] × [h]) : entière si [whole], sinon autour de
  /// l'appareil (en [dev] à l'écran, avec ses poignées et son ombre) et de
  /// son câble, jusqu'au bord.
  void _shapeWindow(double w, double h, Rect dev, {required bool whole}) {
    final win = _full;
    if (win == null) return;
    final all = Offset.zero & Size(w, h);
    final List<Offset> points;
    if (whole) {
      points = [all.topLeft, all.topRight, all.bottomRight, all.bottomLeft];
    } else {
      final jack = dev.left + _model.jackX * dev.width / _model.size.width;
      points = outlineOf([
        // Les poignées sortent de 60 de chaque côté ; l'ombre tombe dessous.
        Rect.fromLTRB(dev.left - 84, dev.top - 34, dev.right + 84, dev.bottom + 90).intersect(all),
        (_model.jackOnTop
                ? Rect.fromLTRB(jack - 54, 0, jack + 54, dev.top)
                : Rect.fromLTRB(jack - 54, dev.bottom, jack + 54, h))
            .intersect(all),
      ]);
    }
    final rounded = [for (final p in points) Offset(p.dx.roundToDouble(), p.dy.roundToDouble())];
    final size = Size(w, h);
    if (rounded.length < 3 || (_shapeFor == size && listEquals(_shape, rounded))) return;
    try {
      final shape = WindowShape.create();
      if (shape == null) return;
      for (final p in rounded) {
        shape.addPoint(Point(x: p.dx, y: p.dy));
      }
      if (win.setShape(shape)) {
        _shape = rounded;
        _shapeFor = size;
      }
      shape.dispose();
    } catch (_) {}
  }
}
