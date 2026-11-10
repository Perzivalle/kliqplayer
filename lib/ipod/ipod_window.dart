part of 'ipod.dart';

/// La fenêtre que l'appli règle elle-même autour de l'appareil (Windows,
/// macOS), à part de la scène : ce qu'elle a besoin d'en savoir tient en
/// quelques lignes.
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
}
