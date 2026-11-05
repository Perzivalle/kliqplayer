import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'geometry.dart';

typedef G = IpodGeometry;

/// Boîtier : ombre portée (il flotte), liseré chromé, façade blanche laquée
/// et cadre sombre de l'écran.
class BodyPainter extends CustomPainter {
  const BodyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(G.radius));

    // Ombres : une large et diffuse, une plus serrée sous l'appareil.
    canvas.drawRRect(
      outer.shift(const Offset(0, 26)).deflate(10),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.drawRRect(
      outer.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Liseré chromé : reflets verticaux comme un métal poli.
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, 0),
          const [Color(0xFF8C9095), Color(0xFFF7F8F9), Color(0xFFB4B8BC), Color(0xFFE8EAEC), Color(0xFF85898E)],
          const [0, 0.18, 0.5, 0.82, 1],
        ),
    );

    // Façade blanche.
    final front = outer.deflate(G.rim);
    canvas.drawRRect(
      front,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          const [Color(0xFFFFFFFF), Color(0xFFF6F6F4), Color(0xFFECECEA)],
          const [0, 0.55, 1],
        ),
    );
    // Arrondi de la façade : léger assombrissement au ras du chrome.
    canvas.drawRRect(
      front.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: 0.07),
    );

    // Cadre de l'écran.
    final frame = RRect.fromRectAndRadius(G.screenFrame, const Radius.circular(6));
    canvas.drawRRect(frame.inflate(1), Paint()..color = const Color(0xFFD5D6D8));
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF1E1F21));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Reflet de la plaque d'acrylique qui couvre toute la façade.
class GlassPainter extends CustomPainter {
  const GlassPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final front = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(G.radius)).deflate(G.rim);
    canvas.save();
    canvas.clipRRect(front);
    // Bande de lumière en diagonale sur le haut.
    final band = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.78, 0)
      ..lineTo(0, size.height * 0.36)
      ..close();
    canvas.drawPath(
      band,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width * 0.4, size.height * 0.24),
          [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0)],
          const [0, 0.7, 1],
        ),
    );
    // L'écran sous l'acrylique : très léger voile.
    canvas.drawRect(
      G.screen,
      Paint()
        ..shader = ui.Gradient.linear(
          G.screen.topLeft,
          G.screen.bottomLeft,
          [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.0)],
          const [0, 0.5],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

enum WheelZone { none, menu, next, playPause, previous, center }

/// La molette et son bouton central. [pressed] assombrit la zone appuyée.
class WheelPainter extends CustomPainter {
  const WheelPainter(this.pressed);

  final WheelZone pressed;

  static const _label = Color(0xFFADB1B6);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = G.wheelRadius;
    const b = G.buttonRadius;

    // Léger creux dans la façade autour de la molette.
    canvas.drawCircle(c, r + 1.5, Paint()..color = const Color(0xFFD4D6D9));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c.translate(0, -r * 0.3),
          r * 1.3,
          const [Color(0xFFF2F3F4), Color(0xFFE2E4E7), Color(0xFFD3D6DA)],
          const [0, 0.6, 1],
        ),
    );
    // Arête intérieure de la molette (ombre en haut, lumière en bas).
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = ui.Gradient.linear(
          c.translate(0, -r),
          c.translate(0, r),
          [Colors.black.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.7)],
        ),
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

    // Inscriptions.
    final tp = TextPainter(
      text: const TextSpan(
        text: 'MENU',
        style: TextStyle(fontFamily: 'Noto Sans', fontSize: 17, fontWeight: FontWeight.w700, color: _label, letterSpacing: 1.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c.translate(-tp.width / 2, -r * 0.78 - tp.height / 2 + 4));
    final ink = Paint()..color = _label;
    _skip(canvas, c.translate(r * 0.76, 0), 1, ink);
    _skip(canvas, c.translate(-r * 0.76, 0), -1, ink);
    _playPause(canvas, c.translate(0, r * 0.76), ink);

    // Bouton central, séparé de la molette par une fine rainure.
    canvas.drawCircle(c, b + 2.5, Paint()..color = const Color(0xFFC3C6CA));
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
      Paint()
        ..shader = ui.Gradient.linear(
          c.translate(0, -b),
          c.translate(0, b),
          down
              ? const [Color(0xFFDDDFE2), Color(0xFFF0F1F2)]
              : const [Color(0xFFFFFFFF), Color(0xFFEDEEF0)],
        ),
    );
    canvas.drawCircle(
      c,
      b - 0.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: down ? 0.3 : 0.9),
    );
  }

  /// ⏭ (dir = 1) ou ⏮ (dir = -1).
  void _skip(Canvas canvas, Offset c, double dir, Paint ink) {
    const h = 9.0;
    const w = 9.0;
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
    canvas.drawRect(Rect.fromLTRB(math.min(bar, bar + 2.6 * dir), c.dy - h, math.max(bar, bar + 2.6 * dir), c.dy + h), ink);
  }

  void _playPause(Canvas canvas, Offset c, Paint ink) {
    const h = 8.0;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 12, c.dy - h)
        ..lineTo(c.dx + 1, c.dy)
        ..lineTo(c.dx - 12, c.dy + h)
        ..close(),
      ink,
    );
    canvas.drawRect(Rect.fromLTWH(c.dx + 4, c.dy - h, 3, h * 2), ink);
    canvas.drawRect(Rect.fromLTWH(c.dx + 10, c.dy - h, 3, h * 2), ink);
  }

  @override
  bool shouldRepaint(covariant WheelPainter old) => old.pressed != pressed;
}
