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

/// Le câble qui descend du haut de la fenêtre et la prise plantée dans la
/// tranche de l'appareil. Tout est en coordonnées de la scène.
class JackPainter extends CustomPainter {
  const JackPainter({
    required this.socket,
    required this.scale,
    required this.lift,
    required this.anchorX,
    required this.sway,
  });

  /// Entrée de la prise sur la tranche de l'appareil, ou null (rien à dessiner).
  final Offset? socket;

  /// Pixels par unité de l'appareil (il est agrandi pour remplir la fenêtre).
  final double scale;

  /// Hauteur dont la prise est sortie, en unités (0 = enfoncée).
  final double lift;

  /// Abscisse où le câble sort du haut de la fenêtre.
  final double anchorX;

  /// Ballant du câble, en pixels (il ondule quand l'appareil bouge).
  final double sway;

  @override
  void paint(Canvas canvas, Size size) {
    final socket = this.socket;
    if (socket == null) return;
    final s = scale;
    final base = socket.translate(0, -lift * s); // bas du corps de la prise
    final bodyTop = base.dy - JackGeometry.bodyLength * s;
    final reliefTop = bodyTop - JackGeometry.reliefLength * s;
    if (reliefTop > size.height + 50) return;

    // --- Câble : du manchon jusqu'au haut de la fenêtre, avec du ballant.
    final from = Offset(base.dx, reliefTop + 2 * s);
    final to = Offset(anchorX, -40);
    final h = (from.dy - to.dy).abs();
    final cable = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(
        from.dx + sway,
        from.dy - h * 0.35,
        to.dx + sway * 0.4,
        to.dy + h * 0.45,
        to.dx,
        to.dy,
      );
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

    // --- Pointe chromée, visible seulement au-dessus de la tranche.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, -1e5, size.width, socket.dy));
    final tw = JackGeometry.tipWidth * s;
    final tip = RRect.fromRectAndCorners(
      Rect.fromLTWH(base.dx - tw / 2, base.dy, tw, JackGeometry.tipLength * s),
      bottomLeft: Radius.circular(tw / 2),
      bottomRight: Radius.circular(tw / 2),
    );
    canvas.drawRRect(
      tip,
      Paint()
        ..shader = ui.Gradient.linear(
          tip.outerRect.centerLeft,
          tip.outerRect.centerRight,
          const [Color(0xFF7D8288), Color(0xFFF3F5F7), Color(0xFFB4B9BE), Color(0xFF6E7378)],
          const [0, 0.35, 0.7, 1],
        ),
    );
    // Bagues isolantes noires de la prise stéréo.
    for (final k in [0.42, 0.68]) {
      canvas.drawRect(
        Rect.fromLTWH(tip.left, base.dy + JackGeometry.tipLength * s * k, tw, 2.2 * s),
        Paint()..color = const Color(0xFF1C1D1F),
      );
    }
    canvas.restore();

    // --- Corps en plastique blanc et manchon qui s'affine vers le câble.
    final bw = JackGeometry.bodyWidth * s;
    final cw = JackGeometry.cableWidth * s;
    final body = Path()
      ..moveTo(base.dx - bw / 2, base.dy)
      ..lineTo(base.dx - bw / 2, bodyTop)
      ..cubicTo(base.dx - bw / 2, bodyTop - JackGeometry.reliefLength * s * 0.5, base.dx - cw / 2,
          reliefTop + JackGeometry.reliefLength * s * 0.3, base.dx - cw / 2, reliefTop)
      ..lineTo(base.dx + cw / 2, reliefTop)
      ..cubicTo(base.dx + cw / 2, reliefTop + JackGeometry.reliefLength * s * 0.3, base.dx + bw / 2,
          bodyTop - JackGeometry.reliefLength * s * 0.5, base.dx + bw / 2, bodyTop)
      ..lineTo(base.dx + bw / 2, base.dy)
      ..close();
    canvas.drawPath(
      body.shift(Offset(2 * s, 3 * s)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1, 4 * s)),
    );
    final bounds = Rect.fromLTRB(base.dx - bw / 2, reliefTop, base.dx + bw / 2, base.dy);
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          bounds.centerLeft,
          bounds.centerRight,
          const [Color(0xFFC4C6C8), Color(0xFFF2F2F1), Color(0xFFFFFFFF), Color(0xFFD9DADB), Color(0xFFB6B8BA)],
          const [0, 0.25, 0.45, 0.8, 1],
        ),
    );
    // Petit bourrelet à la base, là où la prise touche la tranche.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(base.dx - bw / 2, base.dy - 6 * s, bw, 6 * s),
        Radius.circular(2 * s),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(covariant JackPainter old) => true;
}
