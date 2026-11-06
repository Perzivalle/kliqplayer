import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Matière et proportions d'une molette. Les valeurs par défaut sont celles
/// du Classic blanc.
@immutable
class WheelStyle {
  const WheelStyle({
    required this.radius,
    required this.buttonRadius,
    this.iconScale = 1,
    this.labelSize = 17,
    this.labelSpacing = 1.2,
    this.label = const Color(0xFFADB1B6),
    this.recess = const Color(0xFFD4D6D9),
    this.ring = const [Color(0xFFF2F3F4), Color(0xFFE2E4E7), Color(0xFFD3D6DA)],
    this.edgeLight = 0.7,
    this.groove = const Color(0xFFC3C6CA),
    this.buttonUp = const [Color(0xFFFFFFFF), Color(0xFFEDEEF0)],
    this.buttonDown = const [Color(0xFFDDDFE2), Color(0xFFF0F1F2)],
    this.labels = true,
    this.sideClicks = true,
    this.innerRadius,
    this.labelInset,
    this.inner = const [Color(0xFFF7F8F9), Color(0xFFE6E8EB), Color(0xFFD9DCE0)],
    this.menuLabel = 'MENU',
    this.turns = true,
    this.shuffle = false,
  });

  /// Texte du haut de la molette (« menu » en minuscules sur la 1re génération).
  final String menuLabel;

  /// L'anneau intérieur ([innerRadius]) tourne sous le doigt (1re
  /// génération) ; sinon c'est une surface tactile fixe (2e génération).
  final bool turns;

  /// Anneau de commandes d'un shuffle : + et − en haut et en bas, ⏮ ⏭ sur
  /// les côtés, ⏯ sur le bouton central.
  final bool shuffle;

  final double radius;
  final double buttonRadius;

  /// Taille des pictogrammes ⏮ ⏭ ⏯ (1 = Classic).
  final double iconScale;
  final double labelSize;
  final double labelSpacing;
  final Color label;

  /// Creux de la façade autour de la molette.
  final Color recess;

  /// Dégradé de la molette, du centre vers le bord.
  final List<Color> ring;
  final double edgeLight;

  /// Rainure entre la molette et le bouton central.
  final Color groove;
  final List<Color> buttonUp;
  final List<Color> buttonDown;

  /// MENU ⏮ ⏭ ⏯ inscrits sur la molette (sinon, boutons à part).
  final bool labels;

  /// Les côtés de la molette sont cliquables (sinon seul le centre l'est).
  final bool sideClicks;

  /// Molette mécanique (1re génération) : un anneau intérieur de ce rayon
  /// tourne vraiment sous le doigt, entouré des quatre boutons fixes.
  final double? innerRadius;
  final List<Color> inner;

  /// Distance des inscriptions au centre, en fraction du rayon (par défaut
  /// celle du Classic ; plus loin sur une molette mécanique).
  final double? labelInset;
}

enum WheelZone { none, menu, next, playPause, previous, center }

/// La molette et son bouton central. [pressed] assombrit la zone appuyée.
class WheelPainter extends CustomPainter {
  const WheelPainter(this.style, this.pressed, {this.rotation = 0});

  final WheelStyle style;
  final WheelZone pressed;

  /// Angle de l'anneau mécanique (radians), s'il y en a un.
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final s = style;
    final r = s.radius;
    final b = s.buttonRadius;

