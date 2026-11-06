import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'look.dart';
import 'mini.dart';
import 'model.dart';
import 'nanos.dart';
import 'wheel.dart';

/// Le shuffle n'a pas d'écran : ce « look » n'est jamais affiché.
const _noScreen = MiniLook(size: Size(160, 128), visibleRows: 6);

/// Anneau de commandes d'un shuffle : blanc, symboles gris, bouton central
/// blanc (1G) ou de la couleur du boîtier (2G, 4G).
WheelStyle _pad(double radius, double button, {List<Color>? center, List<Color>? centerDown, Color recess = const Color(0xFFC9CBCE)}) =>
    WheelStyle(
      radius: radius,
      buttonRadius: button,
      shuffle: true,
      iconScale: radius / 110,
      labelInset: (radius + button) / 2 / radius,
      label: const Color(0xFFADB0B4),
      recess: recess,
      ring: const [Color(0xFFFAFAF8), Color(0xFFEFEFEC), Color(0xFFE2E2DF)],
      edgeLight: 0.6,
      groove: const Color(0xFFCDCFD2),
      buttonUp: center ?? const [Color(0xFFFFFFFF), Color(0xFFEDEEF0)],
      buttonDown: centerDown ?? const [Color(0xFFDDDFE2), Color(0xFFF0F1F2)],
    );

/// Le shuffle de 1re génération (2005) : une barrette de plastique blanc
/// (25 × 84 mm), l'anneau de commandes en haut, le connecteur USB sous un
/// capuchon en bas. Pas d'écran.
class Shuffle1Model extends IpodModel {
  const Shuffle1Model();

  static const Size _size = Size(167, 560);
  static const double _radius = 18;

  @override
  String get id => 'shuffle1';

  @override
  String get family => 'shuffle1';

  @override
  String get label => 'Shuffle 1G';

  @override
  String get variantName => 'Blanc';

  @override
  Color get swatch => const Color(0xFFF7F7F5);

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => Rect.zero;

  @override
  bool get hasScreen => false;

  /// Prise casque et voyant sur la tranche du haut.
  @override
  double get jackX => 58;

  @override
  double? get led => 124;

  @override
  Offset get wheelCenter => const Offset(83.5, 140);

  @override
  WheelStyle get wheel => _pad(76, 45, recess: const Color(0xFFD9DADC));

  @override
  ScreenLook get look => _noScreen;

  @override
  CustomPainter get body => const _StickPainter();

  @override
  CustomPainter? get glass => null;

  @override
  Size get windowSize => const Size(320, 700);
}

/// Les teintes du shuffle de 2e génération (2006-2008).
const shuffle2Colors = [
  Anodized('argent', 'Argent', base: Color(0xFFCDD0D3), light: Color(0xFFE6E8EA), dark: Color(0xFFA9ADB1)),
  Anodized('bleu', 'Bleu', base: Color(0xFF8DBEDF), light: Color(0xFFB4D5EC), dark: Color(0xFF6497BF)),
  Anodized('vert', 'Vert', base: Color(0xFF1F7F78), light: Color(0xFF3B9C94), dark: Color(0xFF125C57)),
  Anodized('violet', 'Violet', base: Color(0xFFA796C9), light: Color(0xFFC3B6DE), dark: Color(0xFF8170A8)),
  Anodized('rose', 'Rose', base: Color(0xFFE79BB9), light: Color(0xFFF1BED2), dark: Color(0xFFC57595)),
  Anodized('orange', 'Orange', base: Color(0xFFEE8F3E), light: Color(0xFFF4AE71), dark: Color(0xFFC46B22)),
  Anodized('rouge', 'Rouge', base: Color(0xFFC21F35), light: Color(0xFFD9475A), dark: Color(0xFF8E1424)),
];

/// Le shuffle de 2e génération (2006) : une pince en aluminium anodisé
/// (41 × 27 mm), l'anneau de commandes au milieu ; prise casque et voyant
/// en haut, interrupteurs en bas.
class Shuffle2Model extends IpodModel {
  const Shuffle2Model(this.color);

  final Anodized color;

  static const Size _size = Size(275, 182);
  static const double _radius = 11;

  @override
  String get id => 'shuffle2-${color.name}';

  @override
  String get family => 'shuffle2';

  @override
  String get label => 'Shuffle 2G';

  @override
  String get variantName => color.displayName;

  @override
  Color get swatch => color.base;

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => Rect.zero;

  @override
  bool get hasScreen => false;

  @override
  double get jackX => 55;

  @override
  double? get led => 252;

  /// Interrupteur (arrêt, lecture dans l'ordre, aléatoire), en bas.
  @override
  HoldSwitch? get hold => const HoldSwitch(110, onTop: false);

