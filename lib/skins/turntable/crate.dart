import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/library.dart';
import '../../core/player.dart';
import '../../physics.dart';
import 'search_note.dart';

/// Dimensions du bac à disques, dans le même repère que la platine.
class CrateGeometry {
  static const double width = 760;
  static const double height = 1000;

  /// Côté d'une pochette au premier rang.
  static const double sleeve = 470;
  static const double centerX = 380;

  /// Haut de la pochette du premier rang ; les suivantes remontent
  /// (perspective) jusqu'à [stackRise] plus haut.
  static const double frontTop = 460;
  static const double stackRise = 200;
  static const double depthFalloff = 7;

  /// Hauteur dont une pochette sort du bac au survol.
  static const double maxLift = 290;

  /// Inclinaison des disques déjà feuilletés, couchés vers l'avant.
  static const double flipAngle = 1.0;

  /// Paroi avant du bac.
  static const Rect front = Rect.fromLTRB(30, 700, 730, 965);
  static const Rect handle = Rect.fromLTWH(285, 727, 190, 50);

  /// Paroi du fond (cachée en grande partie par les disques).
  static const Rect back = Rect.fromLTRB(95, 545, 665, 885);

  /// Bout de papier de recherche, scotché sur la planche du bas.
  static const Offset note = Offset(52, 800);
}

typedef C = CrateGeometry;

/// Bac de disques : on survole une pochette pour la sortir, on la clique
/// pour la poser sur la platine, la molette fait défiler les disques.
class Crate extends StatefulWidget {
  const Crate({super.key, required this.player, required this.onPick});

  final PlayerController player;

  /// Album choisi, et rectangle de sa pochette (repère du bac).
  final void Function(int album, Rect sleeve) onPick;

  @override
  State<Crate> createState() => _CrateState();
}

class _Slot {
  const _Slot(this.rect, this.tilt, this.shade, this.lift);

  final Rect rect;
  final double tilt;
  final double shade;
  final double lift;
}

