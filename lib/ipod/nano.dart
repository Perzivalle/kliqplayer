import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'classic.dart';
import 'finish.dart';
import 'look.dart';
import 'model.dart';
import 'wheel.dart';

/// Teintes du Nano de 3e génération (2007) : façade en aluminium anodisé,
/// molette blanche (noire sur le noir).
enum NanoColor {
  argent('Argent', base: Color(0xFFBFC4C6), light: Color(0xFFDFE4E5), dark: Color(0xFF8F9599)),
  noir('Noir', base: Color(0xFF26282E), light: Color(0xFF3F4148), dark: Color(0xFF131418)),
  bleu('Bleu', base: Color(0xFF60B8B8), light: Color(0xFF9DD3D8), dark: Color(0xFF2F7B83)),
  vert('Vert', base: Color(0xFFA3D3A0), light: Color(0xFFCBE9C8), dark: Color(0xFF6C9F6E)),
  rouge('Rouge', base: Color(0xFF8E1031), light: Color(0xFFBA1A49), dark: Color(0xFF5C0920)),
  rose('Rose', base: Color(0xFFB83479), light: Color(0xFFE8529E), dark: Color(0xFF8A1F58));

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
  String get label => 'Nano 3G';

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

  /// En bas à droite (le verrou est en bas à gauche).
  @override
  double get jackX => 297;

  @override
  bool get jackOnTop => false;

  @override
  Offset get wheelCenter => const Offset(174.5, 354);

  @override
  WheelStyle get wheel => color == NanoColor.noir
      ? const WheelStyle(
          radius: 86,
          buttonRadius: 42,
          iconScale: 0.65,
          labelSize: 11,
          labelSpacing: 0.8,
          label: Color(0xFFE1E2E4),
          recess: Color(0xFF0B0C0E),
          ring: [Color(0xFF292B31), Color(0xFF25272D), Color(0xFF1E2025)],
          edgeLight: 0.1,
          groove: Color(0xFF0E0F12),
          buttonUp: [Color(0xFF212328), Color(0xFF2E3037)],
          buttonDown: [Color(0xFF17181C), Color(0xFF24262B)],
          buttonEdge: 0.1,
        )
      : WheelStyle(
          radius: 86,
          buttonRadius: 42,
          iconScale: 0.65,
          labelSize: 11,
          labelSpacing: 0.8,
          label: const Color(0xFF95A0AC),
          recess: Color.lerp(color.dark, Colors.black, 0.2)!,
          ring: const [Color(0xFFFFFFFF), Color(0xFFFBFDFD), Color(0xFFEFF2F3)],
          groove: Color.lerp(color.dark, Colors.black, 0.25)!,
          // Bouton central en aluminium de la couleur du boîtier, un peu
          // creusé : sombre en haut, clair en bas.
          buttonUp: [Color.lerp(color.base, color.dark, 0.3)!, Color.lerp(color.base, color.light, 0.8)!],
          buttonDown: [Color.lerp(color.base, color.dark, 0.6)!, Color.lerp(color.base, color.dark, 0.15)!],
          buttonEdge: 0.18,
        );

  /// Petit curseur en métal, en bas à gauche.
  @override
  HoldSwitch? get hold => const HoldSwitch(35, onTop: false, kind: HoldKind.metal);

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

    paintFloatShadow(canvas, outer);

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

    // Façade en aluminium anodisé, mate et bombée comme un coussin : unie
    // au milieu, elle s'éclaircit en tombant vers les bords.
    final c = color;
    final front = outer.deflate(2);
    canvas.save();
    canvas.clipRRect(front);
    canvas.drawRect(Offset.zero & size, Paint()..color = c.base);
    // (Des filets emboîtés plutôt qu'un flou : régulier jusque dans les
    // coins.)
    const bevel = 30.0, steps = 20;
    for (var i = 0; i < steps; i++) {
      final t = 1 - i / steps;
      canvas.drawRRect(
        front.deflate(bevel * (i + 0.5) / steps),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bevel / steps + 0.6
          ..color = c.light.withValues(alpha: t * t * 0.85),
      );
    }
    // La lumière vient d'en haut à gauche : le coin opposé reste un peu
    // dans l'ombre.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: 0.14)],
          const [0, 0.5, 1],
        ),
    );
    paintSatin(canvas, size, strength: color == NanoColor.noir ? 0.6 : 1);
    canvas.restore();
    // Arête de la façade.
    canvas.drawRRect(
      front.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [Colors.white.withValues(alpha: 0.45), Colors.black.withValues(alpha: 0.18)],
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
