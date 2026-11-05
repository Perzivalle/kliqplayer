import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'classic.dart';
import 'look.dart';
import 'model.dart';
import 'wheel.dart';

/// Teintes du Nano de 3e génération (2007) : façade en aluminium anodisé,
/// molette blanche (noire sur le noir).
enum NanoColor {
  argent('Argent', base: Color(0xFFCDD0D3), light: Color(0xFFE6E8EA), dark: Color(0xFFA9ADB1)),
  noir('Noir', base: Color(0xFF2B2C2F), light: Color(0xFF3E3F43), dark: Color(0xFF1A1B1D)),
  bleu('Bleu', base: Color(0xFF93C1E3), light: Color(0xFFB9D8EF), dark: Color(0xFF6E9FC5)),
  vert('Vert', base: Color(0xFFA6D7B5), light: Color(0xFFC6E7D0), dark: Color(0xFF7DB491)),
  rouge('Rouge', base: Color(0xFFC21F35), light: Color(0xFFD9475A), dark: Color(0xFF8E1424));

  const NanoColor(this.displayName, {required this.base, required this.light, required this.dark});

  final String displayName;
  final Color base;
  final Color light;
  final Color dark;
}

/// Le Nano de 3e génération, le « gros » : presque carré (52 × 70 mm),
/// écran couleur 320×240, prise casque sous l'appareil.
class NanoModel extends IpodModel {
  const NanoModel([this.color = NanoColor.argent]);

  final NanoColor color;

  // ≈ 6,67 unités par mm.
  static const Size _size = Size(349, 466);
  static const Rect _screen = Rect.fromLTWH(39, 34, 271, 203);
  static const double _radius = 30;

  @override
  String get id => 'nano-${color.name}';

  @override
  String get family => 'nano';

  @override
  String get label => 'Nano';

  @override
  String get variantName => color.displayName;

  @override
  Color get swatch => color.base;

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => _screen;

  /// En bas à gauche, à côté du connecteur.
  @override
  double get jackX => 72;

  @override
  bool get jackOnTop => false;

  @override
  Offset get wheelCenter => const Offset(174.5, 354);

  @override
  WheelStyle get wheel => color == NanoColor.noir
      ? const WheelStyle(
          radius: 86,
          buttonRadius: 30,
          iconScale: 0.65,
          labelSize: 11,
          labelSpacing: 0.8,
          label: Color(0xFF8E9195),
          recess: Color(0xFF0E0F10),
          ring: [Color(0xFF3C3D40), Color(0xFF2C2D30), Color(0xFF1E1F22)],
          edgeLight: 0.12,
          groove: Color(0xFF111214),
          buttonUp: [Color(0xFF47484C), Color(0xFF2A2B2E)],
          buttonDown: [Color(0xFF26272A), Color(0xFF34353A)],
        )
      : WheelStyle(
          radius: 86,
          buttonRadius: 30,
          iconScale: 0.65,
          labelSize: 11,
          labelSpacing: 0.8,
          recess: Color.lerp(color.dark, Colors.black, 0.15)!,
        );

  @override
  ScreenLook get look => const ClassicLook();

  @override
  CustomPainter get body => _NanoBodyPainter(color);

  @override
  CustomPainter? get glass => const _NanoGlassPainter();

  @override
  Size get windowSize => const Size(420, 620);

  @override
  bool operator ==(Object other) => other is NanoModel && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

class _NanoBodyPainter extends CustomPainter {
  const _NanoBodyPainter(this.color);

  final NanoColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(NanoModel._radius));

    // Ombres : il flotte.
    canvas.drawRRect(
      outer.shift(const Offset(0, 22)).deflate(8),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
    canvas.drawRRect(
      outer.shift(const Offset(0, 5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Dos en acier poli qui déborde en fin liseré.
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

    // Façade en aluminium anodisé, mate et plate.
    final c = color;
    final front = outer.deflate(2.5);
    canvas.save();
    canvas.clipRRect(front);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width * 0.3, size.height),
          [c.light, c.base, c.dark],
          const [0, 0.45, 1],
        ),
    );
    final rnd = math.Random(17);
    final light = <Offset>[];
    final dark = <Offset>[];
    for (var i = 0; i < 3600; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      (rnd.nextBool() ? light : dark).add(p);
    }
    canvas.drawPoints(
      ui.PointMode.points,
      light,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 0.9,
    );
    canvas.drawPoints(
      ui.PointMode.points,
      dark,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.07)
        ..strokeWidth = 0.9,
    );
    canvas.restore();
    // Arête biseautée de la façade.
    canvas.drawRRect(
      front.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [Colors.white.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0.15)],
        ),
    );

    // Écran sous une vitre noire.
    final frame = RRect.fromRectAndRadius(NanoModel._screen.inflate(7), const Radius.circular(5));
    canvas.drawRRect(frame.inflate(1), Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF0F1012));
  }

  @override
  bool shouldRepaint(covariant _NanoBodyPainter old) => old.color != color;
}

/// Reflet sur la vitre de l'écran.
class _NanoGlassPainter extends CustomPainter {
  const _NanoGlassPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = NanoModel._screen.inflate(7);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(5)));
    canvas.drawPath(
      Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.left + r.width * 0.7, r.top)
        ..lineTo(r.left, r.top + r.height * 0.6)
        ..close(),
      Paint()
        ..shader = ui.Gradient.linear(
          r.topLeft,
          r.topLeft + Offset(r.width * 0.35, r.height * 0.3),
          [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.03)],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
