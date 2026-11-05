import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Dimensions de la prise, en unités de dessin des appareils (≈ 6,67 unités
/// par mm). Façon câble d'instrument : fût nickelé, collerette striée, bague
/// moletée, gaine thermorétractable colorée, câble noir imprimé.
class JackGeometry {
  /// Fût métallique (≈ 4,5 × 12 mm) et collerette côté pointe.
  static const double bodyWidth = 30;
  static const double bodyLength = 80;
  static const double collarWidth = 33;
  static const double collarHeight = 5;

  /// Gaine thermorétractable qui s'affine du fût jusqu'au câble.
  static const double sleeveLength = 52;
  static const double cableWidth = 11;

  /// Pointe de 3,5 mm, cachée dans l'appareil quand c'est branché.
  static const double tipWidth = 23;
  static const double tipLength = 92;

  /// Distance à laquelle la prise est « partie » (hors de la fenêtre).
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

  // Nickel : un peu plus chaud et plus doux que le chrome.
  static const _nickel = [
    Color(0xFF7E7D78),
    Color(0xFFBDBCB6),
    Color(0xFFF6F5F1),
    Color(0xFFFFFFFF),
    Color(0xFFA9A8A2),
    Color(0xFFD9D8D2),
    Color(0xFF6F6E69),
  ];
  static const _nickelStops = [0.0, 0.16, 0.32, 0.4, 0.62, 0.82, 1.0];

  static const _sleeve = [
    Color(0xFF1B6F87),
    Color(0xFF2E9DBD),
    Color(0xFF7FD0E6),
    Color(0xFF3AA9C8),
    Color(0xFF175F74),
  ];
  static const _sleeveStops = [0.0, 0.25, 0.42, 0.62, 1.0];

  static Shader _metal(Rect r) => ui.Gradient.linear(r.centerLeft, r.centerRight, _nickel, _nickelStops);

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
    final base = socket.translate(0, -lift * s); // bas du fût (côté pointe)
    final bodyTop = base.dy - JackGeometry.bodyLength * s;
    final sleeveTop = bodyTop - JackGeometry.sleeveLength * s;
    final x = base.dx;

    _cable(canvas, Offset(x, sleeveTop + 3 * s), Offset(anchorX, exitY));
    _tip(canvas, size, socket, base);
    _sleeveShape(canvas, x, bodyTop, sleeveTop);
    _barrel(canvas, x, base.dy, bodyTop);
  }

  // --- Câble noir, avec son inscription imprimée qui suit la courbe ------------

  void _cable(Canvas canvas, Offset from, Offset to) {
    final s = scale;
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
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.5),
    );
    canvas.drawPath(
      cable,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF17181A),
    );
    // Reflet mat du caoutchouc.
    canvas.drawPath(
      cable.shift(Offset(-w * 0.18, 0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.3
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF3A3C40).withValues(alpha: 0.7),
    );
    _printing(canvas, cable, w);
  }

  /// « AUDIO CABLE » imprimé en blanc le long du câble, lettre par lettre.
  void _printing(Canvas canvas, Path cable, double w) {
    const text = 'AUDIO CABLE';
    final fontSize = w * 0.55;
    if (fontSize < 3) return;
    final style = TextStyle(
      fontFamily: 'Noto Sans',
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: Colors.white.withValues(alpha: 0.72),
    );
    final glyphs = [
      for (final ch in text.split(''))
        TextPainter(
          text: TextSpan(text: ch, style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    final spacing = fontSize * 0.28;
    final word = glyphs.fold(0.0, (sum, g) => sum + g.width + spacing);
    for (final metric in cable.computeMetrics()) {
      // Premier mot un peu après la gaine, puis un tous les 3,5 mots.
      for (var start = w * 3; start + word < metric.length; start += word * 3.5) {
        var d = start;
        for (final g in glyphs) {
          final t = metric.getTangentForOffset(d + g.width / 2);
          if (t == null) break;
          canvas.save();
          canvas.translate(t.position.dx, t.position.dy);
          // Lisible en remontant le câble.
          canvas.rotate(-t.angle);
          // Câble retourné (prise par en dessous) : on remet les lettres à l'endroit.
          if (fromBelow) canvas.scale(1, -1);
          g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
          canvas.restore();
          d += g.width + spacing;
        }
      }
    }
  }

  // --- Pointe : tige, bagues isolantes, col et bout arrondi ---------------------

  void _tip(Canvas canvas, Size size, Offset socket, Offset base) {
    final s = scale;
    canvas.save();
    // Seulement la partie sortie de l'appareil.
    canvas.clipRect(Rect.fromLTRB(0, -1e5, size.width, socket.dy));
    final tw = JackGeometry.tipWidth * s;
    final len = JackGeometry.tipLength * s;
    final x = base.dx;
    final y0 = base.dy;
    final neckY = y0 + len * 0.8;
    final shape = Path()
      ..moveTo(x - tw / 2, y0)
      ..lineTo(x - tw / 2, neckY - tw * 0.15)
      // Col resserré puis bulbe et petite pointe.
      ..quadraticBezierTo(x - tw * 0.32, neckY, x - tw * 0.42, neckY + tw * 0.28)
      ..quadraticBezierTo(x - tw * 0.48, y0 + len - tw * 0.2, x, y0 + len)
      ..quadraticBezierTo(x + tw * 0.48, y0 + len - tw * 0.2, x + tw * 0.42, neckY + tw * 0.28)
      ..quadraticBezierTo(x + tw * 0.32, neckY, x + tw / 2, neckY - tw * 0.15)
      ..lineTo(x + tw / 2, y0)
      ..close();
    canvas.drawPath(shape, Paint()..shader = _metal(Rect.fromLTWH(x - tw / 2, y0, tw, len)));
    // Bagues isolantes noires de la prise stéréo.
    for (final k in [0.4, 0.66]) {
      canvas.drawRect(Rect.fromLTWH(x - tw / 2, y0 + len * k, tw, 2.4 * s), Paint()..color = const Color(0xFF151618));
    }
    canvas.restore();
  }

  // --- Gaine thermorétractable bleu-vert ------------------------------------------

  void _sleeveShape(Canvas canvas, double x, double bodyTop, double sleeveTop) {
    final s = scale;
    final bw = JackGeometry.bodyWidth * s * 0.84;
    final cw = JackGeometry.cableWidth * s * 1.15;
    final len = bodyTop - sleeveTop;
    final sleeve = Path()
      ..moveTo(x - bw / 2, bodyTop + 2 * s)
      ..cubicTo(x - bw / 2, bodyTop - len * 0.45, x - cw / 2, sleeveTop + len * 0.4, x - cw / 2, sleeveTop)
      ..lineTo(x + cw / 2, sleeveTop)
      ..cubicTo(x + cw / 2, sleeveTop + len * 0.4, x + bw / 2, bodyTop - len * 0.45, x + bw / 2, bodyTop + 2 * s)
      ..close();
    final bounds = Rect.fromLTRB(x - bw / 2, sleeveTop, x + bw / 2, bodyTop);
    canvas.drawPath(
      sleeve,
      Paint()..shader = ui.Gradient.linear(bounds.centerLeft, bounds.centerRight, _sleeve, _sleeveStops),
    );
    // Plis légers et irréguliers du plastique rétracté.
    canvas.save();
    canvas.clipPath(sleeve);
    final fold = Paint()
      ..strokeWidth = math.max(0.6, 1.4 * s)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.4, 0.6 * s));
    for (final (k, tilt) in [(0.2, 2.5), (0.47, -1.5), (0.72, 3.5)]) {
      final y = bodyTop - len * k;
      fold.color = Colors.black.withValues(alpha: 0.09);
      canvas.drawLine(Offset(x - bw, y + tilt * s), Offset(x + bw, y - tilt * s), fold);
      fold.color = Colors.white.withValues(alpha: 0.12);
      canvas.drawLine(Offset(x - bw, y + (tilt + 1.4) * s), Offset(x + bw, y - (tilt - 1.4) * s), fold);
    }
    canvas.restore();
  }

  // --- Fût nickelé : collerette striée, corps lisse, bague moletée ---------------

  void _barrel(Canvas canvas, double x, double baseY, double bodyTop) {
    final s = scale;
    final bw = JackGeometry.bodyWidth * s;
    final barrel = Rect.fromLTRB(x - bw / 2, bodyTop, x + bw / 2, baseY - JackGeometry.collarHeight * s);
    canvas.drawRect(
      barrel.shift(Offset(2 * s, 3 * s)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1, 4 * s)),
    );
    canvas.drawRect(barrel, Paint()..shader = _metal(barrel));
    // Bord du fût côté gaine : léger épaulement.
    canvas.drawRect(
      Rect.fromLTWH(barrel.left, bodyTop, bw, 2 * s),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );

    // Bague moletée en croisillons, vers l'arrière du fût.
    final knurl = Rect.fromLTRB(
      barrel.left,
      bodyTop + barrel.height * 0.14,
      barrel.right,
      bodyTop + barrel.height * 0.36,
    );
    canvas.save();
    canvas.clipRect(knurl);
    canvas.drawRect(knurl, Paint()..color = Colors.black.withValues(alpha: 0.10));
    final step = math.max(1.6, 2.4 * s);
    final line = Paint()..strokeWidth = math.max(0.5, 0.7 * s);
    for (var d = -knurl.height; d < knurl.width + knurl.height; d += step) {
      line.color = Colors.black.withValues(alpha: 0.30);
      canvas.drawLine(Offset(knurl.left + d, knurl.top), Offset(knurl.left + d + knurl.height, knurl.bottom), line);
      canvas.drawLine(Offset(knurl.left + d + knurl.height, knurl.top), Offset(knurl.left + d, knurl.bottom), line);
      line.color = Colors.white.withValues(alpha: 0.25);
      canvas.drawLine(
        Offset(knurl.left + d + step / 2, knurl.top),
        Offset(knurl.left + d + step / 2 + knurl.height, knurl.bottom),
        line,
      );
    }
    canvas.restore();
    final edge = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = math.max(0.5, 0.8 * s);
    canvas.drawLine(knurl.topLeft, knurl.topRight, edge);
    canvas.drawLine(knurl.bottomLeft, knurl.bottomRight, edge);

    // Collerette côté pointe, un peu plus large, striée en biais.
    final cw = JackGeometry.collarWidth * s;
    final collar = RRect.fromRectAndRadius(
      Rect.fromLTRB(x - cw / 2, baseY - JackGeometry.collarHeight * s, x + cw / 2, baseY),
      Radius.circular(1.5 * s),
    );
    canvas.drawRRect(collar, Paint()..shader = _metal(collar.outerRect));
    canvas.save();
    canvas.clipRRect(collar);
    final hatch = Paint()
      ..strokeWidth = math.max(0.5, 0.6 * s)
      ..color = Colors.black.withValues(alpha: 0.28);
    for (var d = 0.0; d < cw + collar.height; d += math.max(1.4, 2 * s)) {
      canvas.drawLine(
        Offset(collar.left + d, collar.top),
        Offset(collar.left + d - collar.height, collar.bottom),
        hatch,
      );
    }
    canvas.restore();
    canvas.drawLine(
      collar.outerRect.topLeft,
      collar.outerRect.topRight,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = math.max(0.5, 0.7 * s),
    );
  }

  @override
  bool shouldRepaint(covariant JackPainter old) => true;
}