    // Léger creux dans la façade autour de la molette.
    canvas.drawCircle(c, r + 1.5, Paint()..color = s.recess);
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = ui.Gradient.radial(c.translate(0, -r * 0.3), r * 1.3, s.ring, const [0, 0.6, 1]),
    );
    // Arête intérieure de la molette (ombre en haut, lumière en bas).
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = ui.Gradient.linear(c.translate(0, -r), c.translate(0, r), [
          Colors.black.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: s.edgeLight),
        ]),
    );

    // Zone appuyée.
    if (pressed != WheelZone.none && pressed != WheelZone.center) {
      final mid = switch (pressed) {
        WheelZone.menu => -math.pi / 2,
        WheelZone.next => 0.0,
        WheelZone.playPause => math.pi / 2,
        _ => math.pi,
      };
      final sector = Path()
        ..addArc(Rect.fromCircle(center: c, radius: r), mid - math.pi / 4, math.pi / 2)
        ..arcTo(Rect.fromCircle(center: c, radius: b + 4), mid + math.pi / 4, -math.pi / 2, false)
        ..close();
      canvas.drawPath(
        sector,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            r,
            [Colors.black.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.09)],
            const [0.35, 1],
          ),
      );
    }

    if (s.labels) s.shuffle ? _shuffleLabels(canvas, c) : _labels(canvas, c);
    final inner = s.innerRadius;
    if (inner != null) _mechanical(canvas, c, inner);

    // Bouton central, séparé de la molette par une fine rainure.
    canvas.drawCircle(c, b + 2.5 * s.iconScale, Paint()..color = s.groove);
    canvas.drawCircle(
      c.translate(0, 1.5),
      b + 1,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    final down = pressed == WheelZone.center;
    canvas.drawCircle(
      c,
      b,
      Paint()..shader = ui.Gradient.linear(c.translate(0, -b), c.translate(0, b), down ? s.buttonDown : s.buttonUp),
    );
    canvas.drawCircle(
      c,
      b - 0.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: down ? 0.3 : 0.9),
    );
    if (s.shuffle && s.labels) _playPause(canvas, c.translate(1.5 * s.iconScale, 0), Paint()..color = s.label);
  }

  /// + − ⏮ ⏭ autour de l'anneau d'un shuffle.
  void _shuffleLabels(Canvas canvas, Offset c) {
    final s = style;
    final at = s.labelInset == null ? s.radius * 0.8 : s.radius * s.labelInset!;
    final k = s.iconScale;
    final ink = Paint()..color = s.label;
    final arm = 8.0 * k, t = 2.6 * k;
    final top = c.translate(0, -at), bottom = c.translate(0, at);
    canvas.drawRect(Rect.fromCenter(center: top, width: arm * 2, height: t), ink);
    canvas.drawRect(Rect.fromCenter(center: top, width: t, height: arm * 2), ink);
    canvas.drawRect(Rect.fromCenter(center: bottom, width: arm * 2, height: t), ink);
    _skip(canvas, c.translate(at, 0), 1, ink);
    _skip(canvas, c.translate(-at, 0), -1, ink);
  }

  /// Anneau qui tourne : séparé des boutons par une rainure, et strié de
  /// fines marques pour qu'on le voie tourner.
  void _mechanical(Canvas canvas, Offset c, double r) {
    final s = style;
    canvas.drawCircle(c, r + 3, Paint()..color = s.groove);
    canvas.drawCircle(
      c,
      r + 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black.withValues(alpha: 0.12),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = ui.Gradient.radial(c.translate(0, -r * 0.35), r * 1.3, s.inner, const [0, 0.6, 1]),
    );
    // Surface tactile fixe (2e génération) : lisse, sans repères.
    if (!s.turns) return;
    final tick = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 48; i++) {
      final a = rotation + i * 2 * math.pi / 48;
      final dir = Offset(math.cos(a), math.sin(a));
      // Plus visibles là où la lumière rase (en haut à gauche).
      final light = 0.5 + 0.5 * math.cos(a + 2.3);
      tick.color = Colors.black.withValues(alpha: 0.04 + 0.07 * light);
      canvas.drawLine(c + dir * (r - 10), c + dir * (r - 3), tick);
    }
    // Creux pour le doigt, qui tourne avec l'anneau.
    final dimple = c + Offset(math.cos(rotation - math.pi / 2), math.sin(rotation - math.pi / 2)) * (r * 0.78);
    canvas.drawCircle(
      dimple,
      r * 0.09,
      Paint()
        ..shader = ui.Gradient.radial(dimple.translate(-r * 0.02, -r * 0.03), r * 0.1, [
          Colors.black.withValues(alpha: 0.16),
          Colors.black.withValues(alpha: 0.02),
        ]),
    );
  }

  /// MENU, ⏮, ⏭, ⏯ inscrits sur la molette.
  void _labels(Canvas canvas, Offset c) {
    final s = style;
    final r = s.radius;
    final tp = TextPainter(
      text: TextSpan(
        text: s.menuLabel,
        style: TextStyle(
          fontFamily: 'Noto Sans',
          fontSize: s.labelSize,
          fontWeight: FontWeight.w700,
          color: s.label,
          letterSpacing: s.labelSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final menuAt = s.labelInset == null ? r * 0.78 : r * s.labelInset!;
    final iconAt = s.labelInset == null ? r * 0.76 : r * s.labelInset!;
    tp.paint(canvas, c.translate(-tp.width / 2, -menuAt - tp.height / 2 + 4 * s.iconScale));
    final ink = Paint()..color = s.label;
    _skip(canvas, c.translate(iconAt, 0), 1, ink);
    _skip(canvas, c.translate(-iconAt, 0), -1, ink);
    _playPause(canvas, c.translate(0, iconAt), ink);
  }

  /// ⏭ (dir = 1) ou ⏮ (dir = -1).
  void _skip(Canvas canvas, Offset c, double dir, Paint ink) {
    final h = 9.0 * style.iconScale;
    final w = 9.0 * style.iconScale;
    for (final dx in [-w, 0.0]) {
      final x0 = c.dx + dx * dir;
      canvas.drawPath(
        Path()
          ..moveTo(x0, c.dy - h)
          ..lineTo(x0 + w * dir, c.dy)
          ..lineTo(x0, c.dy + h)
          ..close(),
        ink,
      );
    }
    final bar = c.dx + w * dir;
    final t = 2.6 * style.iconScale;
    canvas.drawRect(Rect.fromLTRB(math.min(bar, bar + t * dir), c.dy - h, math.max(bar, bar + t * dir), c.dy + h), ink);
  }

  void _playPause(Canvas canvas, Offset c, Paint ink) {
    final k = style.iconScale;
    final h = 8.0 * k;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 12 * k, c.dy - h)
        ..lineTo(c.dx + 1 * k, c.dy)
        ..lineTo(c.dx - 12 * k, c.dy + h)
        ..close(),
      ink,
    );
    canvas.drawRect(Rect.fromLTWH(c.dx + 4 * k, c.dy - h, 3 * k, h * 2), ink);
    canvas.drawRect(Rect.fromLTWH(c.dx + 10 * k, c.dy - h, 3 * k, h * 2), ink);
  }

  @override
  bool shouldRepaint(covariant WheelPainter old) =>
      old.pressed != pressed || old.style != style || old.rotation != rotation;
}

