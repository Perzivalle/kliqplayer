import 'package:flutter/widgets.dart';

import 'look.dart';
import 'wheel.dart';

/// Un modèle de baladeur : ses dimensions, sa matière et son écran. La
/// navigation, la molette et les sons sont communs à tous les modèles.
abstract class IpodModel {
  const IpodModel();

  /// Nom de la skin.
  String get name;

  /// Identifiant stable (préférences).
  String get id;

  /// Famille (un emplacement par famille dans le tiroir) et son nom.
  String get family;
  String get label;

  /// Teinte de cette variante : nom et couleur de la pastille.
  String get variantName;
  Color get swatch;

  /// Taille du boîtier, en unités de dessin.
  Size get size;

  /// Arrondi des coins du boîtier.
  double get cornerRadius;

  /// Emplacement de l'écran sur la façade.
  Rect get screen;
  double get screenCornerRadius => 2;

  Offset get wheelCenter;
  WheelStyle get wheel;
  ScreenLook get look;

  /// Boîtier (sous l'écran) et reflet (par-dessus), dessinés sur [size].
  CustomPainter get body;
  CustomPainter? get glass;

  /// Taille initiale de la fenêtre et marge autour de l'appareil (ombre).
  Size get windowSize => const Size(440, 740);
  EdgeInsets get margin => const EdgeInsets.fromLTRB(24, 16, 24, 40);
}
