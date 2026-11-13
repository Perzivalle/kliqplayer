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

  /// Un écran (le shuffle n'en a pas : on ne fait que lire, à l'aveugle).
  bool get hasScreen => true;

  /// Voyant d'état sur la tranche du haut (abscisse, en unités) : il
  /// clignote en vert quand on appuie (shuffle).
  double? get led => null;
  double get screenCornerRadius => 2;

  /// Position de la prise casque (abscisse), sur la tranche du haut ou,
  /// si [jackOnTop] est faux, sur celle du bas.
  double get jackX;
  bool get jackOnTop => true;

  /// Teinte à laquelle assortir les pochettes (Couleur au hasard, nano 4G
  /// et 5G) ; null : pas de Couleur au hasard sur ce modèle.
  Color? get coverColor => null;

  /// Verrou (Hold) sur la tranche, purement décoratif : on le voit, il ne
  /// fait rien.
  HoldSwitch? get hold => null;

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

/// Forme du curseur du verrou.
enum HoldKind {
  /// Curseur en plastique, à peine en relief (1G, 3G, Mini, 4G, nano 2G).
  plastic,

  /// Curseur en métal (Classic, nano 3G).
  metal,

  /// Minuscule bouton rond en métal poli (nano 4G).
  pin,
}

/// Verrou visible sur la tranche du haut ou, si [onTop] est faux, du bas.
/// On n'en voit que le curseur, qui dépasse à peine.
@immutable
class HoldSwitch {
  const HoldSwitch(this.x, {this.onTop = true, this.kind = HoldKind.plastic, this.knob});

  /// Abscisse du centre, en unités de dessin.
  final double x;
  final bool onTop;
  final HoldKind kind;

  /// Dégradé du curseur (sinon, celui de sa matière).
  final List<Color>? knob;

  double get width => switch (kind) {
    HoldKind.plastic => 30,
    HoldKind.metal => 24,
    HoldKind.pin => 11,
  };

  @override
  bool operator ==(Object other) =>
      other is HoldSwitch && other.x == x && other.onTop == onTop && other.kind == kind && other.knob == knob;

  @override
  int get hashCode => Object.hash(x, onTop, kind, knob);
}

/// Bouton rond posé sur la façade, à côté de la molette.
@immutable
class IpodButton {
  const IpodButton(this.zone, this.center, this.radius);

  final WheelZone zone;
  final Offset center;
  final double radius;
}
