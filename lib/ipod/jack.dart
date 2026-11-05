import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Dimensions de la prise d'écouteurs, en unités de dessin des appareils
/// (≈ 6,67 unités par mm).
class JackGeometry {
  /// Corps en plastique blanc (≈ 4,5 × 10 mm) puis manchon qui s'affine.
  static const double bodyWidth = 30;
  static const double bodyLength = 64;
  static const double reliefLength = 40;
  static const double cableWidth = 11;

  /// Pointe métallique de 3,5 mm, cachée dans l'appareil quand c'est branché.
  static const double tipWidth = 23;
  static const double tipLength = 92;

  /// Hauteur à laquelle la prise est « partie » (hors de la fenêtre).
  static const double away = 1800;
}

/// Le câble qui sort de la fenêtre (par le haut, ou par le bas si la prise
/// est sous l'appareil) et la prise plantée dans sa tranche. Tout est en
/// coordonnées de la scène.
class JackPainter extends CustomPainter {
  const JackPainter({
    required this.socket,
    required this.scale,
    required this.lift,
    required this.anchorX,
    required this.sway,
    this.fromBelow = false,
  });

  /// Entrée de la prise sur la tranche de l'appareil, ou null (rien à dessiner).
  final Offset? socket;

  /// Pixels par unité de l'appareil (il est agrandi pour remplir la fenêtre).
  final double scale;

  /// Distance dont la prise est sortie, en unités (0 = enfoncée).
  final double lift;

  /// Abscisse où le câble sort de la fenêtre.
  final double anchorX;

  /// Ballant du câble, en pixels (il ondule quand l'appareil bouge).
  final double sway;

  /// Prise sur la tranche du bas : câble qui part vers le bas de la fenêtre.
  final bool fromBelow;

  @override
  void paint(Canvas canvas, Size size) {
    final socket = this.socket;
    if (socket == null) return;
    canvas.save();
    // Prise par en dessous : on dessine la même chose, retournée.
    if (fromBelow) {
      canvas
        ..translate(0, 2 * socket.dy)
        ..scale(1, -1);
    }
    final exitY = fromBelow ? 2 * socket.dy - (size.height + 40) : -40.0;
    _paintUpward(canvas, size, socket, exitY);
    canvas.restore();
  }

