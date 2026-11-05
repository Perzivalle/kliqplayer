import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'geometry.dart';

typedef G = TurntableGeometry;

const _alu = [Color(0xFFE8E9EB), Color(0xFFA8AAAE), Color(0xFFD6D8DB), Color(0xFF7A7C80)];
const _aluStops = [0.0, 0.35, 0.55, 1.0];

Paint _aluPaint(Rect r) => Paint()..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, _alu, _aluStops);

/// Dégradé « cylindre métallique » perpendiculaire au segment [a]→[b].
Paint _cylinder(Offset a, Offset b, double width, List<Color> colors, List<double> stops) {
  final dir = b - a;
  final n = Offset(-dir.dy, dir.dx) / dir.distance * (width / 2);
  return Paint()
    ..shader = ui.Gradient.linear(a + n, a - n, colors, stops)
    ..strokeWidth = width;
}

const _cylAlu = [Color(0xFF6E7074), Color(0xFFEEEFF1), Color(0xFFBEC0C4), Color(0xFF505256)];
const _cylStops = [0.0, 0.3, 0.55, 1.0];

void _text(Canvas canvas, String text, Offset at, {double size = 22, Color color = const Color(0xFFB9BAC0), bool center = true, double spacing = 3, FontWeight weight = FontWeight.w500}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: size, color: color, letterSpacing: spacing, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at - Offset(0, tp.height / 2));
}

/// Tout ce qui ne bouge jamais : socle, plateau, disque, sérigraphies.
class PlinthPainter extends CustomPainter {
  const PlinthPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(G.plinth, const Radius.circular(G.plinthRadius));

    // Ombre portée du socle.
    canvas.drawRRect(
      body.shift(const Offset(0, 12)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Socle noir satiné + liseré aluminium + biseau.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          G.plinth.topLeft,
          G.plinth.bottomCenter + const Offset(200, 0),
          const [Color(0xFF34353A), Color(0xFF1F2023), Color(0xFF151618)],
          const [0, 0.5, 1],
        ),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..shader = ui.Gradient.linear(G.plinth.topCenter, G.plinth.bottomCenter, _alu, _aluStops),
    );
    canvas.drawRRect(
      body.deflate(9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.05),
    );

    _platter(canvas);
    _record(canvas);
    _controls(canvas);
    _armBase(canvas);