class _CrateState extends State<Crate> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;

  PlayerController get player => widget.player;
  List<Album> get albums => player.albums;

  // Défilement : index (fractionnaire) du disque au premier rang.
  final _flip = Spring(5.4, stiffness: 170, damping: 0.86);
  int _flipTarget = 5;
  double _scrollAccumulator = 0;

  // Pochettes soulevées (celle survolée monte, les autres redescendent).
  final Map<int, Spring> _lifts = {};
  int? _hovered;
  Offset? _mouse;

  // Garde le texte de la bulle pendant qu'elle s'efface.
  Album? _lastShown;

  // Recherche écrite sur le bout de papier.
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  int? _searchHit;
  bool _noMatch = false;

  bool _raised(int i) => i == _hovered || i == _searchHit;

  final Map<int, Widget> _sleeves = {};

  @override
  void initState() {
    super.initState();
    player.addListener(_onPlayer);
    player.albumCoversLoaded.addListener(_onCovers);
  }

  @override
  void dispose() {
    player.removeListener(_onPlayer);
    player.albumCoversLoaded.removeListener(_onCovers);
    _ticker.dispose();
    _frame.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  int _albumCount = 0;

  void _onPlayer() {
    if (albums.length != _albumCount) {
      _albumCount = albums.length;
      _sleeves.clear();
      setState(() {});
    }
  }

  void _onCovers() {
    _sleeves.removeWhere((i, _) => player.albumCovers.containsKey(i));
    setState(() {});
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    final step = dt.clamp(0.0, 0.05);

    _flip.step(_flipTarget.toDouble(), step);
    _updateHover();

    for (final MapEntry(key: i, value: spring) in _lifts.entries) {
      spring.step(_raised(i) ? 1 : 0, step);
    }
    _lifts.removeWhere((i, s) => !_raised(i) && s.isSettled);

    _frame.value++;
    if (_flip.isSettled && _lifts.values.every((s) => s.isSettled)) _ticker.stop();
  }

  // --- Disposition ----------------------------------------------------------

  static ({double dx, double rot}) _jitter(int i) {
    final r = math.Random(i * 7919 + 13);
    return (dx: (r.nextDouble() - 0.5) * 10, rot: (r.nextDouble() - 0.5) * 0.014);
  }

  _Slot _slot(int i) {
    final d = i - _flip.value;
    final j = _jitter(i);
    if (d >= 0) {
      // Disque debout : plus il est loin, plus il est haut, petit et sombre.
      final t = 1 - math.exp(-d / C.depthFalloff);
      final size = C.sleeve * (1 - 0.12 * t);
      final lift = _lifts[i]?.value ?? 0;
      final top = C.frontTop - C.stackRise * t;
      final lifted = top - lift * math.min(C.maxLift, top - 30);
      return _Slot(
        Rect.fromLTWH(C.centerX - size / 2 + j.dx, lifted, size, size),
        0,
        0.42 * t * (1 - lift.clamp(0.0, 1.0)),
        lift,
      );
    }
    // Disque déjà feuilleté : il bascule vers l'avant contre la paroi.
    final f = (-d).clamp(0.0, 1.0);
    final extra = (-d - 1).clamp(0.0, 8.0);
    final bottom = C.frontTop + C.sleeve + 6 * f + 3 * extra;
    return _Slot(
      Rect.fromLTWH(C.centerX - C.sleeve / 2 + j.dx, bottom - C.sleeve, C.sleeve, C.sleeve),
      f * C.flipAngle,
      0.5 * f,
      0,
    );
  }

  (int, int) get _visibleRange {
    final first = math.max(0, _flip.value.floor() - 8);
    final last = math.min(albums.length - 1, _flip.value.ceil() + 40);
    return (first, last);
  }

  /// Pochette sous le pointeur : la plus proche de l'avant qui le contient.
  int? _hitTest(Offset p) {
    if (p.dy >= C.front.top) return null;
    final (first, last) = _visibleRange;
    for (var i = first; i <= last; i++) {
      if (i - _flip.value < -0.05) continue;
      if (_slot(i).rect.contains(p)) return i;
    }
    return null;
  }

  void _updateHover() {
    final h = _mouse == null ? null : _hitTest(_mouse!);
    if (h != _hovered) {
      _hovered = h;
      if (h != null) _lastShown = albums[h];
      if (h != null) _lifts.putIfAbsent(h, () => Spring(0, stiffness: 260, damping: 0.72));
      // Reconstruit le curseur et la bulle d'information.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      _wake();
    }
  }

  // --- Gestes ---------------------------------------------------------------

  void _onScroll(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || albums.isEmpty) return;
    _scrollAccumulator += e.scrollDelta.dy;
    const notch = 40.0;
    while (_scrollAccumulator.abs() >= notch) {
      final dir = _scrollAccumulator.sign.toInt();
      _flipTarget = (_flipTarget + dir).clamp(0, albums.length - 1);
      _scrollAccumulator -= dir * notch;
    }
    _wake();
  }

  static String _fold(String s) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    final b = StringBuffer();
    for (final c in s.toLowerCase().split('')) {
      final k = from.indexOf(c);
      b.write(k >= 0 ? to[k] : c);
    }
    return b.toString().trim();
  }

  /// Meilleur album pour la recherche : début d'artiste ou de titre, puis
  /// début d'un mot, puis n'importe où.
  int? _find(String query) {
    final q = _fold(query);
    if (q.isEmpty) return null;
    int? best;
    var bestScore = 0;
    for (var i = 0; i < albums.length; i++) {
      var score = 0;
      for (final field in [albums[i].artist, albums[i].title]) {
        final f = _fold(field);
        if (f.startsWith(q)) {
          score = math.max(score, 3);
        } else if (f.contains(' $q')) {
          score = math.max(score, 2);
        } else if (f.contains(q)) {
          score = math.max(score, 1);
        }
      }
      if (score > bestScore) {
        best = i;
        bestScore = score;
      }
    }
    return best;
  }

  void _onSearch(String query) {
    final hit = _find(query);
    setState(() {
      _noMatch = query.trim().isNotEmpty && hit == null;
      _searchHit = hit;
      if (hit != null) {
        _lastShown = albums[hit];
        _flipTarget = hit;
        _lifts.putIfAbsent(hit, () => Spring(0, stiffness: 260, damping: 0.72));
      }
    });
    _wake();
  }

  void _pickSearchHit() {
    final hit = _searchHit;
    _searchFocus.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    if (hit != null) widget.onPick(hit, _slot(hit).rect);
  }

  void _cancelSearch() {
    _search.clear();
    _onSearch('');
    _searchFocus.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
  }

  void _onTapUp(TapUpDetails d) {
    final h = _hitTest(d.localPosition);
    if (h != null) widget.onPick(h, _slot(h).rect);
  }

  // --- Construction ---------------------------------------------------------

  Widget _sleeve(int i) => _sleeves.putIfAbsent(
        i,
        () => RepaintBoundary(child: _Sleeve(album: albums[i], cover: player.albumCovers[i])),
      );

  List<Widget> _records() {
    if (albums.isEmpty) return const [];
    final (first, last) = _visibleRange;
    return [
      // Du fond vers l'avant : chaque disque cache le bas du précédent.
      for (var i = last; i >= first; i--)
        if (_slot(i) case final s)
          Positioned.fromRect(
            rect: s.rect,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0009)
                ..rotateX(-s.tilt)
                ..rotateZ(_jitter(i).rot),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45 + 0.15 * s.lift),
                      blurRadius: 10 + 26 * s.lift,
                      offset: Offset(0, -2 + 14 * s.lift),
                    ),
                  ],
                ),
                position: DecorationPosition.background,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.black.withValues(alpha: s.shade.clamp(0.0, 1.0)),
                  ),
                  child: _sleeve(i),
                ),
              ),
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final shownIndex = _hovered ?? _searchHit;
    final hovered = shownIndex != null && shownIndex < albums.length ? albums[shownIndex] : null;
    return Listener(
      onPointerSignal: _onScroll,
      child: MouseRegion(
        cursor: hovered != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onHover: (e) {
          _mouse = e.localPosition;
          _updateHover();
        },
        onExit: (_) {
          _mouse = null;
          _updateHover();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onTapUp,
          child: SizedBox(
            width: C.width,
            height: C.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _CrateBackPainter()))),
                Positioned.fill(
                  child: ValueListenableBuilder(
                    valueListenable: _frame,
                    builder: (_, _, _) => Stack(clipBehavior: Clip.none, children: _records()),
                  ),
                ),
                const Positioned.fill(
                  child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _CrateFrontPainter()))),
                ),
                Positioned(
                  left: C.note.dx,
                  top: C.note.dy,
                  child: SearchNote(
                    controller: _search,
                    focusNode: _searchFocus,
                    onChanged: _onSearch,
                    onSubmitted: _pickSearchHit,
                    onCancel: _cancelSearch,
                    noMatch: _noMatch,
                  ),
                ),
                Positioned(
                  left: C.front.left + 40,
                  width: C.front.width - 80,
                  top: C.front.top - 105,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: hovered != null ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: _AlbumPill(album: hovered ?? _lastShown),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _AlbumPill extends StatelessWidget {
  const _AlbumPill({required this.album});

  final Album? album;

  @override
  Widget build(BuildContext context) {
    final a = album;
    if (a == null) return const SizedBox.shrink();
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
            color: const Color(0xFF1A120A).withValues(alpha: 0.72),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${a.artist} · ${a.trackCount} titre${a.trackCount > 1 ? 's' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 18)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une pochette : la jaquette de l'album, ou une pochette unie générée.
class _Sleeve extends StatelessWidget {
  const _Sleeve({required this.album, required this.cover});

  final Album album;
  final Uint8List? cover;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null)
            Image.memory(
              cover!,
              fit: BoxFit.cover,
              cacheWidth: 400,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => CustomPaint(painter: _PlainSleevePainter(album)),
            )
          else
            CustomPaint(painter: _PlainSleevePainter(album)),
          const CustomPaint(painter: _SleeveFinishPainter()),
        ],
      ),
    );
  }
}

