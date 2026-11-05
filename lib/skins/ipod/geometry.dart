import 'dart:ui';

/// Dimensions du baladeur, en unités de dessin (≈ 6,67 unités par mm,
/// d'après un Classic de 61,8 × 103,5 mm).
class IpodGeometry {
  static const Size size = Size(412, 690);
  static const double radius = 36;

  /// Liseré chromé visible tout autour de la façade.
  static const double rim = 3;

  /// Cadre sombre autour de l'écran, puis l'écran lui-même (4:3).
  static const Rect screenFrame = Rect.fromLTWH(32, 34, 348, 261);
  static const Rect screen = Rect.fromLTWH(38, 40, 336, 252);

  /// Résolution logique de l'interface affichée sur l'écran.
  static const Size screenUi = Size(320, 240);

  static const Offset wheelCenter = Offset(206, 498);
  static const double wheelRadius = 132;
  static const double buttonRadius = 50;
}