    _text(canvas, 'LECTEUR', const Offset(78, 82), center: false, size: 24, spacing: 6, weight: FontWeight.w600);
    _text(canvas, 'DIRECT DRIVE', const Offset(78, 112), center: false, size: 14, spacing: 3, color: const Color(0xFF7D7E86));
  }

  void _platter(Canvas canvas) {
    const c = G.center;
    // Ombre du plateau sur le socle.
    canvas.drawCircle(
      c + const Offset(6, 12),
      G.platterR,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(c, G.platterR, _aluPaint(Rect.fromCircle(center: c, radius: G.platterR)));

    // Points stroboscopiques.
    final dot = Paint()..color = const Color(0xFF37383C);
    for (final (ring, count) in const [(0.988, 180), (0.972, 150)]) {
      final r = G.platterR * ring;
      for (var i = 0; i < count; i++) {
        canvas.drawCircle(c + Offset.fromDirection(2 * math.pi * i / count, r), 2.8, dot);
      }
    }

    // Tapis en caoutchouc.
    final mat = G.platterR * 0.955;
    canvas.drawCircle(c, mat, Paint()..color = const Color(0xFF18181A));
    final rib = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.04);
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(c, G.recordR + (mat - G.recordR) * (i + 0.5) / 6, rib);
    }
  }

  void _record(Canvas canvas) {
    const c = G.center;
    canvas.drawCircle(
      c + const Offset(3, 6),
      G.recordR,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(c, G.recordR, Paint()..color = const Color(0xFF0C0C0D));

    // Sillons, avec des plages lisses entre les morceaux.
    const inner = G.labelR + 12;
    const outer = G.recordR - 8;
    const gaps = [0.22, 0.41, 0.57, 0.71, 0.84];
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final rnd = math.Random(7);
    for (var r = inner; r < outer; r += 2.6) {
      final t = (r - inner) / (outer - inner);
      final inGap = gaps.any((g) => (t - g).abs() < 0.008);
      groove.color = Colors.white.withValues(alpha: inGap ? 0.015 : 0.035 + rnd.nextDouble() * 0.04);
      canvas.drawCircle(c, r, groove);
    }

    // Reflets fixes : la lumière vient d'en haut à gauche.
    for (final base in const [-3 * math.pi / 4, math.pi / 4]) {
      for (final (spread, alpha) in const [(0.34, 0.06), (0.13, 0.08), (0.045, 0.1)]) {
        final path = Path()
          ..moveTo(c.dx, c.dy)
          ..arcTo(Rect.fromCircle(center: c, radius: G.recordR), base - spread, 2 * spread, false)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.radial(
              c,
              G.recordR,
              [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: alpha), Colors.white.withValues(alpha: alpha / 2)],
              const [0, 0.35, 0.75, 1],
            ),
        );
      }
    }

    canvas.drawCircle(
      c,
      G.recordR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF46464A),
    );
  }

  void _controls(Canvas canvas) {
    // Variateur de vitesse : fente et graduations.
    const px = G.pitchX;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(px - 6, G.pitchTop, px + 6, G.pitchBottom), const Radius.circular(6)),
      Paint()..color = const Color(0xFF050506),
    );
    final tick = Paint()
      ..color = const Color(0x78C8C8CD)
      ..strokeWidth = 1.8;
    for (var i = 0; i <= 10; i++) {
      final y = G.pitchTop + (G.pitchBottom - G.pitchTop) * i / 10;
      final len = i % 5 == 0 ? 22.0 : 12.0;
      canvas.drawLine(Offset(px - 16 - len, y), Offset(px - 16, y), tick);
    }
    _text(canvas, 'PITCH', const Offset(px, G.pitchTop - 40));
    _text(canvas, '+', const Offset(px + 26, G.pitchBottom - 6), size: 18);
    _text(canvas, '−', const Offset(px + 26, G.pitchTop + 6), size: 18);

    // Graduations du volume.
    for (var i = 0; i <= 10; i++) {
      final a = 3 * math.pi / 4 + 1.5 * math.pi * i / 10;
      canvas.drawCircle(G.knob + Offset.fromDirection(a, G.knobR * 1.32), 3.5, Paint()..color = const Color(0x96C8C8CD));
    }
    _text(canvas, 'VOLUME', G.knob - const Offset(0, G.knobR * 1.32 + 34));

    // Sérigraphies des boutons de vitesse.
    _text(canvas, '33', G.speed33.topCenter - const Offset(0, 24));
    _text(canvas, '45', G.speed45.topCenter - const Offset(0, 24));

    // Socle de la lampe stroboscopique.
    canvas.drawCircle(G.lamp, G.lampR * 1.4, _aluPaint(Rect.fromCircle(center: G.lamp, radius: G.lampR * 1.4)));
  }

  void _armBase(Canvas canvas) {
    const p = G.pivot;
    canvas.drawCircle(
      p + const Offset(4, 8),
      85,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(p, 85, Paint()..color = const Color(0xFF1D1E21));
    canvas.drawCircle(
      p,
      85,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..shader = ui.Gradient.linear(p - const Offset(0, 85), p + const Offset(0, 85), _alu, _aluStops),
    );
    canvas.drawCircle(
      p,
      60,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.07),
    );

    // Anti-skating (décoratif).
    final anti = p + const Offset(70, 75);
    canvas.drawCircle(anti, 18, _aluPaint(Rect.fromCircle(center: anti, radius: 18)));

    // Repose-bras.
    final rest = p + Offset.fromDirection(G.armRest, G.armLength * 0.62);
    canvas.drawCircle(
      rest + const Offset(3, 6),
      18,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(rest, 18, _aluPaint(Rect.fromCircle(center: rest, radius: 18)));
    canvas.drawCircle(rest, 8, Paint()..color = const Color(0xFF19191B));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bras de lecture, dessiné pointant vers la droite (+x) depuis le pivot
/// placé au centre du canevas ; la rotation est appliquée par un Transform.
class ArmPainter extends CustomPainter {
  const ArmPainter({this.shadow = false});

  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final l = G.armLength;
    const hl = G.headLength;
    final hdir = Offset.fromDirection(G.headOffset);
    final hperp = Offset(-hdir.dy, hdir.dx);
    final stylus = Offset(l, 0);
    final joint = stylus - hdir * (hl * 0.75);
    final headEnd = stylus + hdir * (hl * 0.25);
    final h0 = joint + hdir * 12;

    final Paint Function(Offset a, Offset b, double w, List<Color> c, List<double> s) cyl;
    if (shadow) {
      final p = Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      cyl = (a, b, w, c, s) => p..strokeWidth = w;
    } else {
      cyl = _cylinder;
    }
    Paint solid(Color c) => shadow ? cyl(Offset.zero, const Offset(1, 0), 1, const [], const []) : (Paint()..color = c);

    // Contrepoids moleté, derrière le pivot.
    const w0 = Offset(-50, 0);
    const w1 = Offset(-122, 0);
    canvas.drawLine(const Offset(-35, 0), w0, cyl(const Offset(-35, 0), w0, 16, _cylAlu, _cylStops)..strokeCap = StrokeCap.round);
    canvas.drawLine(
      w0,
      w1,
      cyl(w0, w1, 58, const [Color(0xFF28292C), Color(0xFF7A7C80), Color(0xFF46484C), Color(0xFF19191B)], _cylStops)..strokeCap = StrokeCap.butt,
    );
    if (!shadow) {
      final knurl = Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..strokeWidth = 1.5;
      for (var i = 1; i < 9; i++) {
        final x = w0.dx + (w1.dx - w0.dx) * i / 9;
        canvas.drawLine(Offset(x, -29), Offset(x, 29), knurl);
      }
    }

    // Tube.
    canvas.drawLine(Offset.zero, joint, cyl(Offset.zero, joint, 15, _cylAlu, _cylStops)..strokeCap = StrokeCap.round);
    // Bague de la tête.
    canvas.drawLine(joint, h0, solid(const Color(0xFF19191B))..strokeWidth = 22);

    // Coque de la tête de lecture.
    final shell = Path()
      ..moveTo(h0.dx + hperp.dx * 13, h0.dy + hperp.dy * 13)
      ..lineTo(headEnd.dx + hperp.dx * 18, headEnd.dy + hperp.dy * 18)
      ..lineTo(headEnd.dx - hperp.dx * 18, headEnd.dy - hperp.dy * 18)
      ..lineTo(h0.dx - hperp.dx * 13, h0.dy - hperp.dy * 13)
      ..close();
    if (shadow) {
      canvas.drawPath(shell, solid(Colors.black));
    } else {
      canvas.drawPath(
        shell,
        Paint()
          ..shader = ui.Gradient.linear(h0 + hperp * 18, h0 - hperp * 18, const [Color(0xFF141416), Color(0xFF46474B), Color(0xFF0C0C0D)], const [0, 0.4, 1]),
      );
      canvas.drawPath(
        shell,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xC8969AA0),
      );
      // Cellule avec son liseré orange.
      final c0 = stylus - hdir * 22;
      final c1 = stylus + hdir * 12;
      canvas.drawLine(c0, c1, Paint()
        ..color = const Color(0xFF08080A)
        ..strokeWidth = 24);
      canvas.drawLine(c0, c0 + hdir * 8, Paint()
        ..color = const Color(0xFFFF7828)
        ..strokeWidth = 24);
    }

    // Lève-bras, vers l'extérieur du disque.
    final lift0 = headEnd - hdir * 25 - hperp * 16;
    final lift1 = lift0 - hperp * 35 + hdir * 10;
    canvas.drawLine(lift0, lift1, cyl(lift0, lift1, 6, _cylAlu, _cylStops)..strokeCap = StrokeCap.round);

    // Cardan au-dessus du pivot.
    if (!shadow) {
      canvas.drawCircle(Offset.zero, 34, _aluPaint(Rect.fromCircle(center: Offset.zero, radius: 34)));
      canvas.drawCircle(Offset.zero, 34, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF28282C));
      canvas.drawCircle(Offset.zero, 12, Paint()..color = const Color(0xFF1E1E21));
    }
  }

  @override
  bool shouldRepaint(covariant ArmPainter oldDelegate) => oldDelegate.shadow != shadow;
}

