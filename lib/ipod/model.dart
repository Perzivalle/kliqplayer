import 'package:flutter/widgets.dart';

import 'look.dart';
import 'wheel.dart';

/// Un modèle de baladeur : ses dimensions, sa matière et son écran. La
/// navigation, la molette et les sons sont communs à tous les modèles.
abstract class IpodModel {
  const IpodModel();

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

  /// Position de la prise casque (abscisse), sur la tranche du haut ou,
  /// si [jackOnTop] est faux, sur celle du bas.
  double get jackX;
  bool get jackOnTop => true;

  /// Boutons séparés de la molette (3e génération), et leur dessin.
  List<IpodButton> get buttons => const [];
  CustomPainter? buttonPainter(IpodButton button, {required bool pressed}) => null;

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

/// Bouton rond posé sur la façade, à côté de la molette.
@immutable
class IpodButton {
  const IpodButton(this.zone, this.center, this.radius);

  final WheelZone zone;
  final Offset center;
  final double radius;
}
