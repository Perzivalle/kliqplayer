import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'classic.dart';
import 'look.dart';
import 'model.dart';
import 'wheel.dart';

/// Une teinte d'aluminium anodisé : couleur, reflet et ombre.
@immutable
class Anodized {
  const Anodized(this.name, this.displayName, {required this.base, required this.light, required this.dark});

  final String name;
  final String displayName;
  final Color base;
  final Color light;
  final Color dark;

  bool get isBlack => name == 'noir';

  /// Molette blanche, sauf sur le noir où elle est noire. [tintedButton] :
  /// bouton central de la couleur du boîtier ; [darkRing] : molette noire
  /// même sur une teinte claire (nano 4G argent).
  WheelStyle wheel({
    required double radius,
    required double buttonRadius,
    bool tintedButton = false,
    bool darkRing = false,
  }) => isBlack || darkRing
      ? WheelStyle(
          radius: radius,
          buttonRadius: buttonRadius,
          iconScale: 0.65,
          labelSize: 11,
          labelSpacing: 0.8,
          label: const Color(0xFF8E9195),
          recess: const Color(0xFF0E0F10),
          ring: const [Color(0xFF3C3D40), Color(0xFF2C2D30), Color(0xFF1E1F22)],
          edgeLight: 0.12,
          groove: const Color(0xFF111214),
          buttonUp: isBlack ? const [Color(0xFF47484C), Color(0xFF2A2B2E)] : [light, base],
          buttonDown: isBlack ? const [Color(0xFF26272A), Color(0xFF34353A)] : [dark, base],
        )
      : WheelStyle(
          radius: radius,
          buttonRadius: buttonRadius,
          iconScale: 0.65,
          labelSize: 11,
          labelSpacing: 0.8,
          recess: Color.lerp(dark, Colors.black, 0.15)!,
          buttonUp: tintedButton ? [light, base] : const [Color(0xFFFFFFFF), Color(0xFFEDEEF0)],
          buttonDown: tintedButton ? [dark, base] : const [Color(0xFFDDDFE2), Color(0xFFF0F1F2)],
        );
}

// --- nano 2e génération ------------------------------------------------------

/// Les six teintes du nano de 2e génération (2006).
const nano2Colors = [
  Anodized('argent', 'Argent', base: Color(0xFFCDD0D3), light: Color(0xFFE6E8EA), dark: Color(0xFFA9ADB1)),
  Anodized('rose', 'Rose', base: Color(0xFFEBA9C2), light: Color(0xFFF5CADA), dark: Color(0xFFC9819D)),
  Anodized('vert', 'Vert', base: Color(0xFFAFD37A), light: Color(0xFFCBE5A3), dark: Color(0xFF86AE53)),
  Anodized('bleu', 'Bleu', base: Color(0xFF7FB3DD), light: Color(0xFFA9CDEA), dark: Color(0xFF5A8FBD)),
  Anodized('noir', 'Noir', base: Color(0xFF2B2C2F), light: Color(0xFF3E3F43), dark: Color(0xFF1A1B1D)),
  Anodized('rouge', 'Rouge', base: Color(0xFFC21F35), light: Color(0xFFD9475A), dark: Color(0xFF8E1424)),
];

/// Le nano de 2e génération : fin, tout en aluminium anodisé (40 × 90 mm),
/// petit écran couleur en haut, prise casque sous l'appareil.
class Nano2Model extends IpodModel {
  const Nano2Model(this.color);

  final Anodized color;

  // ≈ 6,67 unités par mm.
  static const Size _size = Size(267, 600);
  static const Rect _screen = Rect.fromLTWH(32, 46, 203, 153);
  static const double _radius = 24;

  @override
  String get id => 'nano2-${color.name}';

  @override
  String get family => 'nano2';

  @override
  String get label => 'Nano 2G';

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

  /// En bas à droite.
  @override
  double get jackX => 227;

  @override
  bool get jackOnTop => false;

  @override
  Offset get wheelCenter => const Offset(133.5, 420);

  @override
  WheelStyle get wheel => color.wheel(radius: 102, buttonRadius: 45);

  /// En haut à gauche, dans le bouchon en plastique.
  @override
  HoldSwitch? get hold => const HoldSwitch(40);

  @override
  ScreenLook get look => const ClassicLook();

  @override
  CustomPainter get body => _AnodizedBodyPainter(color, _radius, _screen, rounded: false);

  @override
  CustomPainter? get glass => const _ScreenGlassPainter(_screen);

  @override
  Size get windowSize => const Size(360, 720);

  @override
  bool operator ==(Object other) => other is Nano2Model && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

// --- nano 4e génération ------------------------------------------------------

/// Les neuf teintes du nano de 4e génération (2008).
const nano4Colors = [
  Anodized('argent', 'Argent', base: Color(0xFFCDD0D3), light: Color(0xFFE9EBEC), dark: Color(0xFFA2A6AA)),
  Anodized('noir', 'Noir', base: Color(0xFF2B2C2F), light: Color(0xFF45464A), dark: Color(0xFF161719)),
  Anodized('violet', 'Violet', base: Color(0xFF8F69B9), light: Color(0xFFAE8DD2), dark: Color(0xFF6A4891)),
  Anodized('bleu', 'Bleu', base: Color(0xFF3E86D4), light: Color(0xFF6BA6E4), dark: Color(0xFF2A64A8)),
  Anodized('vert', 'Vert', base: Color(0xFF79C24A), light: Color(0xFF9DD674), dark: Color(0xFF579A2F)),
  Anodized('jaune', 'Jaune', base: Color(0xFFF0D232), light: Color(0xFFF7E37A), dark: Color(0xFFC7A714)),
  Anodized('orange', 'Orange', base: Color(0xFFF08A2A), light: Color(0xFFF6AB62), dark: Color(0xFFC4661A)),
  Anodized('rose', 'Rose', base: Color(0xFFEA6EA0), light: Color(0xFFF299BE), dark: Color(0xFFC04B7B)),
  Anodized('rouge', 'Rouge', base: Color(0xFFC21F35), light: Color(0xFFDB4A5D), dark: Color(0xFF8C1424)),
];

/// Le nano de 4e génération : long, galbé (38,7 × 90,7 mm), écran
/// vertical, prise casque sous l'appareil.
class Nano4Model extends IpodModel {
  const Nano4Model(this.color);