/// Bouton de volume : jupe moletée fixe, capuchon brossé, repère tournant.
class KnobPainter extends CustomPainter {
  const KnobPainter(this.angle);

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = G.knobR;
    canvas.drawCircle(
      c + const Offset(4, 8),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF262629));
    // Le moletage tourne avec le bouton.
    for (var i = 0; i < 72; i++) {
      final a = angle + 2 * math.pi * i / 72;
      canvas.drawLine(
        c + Offset.fromDirection(a, r * 0.86),
        c + Offset.fromDirection(a, r),
        Paint()
          ..strokeWidth = 2.5
          ..color = i.isEven ? const Color(0xFF5A5B5F) : const Color(0xFF141416),
      );
    }
    const cap = r * 0.82;
    canvas.drawCircle(c, cap, _aluPaint(Rect.fromCircle(center: c, radius: cap)));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 1; i < 8; i++) {
      ring.color = Colors.white.withValues(alpha: i.isEven ? 0.07 : 0.03);
      canvas.drawCircle(c, cap * i / 8, ring);
    }
    canvas.drawLine(
      c + Offset.fromDirection(angle, cap * 0.3),
      c + Offset.fromDirection(angle, cap * 0.88),
      Paint()
        ..color = const Color(0xFFFF8232)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant KnobPainter oldDelegate) => oldDelegate.angle != angle;
}