  void _paintUpward(Canvas canvas, Size size, Offset socket, double exitY) {
    final s = scale;
    final base = socket.translate(0, -lift * s); // bas du corps de la prise
    final bodyTop = base.dy - JackGeometry.bodyLength * s;
    final reliefTop = bodyTop - JackGeometry.reliefLength * s;

    // --- Câble : du manchon jusqu'au bord de la fenêtre, avec du ballant.
    final from = Offset(base.dx, reliefTop + 2 * s);
    final to = Offset(anchorX, exitY);
    final h = (from.dy - to.dy).abs();
    final cable = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(from.dx + sway, from.dy - h * 0.35, to.dx + sway * 0.4, to.dy + h * 0.45, to.dx, to.dy);
    final w = JackGeometry.cableWidth * s;
    canvas.drawPath(
      cable.shift(Offset(w * 0.25, w * 0.3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.5),
    );
    canvas.drawPath(
      cable,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFC9CBCD),
    );
    canvas.drawPath(
      cable.shift(Offset(-w * 0.14, 0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.55
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFF7F7F6),
    );

    // --- Pointe chromée, visible seulement hors de l'appareil.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, -1e5, size.width, socket.dy));
    final tw = JackGeometry.tipWidth * s;
    final tip = RRect.fromRectAndCorners(
      Rect.fromLTWH(base.dx - tw / 2, base.dy, tw, JackGeometry.tipLength * s),
      bottomLeft: Radius.circular(tw / 2),
      bottomRight: Radius.circular(tw / 2),
    );
    canvas.drawRRect(tip, Paint()..shader = _chrome(tip.outerRect));
    // Bagues isolantes noires de la prise stéréo.
    for (final k in [0.42, 0.68]) {
      canvas.drawRect(
        Rect.fromLTWH(tip.left, base.dy + JackGeometry.tipLength * s * k, tw, 2.2 * s),
        Paint()..color = const Color(0xFF1C1D1F),
      );
    }
    canvas.restore();

    final bw = JackGeometry.bodyWidth * s;
    final cw = JackGeometry.cableWidth * s;

    // --- Manchon en caoutchouc blanc qui s'affine vers le câble.
    final relief = Path()
      ..moveTo(base.dx - bw * 0.36, bodyTop + 1)
      ..cubicTo(
        base.dx - bw * 0.36,
        bodyTop - JackGeometry.reliefLength * s * 0.45,
        base.dx - cw / 2,
        reliefTop + JackGeometry.reliefLength * s * 0.3,
        base.dx - cw / 2,
        reliefTop,
      )
      ..lineTo(base.dx + cw / 2, reliefTop)
      ..cubicTo(
        base.dx + cw / 2,
        reliefTop + JackGeometry.reliefLength * s * 0.3,
        base.dx + bw * 0.36,
        bodyTop - JackGeometry.reliefLength * s * 0.45,
        base.dx + bw * 0.36,
        bodyTop + 1,
      )
      ..close();
    final reliefBounds = Rect.fromLTRB(base.dx - bw * 0.36, reliefTop, base.dx + bw * 0.36, bodyTop);
    canvas.drawPath(
      relief,
      Paint()
        ..shader = ui.Gradient.linear(
          reliefBounds.centerLeft,
          reliefBounds.centerRight,
          const [Color(0xFFBFC1C3), Color(0xFFF4F4F3), Color(0xFFFFFFFF), Color(0xFFD5D6D7), Color(0xFFB2B4B6)],
          const [0, 0.25, 0.45, 0.8, 1],
        ),
    );

    // --- Tête en métal : cylindre chromé, deux bagues moletées, arêtes vives.
    final head = RRect.fromRectAndCorners(
      Rect.fromLTRB(base.dx - bw / 2, bodyTop, base.dx + bw / 2, base.dy),
      topLeft: Radius.circular(3 * s),
      topRight: Radius.circular(3 * s),
    );
    canvas.drawRRect(
      head.shift(Offset(2 * s, 3 * s)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1, 4 * s)),
    );
    canvas.drawRRect(head, Paint()..shader = _chrome(head.outerRect));
    final knurl = Paint()..strokeWidth = math.max(0.5, 0.8 * s);
    for (final (from, to) in [(0.18, 0.34), (0.62, 0.78)]) {
      final band = Rect.fromLTRB(
        head.left,
        base.dy - JackGeometry.bodyLength * s * to,
        head.right,
        base.dy - JackGeometry.bodyLength * s * from,
      );
      canvas.drawRect(band, Paint()..color = Colors.black.withValues(alpha: 0.12));
      // Fines stries verticales : le moletage qui accroche la lumière.
      for (var x = band.left + 1.5 * s; x < band.right - s; x += 2.6 * s) {
        knurl.color = Colors.black.withValues(alpha: 0.28);
        canvas.drawLine(Offset(x, band.top), Offset(x, band.bottom), knurl);
        knurl.color = Colors.white.withValues(alpha: 0.35);
        canvas.drawLine(Offset(x + 0.9 * s, band.top), Offset(x + 0.9 * s, band.bottom), knurl);
      }
      canvas.drawLine(
        band.topLeft,
        band.topRight,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..strokeWidth = math.max(0.5, 0.7 * s),
      );
    }
    // Chanfrein brillant à la base, là où la prise touche la tranche.
    canvas.drawRect(
      Rect.fromLTWH(head.left, base.dy - 2.5 * s, bw, 2.5 * s),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
  }

  /// Chrome poli : reflets francs, du sombre au clair puis au sombre.
  static Shader _chrome(Rect r) => ui.Gradient.linear(
    r.centerLeft,
    r.centerRight,
    const [
      Color(0xFF6D7277),
      Color(0xFFB9BEC3),
      Color(0xFFF8F9FA),
      Color(0xFF9DA2A7),
      Color(0xFFD7DADD),
      Color(0xFF62676C),
    ],
    const [0, 0.18, 0.38, 0.6, 0.8, 1],
  );

  @override
  bool shouldRepaint(covariant JackPainter old) => true;
}
