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
WheelStyle _pad(double radius, double button, {Anodized? tint, bool darkRing = false, Color recess = const Color(0xFFC9CBCE)}) =>
    WheelStyle(
      radius: radius,
      buttonRadius: button,
      shuffle: true,
      iconScale: radius / 110,
      labelInset: (radius + button) / 2 / radius,
      // Anneau blanc aux symboles gris, ou noir aux symboles blancs (4G
      // argent et gris sidéral : le ⏯ du bouton y est gravé en sombre).
      label: darkRing ? const Color(0xFFF2F3F5) : const Color(0xFFA3ACB0),
      centerLabel: darkRing ? const Color(0xFF1A1A1C) : null,
      recess: recess,
      ring: darkRing
          ? const [Color(0xFF232325), Color(0xFF19191B), Color(0xFF0E0E10)]
          : const [Color(0xFFFCFDFF), Color(0xFFF3F7FB), Color(0xFFE6EAEE)],
      edgeLight: darkRing ? 0.1 : 0.6,
      groove: darkRing
          ? const Color(0xFF050506)
          : tint == null
              ? const Color(0xFFCDCFD2)
              : Color.lerp(tint.dark, Colors.black, 0.3)!,
      // Bouton central en aluminium de la couleur du boîtier, plat.
      buttonUp: tint == null
          ? const [Color(0xFFFFFFFF), Color(0xFFEDEEF0)]
          : [Color.lerp(tint.base, tint.light, 0.5)!, Color.lerp(tint.base, tint.dark, 0.3)!],
      buttonDown: tint == null
          ? const [Color(0xFFDDDFE2), Color(0xFFF0F1F2)]
          : [tint.dark, Color.lerp(tint.base, tint.dark, 0.4)!],
      buttonEdge: tint == null ? 0.9 : 0.18,
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
  Anodized('argent', 'Argent', base: Color(0xFFC8C9CB), light: Color(0xFFD3D5D6), dark: Color(0xFFBBBDBE)),
  Anodized('bleu', 'Bleu', base: Color(0xFF006DB6), light: Color(0xFF0079C2), dark: Color(0xFF0062A6)),
  Anodized('vert', 'Vert', base: Color(0xFF4F9800), light: Color(0xFF5AA708), dark: Color(0xFF458A00)),
  Anodized('violet', 'Violet', base: Color(0xFF9C8AC6), light: Color(0xFFAC9BD3), dark: Color(0xFF8A78B4)),
  Anodized('rose', 'Rose', base: Color(0xFFBD227A), light: Color(0xFFC92A84), dark: Color(0xFFAE1C70)),
  Anodized('orange', 'Orange', base: Color(0xFFE9831C), light: Color(0xFFF2922E), dark: Color(0xFFD67413)),
  Anodized('rouge', 'Rouge', base: Color(0xFFB80012), light: Color(0xFFC70017), dark: Color(0xFFA6000F)),
];

/// Le shuffle de 2e génération (2006) : une pince en aluminium anodisé
/// (41 × 27 mm), l'anneau de commandes décalé vers la droite (mesuré sur la
/// photo d'Apple : centre à +12 % de la largeur, 57 % de la largeur de
/// diamètre) ; prise casque et voyant en haut, interrupteurs en bas.
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
  Offset get wheelCenter => const Offset(170.5, 91);

  @override
  WheelStyle get wheel => _pad(78, 47, tint: color, recess: Color.lerp(color.dark, Colors.black, 0.25)!);

  @override
  ScreenLook get look => _noScreen;

  @override
  CustomPainter get body => AnodizedBodyPainter(color, _radius, Rect.zero, shape: AluShape.flat);

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
  // 2010.
  Anodized('argent', 'Argent', base: Color(0xFFA2A3A8), light: Color(0xFFB9BABF), dark: Color(0xFF85878C)),
  Anodized('bleu', 'Bleu', base: Color(0xFF3A6EB6), light: Color(0xFF568FCF), dark: Color(0xFF245198)),
  Anodized('vert', 'Vert', base: Color(0xFF71972B), light: Color(0xFF88B13C), dark: Color(0xFF5E831E)),
  Anodized('orange', 'Orange', base: Color(0xFFC57418), light: Color(0xFFE08D1F), dark: Color(0xFFB26113)),
  Anodized('rose', 'Rose', base: Color(0xFFC72D72), light: Color(0xFFDB4F8B), dark: Color(0xFFBA1862)),
  // 2015.
  Anodized('sideral', 'Gris sidéral', base: Color(0xFF46454B), light: Color(0xFF58565C), dark: Color(0xFF34333A)),
  Anodized('or', 'Or', base: Color(0xFFE8D3B8), light: Color(0xFFF3DEC1), dark: Color(0xFFD2BC9E)),
  Anodized('bleu2015', 'Bleu (2015)', base: Color(0xFF1950AF), light: Color(0xFF1D58BC), dark: Color(0xFF1546A0)),
  Anodized('rose2015', 'Rose (2015)', base: Color(0xFFF41A7A), light: Color(0xFFFB3087), dark: Color(0xFFD81268)),
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
  double get jackX => 160;

  @override
  double? get led => 136;

  /// L'interrupteur, à gauche sur la tranche du haut.
  @override
  HoldSwitch? get hold => const HoldSwitch(34, kind: HoldKind.metal);

  @override
  Offset get wheelCenter => const Offset(96.5, 105.5);

  @override
  WheelStyle get wheel => _pad(
        79,
        47,
        tint: color,
        darkRing: color.name == 'argent' || color.name == 'sideral',
        recess: Color.lerp(color.dark, Colors.black, 0.25)!,
      );

  @override
  ScreenLook get look => _noScreen;

  @override
  CustomPainter get body => AnodizedBodyPainter(color, _radius, Rect.zero, shape: AluShape.flat);

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