/// Molette tactile : on la fait tourner en glissant en cercle (ou à la
/// molette de la souris), on clique sur ses quatre côtés ou au centre.
class IpodWheel extends StatefulWidget {
  const IpodWheel({
    super.key,
    required this.style,
    required this.onScroll,
    required this.onDown,
    required this.onUp,
    required this.onCancel,
  });

  final WheelStyle style;
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

  /// Angle de l'anneau mécanique : il suit le doigt (et la molette de la souris).
  double _rotation = 0;

  /// Au-delà de ce déplacement, un appui devient une rotation et s'annule.
  /// (Un clic au pavé tactile bouge souvent de quelques pixels.)
  static const _clickTolerance = 8.0;

  void _cancelPress() {
    if (_pressed == WheelZone.none) return;
    setState(() => _pressed = WheelZone.none);
    widget.onCancel();
  }

  double _accum = 0;

  WheelStyle get _s => widget.style;
  Offset get _c => Offset(_s.radius, _s.radius);

  WheelZone _zoneAt(Offset p) {
    final v = p - _c;
    final d = v.distance;
    if (d > _s.radius) return WheelZone.none;
    if (d <= _s.buttonRadius) return WheelZone.center;
    if (!_s.sideClicks) return WheelZone.none;
    // Molette mécanique : seuls les boutons fixes, autour de l'anneau, cliquent.
    final inner = _s.innerRadius;
    if (inner != null && d <= inner + 3) return WheelZone.none;
    final a = math.atan2(v.dy, v.dx);
    if (a.abs() <= math.pi / 4) return WheelZone.next;
    if (a.abs() >= 3 * math.pi / 4) return WheelZone.previous;
    return a < 0 ? WheelZone.menu : WheelZone.playPause;
  }

  void _panStart(DragStartDetails d) {
    final v = d.localPosition - _c;
    _lastAngle = v.distance > _s.buttonRadius * 0.6 ? math.atan2(v.dy, v.dx) : null;
    _accum = 0;
  }

  void _panUpdate(DragUpdateDetails d) {
    final v = d.localPosition - _c;
    if (v.distance < _s.buttonRadius * 0.6) return; // trop près du centre : angle instable
    final a = math.atan2(v.dy, v.dx);
    final last = _lastAngle;
    _lastAngle = a;
    if (last == null) return;
    var delta = a - last;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    if (_s.innerRadius != null && _s.turns) setState(() => _rotation += delta);
    // L'anneau d'un shuffle ne se tourne pas : seulement des boutons.
    if (_s.shuffle) return;
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
          final dir = e.scrollDelta.dy > 0 ? 1 : -1;
          if (_s.innerRadius != null && _s.turns) setState(() => _rotation += dir * _step);
          widget.onScroll(dir);
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
        child: CustomPaint(painter: WheelPainter(_s, _pressed, rotation: _rotation)),
      ),
    );
  }
}