/// Carton usé : reflet, usure circulaire du disque, tranches claires.
class _SleeveFinishPainter extends CustomPainter {
  const _SleeveFinishPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          r.topLeft,
          r.bottomRight,
          [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: 0.12)],
          const [0, 0.45, 1],
        ),
    );
    canvas.drawCircle(
      r.center,
      size.width * 0.46,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.02
        ..color = Colors.white.withValues(alpha: 0.05),
    );
    canvas.drawRect(
      r.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.14),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PlainSleevePainter extends CustomPainter {
  _PlainSleevePainter(this.album);

  final Album album;

  @override
  void paint(Canvas canvas, Size size) {
    final hue = (album.title.hashCode % 360).abs().toDouble();
    final base = HSLColor.fromAHSL(1, hue, 0.35, 0.32).toColor();
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = base);
    canvas.drawCircle(
      r.center,
      size.width * 0.3,
      Paint()..color = HSLColor.fromAHSL(1, (hue + 30) % 360, 0.45, 0.5).toColor(),
    );
    void line(String text, double y, double fontSize, FontWeight w) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: const Color(0xFFF5EEE2), fontSize: fontSize, fontWeight: w, letterSpacing: 1.5),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: size.width * 0.84);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, y));
    }

    line(album.artist.toUpperCase(), size.height * 0.07, size.width * 0.055, FontWeight.w700);
    line(album.title, size.height * 0.8, size.width * 0.06, FontWeight.w500);
  }

  @override
  bool shouldRepaint(covariant _PlainSleevePainter old) => old.album != album;
}