/// Bouton métallique (START·STOP, 33, 45) avec diode et effet d'enfoncement.
class ButtonPainter extends CustomPainter {
  const ButtonPainter({required this.pressed, required this.led, this.label, this.ledColor = const Color(0xFF5AFF82)});

  /// 0 = relâché, 1 = enfoncé.
  final double pressed;
  /// 0 = éteinte, 1 = allumée.
  final double led;
  final String? label;
  final Color ledColor;

  @override
  void paint(Canvas canvas, Size size) {
    final depth = 5.0 * (1 - pressed);
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(
      rr.shift(Offset(2, 2 + depth)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + depth * 0.6),
    );
    final top = Color.lerp(const Color(0xFFECEDEF), const Color(0xFFA0A2A6), pressed)!;
    final bottom = Color.lerp(const Color(0xFF96989C), const Color(0xFFC4C6CA), pressed)!;
    canvas.drawRRect(rr, Paint()..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [top, bottom]));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF28292C),
    );
    if (label != null) {
      _text(canvas, label!, rect.center, size: 18, color: const Color(0xFF2A2B2F), spacing: 2, weight: FontWeight.w700);
    }

    // Diode à droite du bouton.
    final ledPos = Offset(size.width + 22, size.height / 2);
    if (led > 0.01) {
      canvas.drawCircle(
        ledPos,
        18,
        Paint()
          ..shader = ui.Gradient.radial(ledPos, 18, [ledColor.withValues(alpha: 0.6 * led), ledColor.withValues(alpha: 0)]),
      );
    }
    canvas.drawCircle(ledPos, 6, Paint()..color = Color.lerp(ledColor.withValues(alpha: 1).darken(), ledColor, led)!);
  }

  @override
  bool shouldRepaint(covariant ButtonPainter old) => old.pressed != pressed || old.led != led || old.label != label;
}

/// Lampe stroboscopique.
class LampPainter extends CustomPainter {
  const LampPainter(this.glow);

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = G.lampR;
    const on = Color(0xFFFF7A28);
    if (glow > 0.01) {
      canvas.drawCircle(c, r * 3.2, Paint()..shader = ui.Gradient.radial(c, r * 3.2, [on.withValues(alpha: 0.55 * glow), on.withValues(alpha: 0)]));
    }
    canvas.drawCircle(c, r, Paint()..color = Color.lerp(const Color(0xFF3C2418), on, glow)!);
    canvas.drawCircle(c - const Offset(5, 5), r * 0.35, Paint()..color = Colors.white.withValues(alpha: 0.25 + 0.45 * glow));
  }

  @override
  bool shouldRepaint(covariant LampPainter old) => old.glow != glow;
}

/// Curseur du variateur.
class PitchKnobPainter extends CustomPainter {
  const PitchKnobPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(
      rr.shift(const Offset(2, 5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(rr, Paint()..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, const [Color(0xFFECEDEF), Color(0xFF8E9094)]));
    canvas.drawLine(rect.centerLeft + const Offset(6, 0), rect.centerRight - const Offset(6, 0), Paint()
      ..color = const Color(0xFF1E1E21)
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bord de l'étiquette, ombrage du papier et axe central (fixes).
class LabelOverlayPainter extends CustomPainter {
  const LabelOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = G.labelR;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, r, const [Color(0x00000000), Color(0x0A000000), Color(0x50000000)], const [0, 0.8, 1]),
    );
    canvas.drawCircle(c, r * 0.97, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black.withValues(alpha: 0.2));
    // Axe chromé.
    canvas.drawCircle(c + const Offset(2, 3), 12, Paint()..color = Colors.black.withValues(alpha: 0.5));
    canvas.drawCircle(c, 12, _aluPaint(Rect.fromCircle(center: c, radius: 12)));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension on Color {
  Color darken() => Color.lerp(this, Colors.black, 0.8)!;
}