  final Anodized color;

  static const Size _size = Size(258, 605);
  static const Rect _screen = Rect.fromLTWH(22, 24, 214, 285);
  static const double _radius = 8;

  @override
  String get id => 'nano4-${color.name}';

  @override
  String get family => 'nano4';

  @override
  String get label => 'Nano 4G';

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

  /// En bas à droite.
  @override
  double get jackX => 214;

  @override
  bool get jackOnTop => false;

  @override
  Offset get wheelCenter => const Offset(129, 449);

  /// Bouton central de la couleur du boîtier ; l'argent a une molette noire.
  @override
  WheelStyle get wheel =>
      color.wheel(radius: 97, buttonRadius: 44, tintedButton: true, darkRing: color.name == 'argent');

  /// En haut à gauche : un minuscule bouton rond en métal poli.
  @override
  HoldSwitch? get hold => const HoldSwitch(46, kind: HoldKind.pin);

  @override
  ScreenLook get look => const ClassicLook(portrait: true);

  @override
  CustomPainter get body => _AnodizedBodyPainter(color, _radius, _screen, rounded: true);

  @override
  CustomPainter? get glass => const _ScreenGlassPainter(_screen);

  @override
  Size get windowSize => const Size(360, 720);

  @override
  bool operator ==(Object other) => other is Nano4Model && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

// --- Dessin ------------------------------------------------------------------

/// Boîtier d'un seul tenant en aluminium anodisé. [rounded] : flancs galbés
/// (4e génération), sinon tranches plates aux arêtes adoucies.
class _AnodizedBodyPainter extends CustomPainter {
  const _AnodizedBodyPainter(this.color, this.radius, this.screen, {required this.rounded});

  final Anodized color;
  final double radius;
  final Rect screen;
  final bool rounded;

  static final _grain = <Size, (Float32List, Float32List)>{};

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final c = color;

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

    canvas.save();
    canvas.clipRRect(outer);
    // Teinte de fond, éclairée d'en haut à gauche.
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
    if (rounded) {
      // Flancs galbés : le métal fuit la lumière vers les bords.
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(size.width, 0),
            [
              Colors.black.withValues(alpha: 0.30),
              Colors.black.withValues(alpha: 0.04),
              Colors.white.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0.02),
              Colors.black.withValues(alpha: 0.06),
              Colors.black.withValues(alpha: 0.34),
            ],
            const [0, 0.1, 0.32, 0.55, 0.88, 1],
          ),
      );
    }
    // Grain du microbillage.
    final (light, dark) = _grain.putIfAbsent(size, () {
      final rnd = math.Random(23);
      final l = <double>[], d = <double>[];
      for (var i = 0; i < (size.width * size.height / 50).round(); i++) {
        final x = rnd.nextDouble() * size.width, y = rnd.nextDouble() * size.height;
        (rnd.nextBool() ? l : d).addAll([x, y]);
      }
      return (Float32List.fromList(l), Float32List.fromList(d));
    });
    canvas.drawRawPoints(
      ui.PointMode.points,
      light,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 0.9,
    );
    canvas.drawRawPoints(
      ui.PointMode.points,
      dark,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.07)
        ..strokeWidth = 0.9,
    );
    canvas.restore();

    // Arêtes : un filet de lumière en haut, plus sombre en bas.
    canvas.drawRRect(
      outer.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rounded ? 2 : 3
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [
            Colors.white.withValues(alpha: 0.6),
            Colors.white.withValues(alpha: 0.15),
            Colors.black.withValues(alpha: 0.2),
          ],
          const [0, 0.5, 1],
        ),
    );
    canvas.drawRRect(
      outer.deflate(0.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = Colors.black.withValues(alpha: 0.35),
    );

    // Écran sous une vitre noire, affleurante.
    final frame = RRect.fromRectAndRadius(screen.inflate(7), const Radius.circular(5));
    canvas.drawRRect(frame.inflate(1), Paint()..color = Colors.black.withValues(alpha: 0.3));
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF0F1012));
  }

  @override
  bool shouldRepaint(covariant _AnodizedBodyPainter old) =>
      old.color != color || old.radius != radius || old.screen != screen || old.rounded != rounded;
}

/// Reflet sur la vitre de l'écran.
class _ScreenGlassPainter extends CustomPainter {
  const _ScreenGlassPainter(this.screen);

  final Rect screen;

  @override
  void paint(Canvas canvas, Size size) {
    final r = screen.inflate(7);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(5)));
    canvas.drawPath(
      Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.left + r.width * 0.7, r.top)
        ..lineTo(r.left, r.top + r.height * 0.6)
        ..close(),
      Paint()
        ..shader = ui.Gradient.linear(r.topLeft, r.topLeft + Offset(r.width * 0.35, r.height * 0.3), [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.03),
        ]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScreenGlassPainter old) => old.screen != screen;
}