// --- Bois ---------------------------------------------------------------------

/// Planche de pin, avec veinage pseudo-aléatoire. [shade] l'assombrit.
void _plank(Canvas canvas, Rect rect, int seed, {double shade = 0, Path? clip, double radius = 6}) {
  canvas.save();
  if (clip != null) {
    canvas.clipPath(clip);
  } else {
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  }
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        const [Color(0xFFD7AE78), Color(0xFFC39258), Color(0xFFB07E47)],
        const [0, 0.55, 1],
      ),
  );
  final rnd = math.Random(seed);
  final grain = Paint()..style = PaintingStyle.stroke;
  for (var k = 0; k < 34; k++) {
    final y = rect.top + rnd.nextDouble() * rect.height;
    final amp = 0.8 + rnd.nextDouble() * 3.5;
    final freq = 0.003 + rnd.nextDouble() * 0.012;
    final phase = rnd.nextDouble() * 6;
    final path = Path()..moveTo(rect.left, y);
    for (var x = rect.left; x <= rect.right + 12; x += 12) {
      path.lineTo(x, y + amp * math.sin(x * freq + phase));
    }
    grain
      ..color = const Color(0xFF6B4320).withValues(alpha: 0.06 + rnd.nextDouble() * 0.16)
      ..strokeWidth = 0.6 + rnd.nextDouble() * 1.8;
    canvas.drawPath(path, grain);
  }
  // Un nœud de temps en temps.
  if (rnd.nextDouble() < 0.7) {
    final c = Offset(rect.left + rect.width * (0.15 + rnd.nextDouble() * 0.7), rect.top + rect.height * (0.3 + rnd.nextDouble() * 0.4));
    for (var k = 0; k < 4; k++) {
      canvas.drawOval(
        Rect.fromCenter(center: c, width: 34.0 - k * 7, height: 13.0 - k * 2.6),
        Paint()
          ..style = k == 3 ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF6B4320).withValues(alpha: 0.22 + k * 0.08),
      );
    }
  }
  if (shade > 0) canvas.drawRect(rect, Paint()..color = Colors.black.withValues(alpha: shade));
  canvas.restore();
}