  @override
  Offset get wheelCenter => const Offset(137.5, 91);

  @override
  WheelStyle get wheel => _pad(
        66,
        40,
        center: [color.light, color.base],
        centerDown: [color.dark, color.base],
        recess: Color.lerp(color.dark, Colors.black, 0.15)!,
      );

  @override
  ScreenLook get look => _noScreen;

  @override
  CustomPainter get body => AnodizedBodyPainter(color, _radius, Rect.zero, rounded: false);

  @override
  CustomPainter? get glass => null;

  @override
  Size get windowSize => const Size(380, 420);

  @override
  bool operator ==(Object other) => other is Shuffle2Model && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

/// Les teintes du shuffle de 4e génération (2010).
const shuffle4Colors = [
  Anodized('argent', 'Argent', base: Color(0xFFCDD0D3), light: Color(0xFFE6E8EA), dark: Color(0xFFA9ADB1)),
  Anodized('bleu', 'Bleu', base: Color(0xFF3E86C4), light: Color(0xFF6BA6D8), dark: Color(0xFF2A649A)),
  Anodized('vert', 'Vert', base: Color(0xFF8DBE4E), light: Color(0xFFADD478), dark: Color(0xFF6A9A33)),
  Anodized('orange', 'Orange', base: Color(0xFFEE8F3E), light: Color(0xFFF4AE71), dark: Color(0xFFC46B22)),
  Anodized('rose', 'Rose', base: Color(0xFFE26D9E), light: Color(0xFFEE98BC), dark: Color(0xFFBC4A7A)),
];

/// Le shuffle de 4e génération (2010) : une petite pince carrée (29 × 31,6
/// mm), l'anneau de commandes presque bord à bord ; sur la tranche du haut,
/// l'interrupteur, le bouton VoiceOver, le voyant et la prise casque.
class Shuffle4Model extends IpodModel {
  const Shuffle4Model(this.color);

  final Anodized color;

  static const Size _size = Size(193, 211);
  static const double _radius = 18;

  @override
  String get id => 'shuffle4-${color.name}';

  @override
  String get family => 'shuffle4';

  @override
  String get label => 'Shuffle 4G';

  @override
  String get variantName => color.displayName;

  @override
  Color get swatch => color.base;

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => Rect.zero;

  @override
  bool get hasScreen => false;

  @override
  double get jackX => 172;

  @override
  double? get led => 150;

  /// L'interrupteur, à gauche sur la tranche du haut.
  @override
  HoldSwitch? get hold => const HoldSwitch(34, kind: HoldKind.metal);

  @override
  Offset get wheelCenter => const Offset(96.5, 105.5);

  @override
  WheelStyle get wheel => _pad(
        79,
        47,
        center: [color.light, color.base],
        centerDown: [color.dark, color.base],
        recess: Color.lerp(color.dark, Colors.black, 0.15)!,
      );

  @override
  ScreenLook get look => _noScreen;

  @override
  CustomPainter get body => AnodizedBodyPainter(color, _radius, Rect.zero, rounded: false);

  @override
  CustomPainter? get glass => null;

  @override
  Size get windowSize => const Size(340, 440);

  @override
  bool operator ==(Object other) => other is Shuffle4Model && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

/// La barrette du shuffle 1G : plastique blanc brillant, et en bas le
/// capuchon du connecteur USB, séparé par une fine rainure.
class _StickPainter extends CustomPainter {
  const _StickPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Shuffle1Model._radius));
    canvas.drawRRect(
      outer.shift(const Offset(0, 22)).deflate(8),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.drawRRect(
      outer.shift(const Offset(0, 5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, 0),
          const [Color(0xFFE4E5E3), Color(0xFFFBFBF9), Color(0xFFF2F2EF), Color(0xFFDCDDDB)],
          const [0, 0.3, 0.7, 1],
        ),
    );
    // Le capuchon : un peu plus mat.
    final cap = size.height - 100;
    canvas.save();
    canvas.clipRRect(outer);
    canvas.drawRect(Rect.fromLTWH(0, cap, size.width, size.height - cap), Paint()..color = Colors.black.withValues(alpha: 0.03));
    canvas.restore();
    canvas.drawLine(Offset(2, cap), Offset(size.width - 2, cap), Paint()
      ..strokeWidth = 1.5
      ..color = Colors.black.withValues(alpha: 0.12));
    canvas.drawLine(Offset(2, cap + 1.5), Offset(size.width - 2, cap + 1.5), Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.8));
    // Reflet vertical du plastique brillant.
    canvas.drawRRect(
      outer.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant _StickPainter old) => false;
}