/// Fond du bac : ombre au sol, paroi arrière, parois latérales.
class _CrateBackPainter extends CustomPainter {
  const _CrateBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(C.front.left + 10, C.front.bottom - 30, C.front.right - 10, C.front.bottom + 22), const Radius.circular(30)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );

    _plank(canvas, C.back, 3, shade: 0.5, radius: 3);

    // Faces intérieures des côtés, en perspective.
    const inset = 18.0;
    final left = Path()
      ..moveTo(C.back.left, C.back.top)
      ..lineTo(C.back.left, C.back.bottom)
      ..lineTo(C.front.left + inset, C.front.bottom)
      ..lineTo(C.front.left + inset, C.front.top)
      ..close();
    final right = Path()
      ..moveTo(C.back.right, C.back.top)
      ..lineTo(C.back.right, C.back.bottom)
      ..lineTo(C.front.right - inset, C.front.bottom)
      ..lineTo(C.front.right - inset, C.front.top)
      ..close();
    _plank(canvas, left.getBounds(), 5, shade: 0.38, clip: left);
    _plank(canvas, right.getBounds(), 7, shade: 0.3, clip: right);

    // Chant supérieur des côtés (épaisseur du bois).
    final leftEdge = Path()
      ..moveTo(C.front.left, C.front.top)
      ..lineTo(C.back.left - 10, C.back.top)
      ..lineTo(C.back.left, C.back.top)
      ..lineTo(C.front.left + inset, C.front.top)
      ..close();
    final rightEdge = Path()
      ..moveTo(C.front.right, C.front.top)
      ..lineTo(C.back.right + 10, C.back.top)
      ..lineTo(C.back.right, C.back.top)
      ..lineTo(C.front.right - inset, C.front.top)
      ..close();
    for (final edge in [leftEdge, rightEdge]) {
      _plank(canvas, edge.getBounds(), 11, clip: edge);
      canvas.drawPath(edge, Paint()..color = Colors.white.withValues(alpha: 0.12));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Paroi avant du bac, avec sa poignée et son marquage au pochoir.
class _CrateFrontPainter extends CustomPainter {
  const _CrateFrontPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const f = C.front;

    // Chant supérieur de la paroi, vu d'un peu au-dessus.
    final top = Path()
      ..moveTo(f.left + 6, f.top - 10)
      ..lineTo(f.right - 6, f.top - 10)
      ..lineTo(f.right, f.top + 2)
      ..lineTo(f.left, f.top + 2)
      ..close();
    _plank(canvas, top.getBounds(), 17, clip: top);
    canvas.drawPath(top, Paint()..color = Colors.white.withValues(alpha: 0.18));

    // Deux planches séparées par un jour sombre.
    final gapY = f.top + f.height * 0.5;
    canvas.drawRect(Rect.fromLTRB(f.left + 4, gapY - 8, f.right - 4, gapY + 8), Paint()..color = const Color(0xFF1B120A));
    final upper = Rect.fromLTRB(f.left, f.top, f.right, gapY - 3);
    final lower = Rect.fromLTRB(f.left, gapY + 3, f.right, f.bottom);
    _plank(canvas, upper, 23);
    _plank(canvas, lower, 29);
    for (final r in [upper, lower]) {
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [
            Colors.white.withValues(alpha: 0.25),
            Colors.black.withValues(alpha: 0.35),
          ]),
      );
    }

    // Poignée découpée dans la planche du haut.
    final handle = RRect.fromRectAndRadius(C.handle, Radius.circular(C.handle.height / 2));
    canvas.drawRRect(
      handle,
      Paint()
        ..shader = ui.Gradient.linear(C.handle.topCenter, C.handle.bottomCenter, const [Color(0xFF0E0905), Color(0xFF2A1C10)]),
    );
    canvas.drawRRect(
      handle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = ui.Gradient.linear(C.handle.topCenter, C.handle.bottomCenter, [
          Colors.black.withValues(alpha: 0.5),
          Colors.white.withValues(alpha: 0.3),
        ]),
    );

    // Vis aux extrémités des planches.
    for (final r in [upper, lower]) {
      for (final x in [r.left + 22, r.right - 22]) {
        for (final y in [r.top + r.height * 0.3, r.bottom - r.height * 0.3]) {
          final c = Offset(x, y);
          canvas.drawCircle(c, 6.5, Paint()..color = const Color(0xFF4A3B2C));
          canvas.drawCircle(
            c,
            5,
            Paint()..shader = ui.Gradient.linear(c - const Offset(5, 5), c + const Offset(5, 5), const [Color(0xFFD9D9D4), Color(0xFF6E6C66)]),
          );
          canvas.drawLine(c - const Offset(3.5, 1.5), c + const Offset(3.5, 1.5), Paint()
            ..strokeWidth = 1.4
            ..color = const Color(0xFF3A3630));
        }
      }
    }

    // Marquage au pochoir, un peu effacé.
    final tp = TextPainter(
      text: const TextSpan(
        text: 'DISQUES',
        style: TextStyle(fontSize: 54, fontWeight: FontWeight.w900, letterSpacing: 18, color: Color(0x553A2410)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(f.center.dx - tp.width / 2 + 9, lower.center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
