import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'classic.dart';
import 'finish.dart';
import 'look.dart';
import 'model.dart';
import 'wheel.dart';

/// Une teinte d'aluminium anodisé, relevée sur les photos d'Apple : la
/// couleur de la face ([base]), son reflet ([light]), l'ombre de ses flancs
/// ([dark]) et, tout au bord, le métal qui fuit la lumière ([deep]).
@immutable
class Anodized {
  const Anodized(this.name, this.displayName, {required this.base, required this.light, required this.dark, Color? deep})
      : _deep = deep; // ignore: prefer_initializing_formals

  final String name;
  final String displayName;
  final Color base;
  final Color light;
  final Color dark;
  final Color? _deep;

  Color get deep => _deep ?? Color.lerp(dark, Colors.black, 0.45)!;

  bool get isBlack => name == 'noir';

  /// Molette blanche, sauf sur le noir où elle est noire. [tintedButton] :
  /// bouton central en aluminium de la couleur du boîtier, légèrement
  /// creusé ([flatButton] : plat) ; [darkRing] : molette noire même sur une
  /// teinte claire (nano 4G argent).
  WheelStyle wheel({
    required double radius,
    required double buttonRadius,
    bool tintedButton = false,
    bool flatButton = false,
    bool darkRing = false,
  }) {
    final up = flatButton
        ? [Color.lerp(base, light, 0.25)!, base]
        : [Color.lerp(base, dark, 0.25)!, Color.lerp(base, light, 0.8)!];
    final down = [Color.lerp(base, dark, 0.6)!, Color.lerp(base, dark, 0.15)!];
    return isBlack || darkRing
        ? WheelStyle(
            radius: radius,
            buttonRadius: buttonRadius,
            iconScale: 0.65,
            labelSize: 11,
            labelSpacing: 0.8,
            label: const Color(0xFFE4E5E8),
            recess: const Color(0xFF0B0B0C),
            ring: const [Color(0xFF2B2B2D), Color(0xFF242426), Color(0xFF1D1D1F)],
            edgeLight: 0.1,
            groove: const Color(0xFF0C0C0D),
            buttonUp: up,
            buttonDown: down,
            buttonEdge: 0.12,
          )
        : WheelStyle(
            radius: radius,
            buttonRadius: buttonRadius,
            iconScale: 0.65,
            labelSize: 11,
            labelSpacing: 0.8,
            label: const Color(0xFF98A1AE),
            recess: Color.lerp(dark, Colors.black, 0.2)!,
            ring: const [Color(0xFFFCFDFE), Color(0xFFF7F9FB), Color(0xFFECEFF2)],
            groove: tintedButton ? Color.lerp(dark, Colors.black, 0.25)! : const Color(0xFFC6CBD0),
            buttonUp: tintedButton ? up : const [Color(0xFFFFFFFF), Color(0xFFEDEEF0)],
            buttonDown: tintedButton ? down : const [Color(0xFFDDDFE2), Color(0xFFF0F1F2)],
            buttonEdge: tintedButton ? 0.18 : 0.9,
          );
  }
}

/// Forme du boîtier, qui décide de la façon dont l'aluminium prend la
/// lumière.
enum AluShape {
  /// Plaque plate (shuffle) : éclairée d'en haut, uniforme en largeur.
  flat,

  /// Tube aplati (nano 2G) : face plate, flancs arrondis ; un reflet court
  /// le long du flanc gauche.
  tube,

  /// Section ovale (nano 4G) : la face est bombée d'un bord à l'autre, la
  /// teinte s'assombrit continûment du milieu vers les flancs.
  oval,

  /// Même section ovale, mais polie (nano 5G) : un large reflet brillant
  /// descend à droite du milieu, entre deux zones plus sombres.
  polished,
}

// --- nano 2e génération ------------------------------------------------------

/// Les six teintes du nano de 2e génération (2006).
const nano2Colors = [
  Anodized('argent', 'Argent', base: Color(0xFFD6DAD8), light: Color(0xFFEEF1F0), dark: Color(0xFF9AA09F)),
  Anodized('rose', 'Rose', base: Color(0xFFC51D7B), light: Color(0xFFF13BA3), dark: Color(0xFF870043)),
  Anodized('vert', 'Vert', base: Color(0xFF79BC27), light: Color(0xFFA5EB50), dark: Color(0xFF3C7A00)),
  Anodized('bleu', 'Bleu', base: Color(0xFF0086B5), light: Color(0xFF07AEE2), dark: Color(0xFF00577A)),
  Anodized('noir', 'Noir', base: Color(0xFF2A2B2E), light: Color(0xFF4A4B50), dark: Color(0xFF111213)),
  Anodized('rouge', 'Rouge', base: Color(0xFFB8101F), light: Color(0xFFE3323F), dark: Color(0xFF78000E)),
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
  WheelStyle get wheel => color.wheel(radius: 102, buttonRadius: 45, tintedButton: true);

  /// En haut à gauche, dans le bouchon en plastique.
  @override
  HoldSwitch? get hold => const HoldSwitch(40);

  @override
  ScreenLook get look => const ClassicLook(ui: ColorUi.video);

  @override
  CustomPainter get body => AnodizedBodyPainter(color, _radius, _screen, shape: AluShape.tube);

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
  // Section ovale : [base] est la teinte au milieu de la face, [dark] et
  // [deep] celles des flancs (relevées à 6 % et 1 % de la largeur).
  Anodized('argent', 'Argent', base: Color(0xFFDADADB), light: Color(0xFFEFEFF0), dark: Color(0xFF979798), deep: Color(0xFF747475)),
  Anodized('noir', 'Noir', base: Color(0xFF666466), light: Color(0xFF7C7A7D), dark: Color(0xFF2C2C2D), deep: Color(0xFF1C1B1C)),
  Anodized('violet', 'Violet', base: Color(0xFF7250C3), light: Color(0xFF8B6AD6), dark: Color(0xFF361688), deep: Color(0xFF1C046B)),
  Anodized('bleu', 'Bleu', base: Color(0xFF078CCE), light: Color(0xFF2AA6E4), dark: Color(0xFF004C87), deep: Color(0xFF00335E)),
  Anodized('vert', 'Vert', base: Color(0xFF7AD439), light: Color(0xFF97E65C), dark: Color(0xFF438000), deep: Color(0xFF326400)),
  Anodized('jaune', 'Jaune', base: Color(0xFFEBC700), light: Color(0xFFF7D930), dark: Color(0xFFA57600), deep: Color(0xFF7D5A00)),
  Anodized('orange', 'Orange', base: Color(0xFFF9861B), light: Color(0xFFFF9F40), dark: Color(0xFFAC4B00), deep: Color(0xFF6B2A00)),
  Anodized('rose', 'Rose', base: Color(0xFFF91E9E), light: Color(0xFFFF4DB4), dark: Color(0xFFA20061), deep: Color(0xFF6D0048)),
  Anodized('rouge', 'Rouge', base: Color(0xFFF4001E), light: Color(0xFFFF2A42), dark: Color(0xFFA50009), deep: Color(0xFF64000F)),
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
      color.wheel(radius: 97, buttonRadius: 44, tintedButton: true, flatButton: true, darkRing: color.name == 'argent');

  /// En haut à gauche : un minuscule bouton rond en métal poli.
  @override
  HoldSwitch? get hold => const HoldSwitch(46, kind: HoldKind.pin);

  @override
  ScreenLook get look => const ClassicLook(portrait: true);

  @override
  CustomPainter get body => AnodizedBodyPainter(color, _radius, _screen, shape: AluShape.oval);

  @override
  CustomPainter? get glass => const _ScreenGlassPainter(_screen);

  @override
  Size get windowSize => const Size(360, 720);

  @override
  bool operator ==(Object other) => other is Nano4Model && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

// --- nano 5e génération ------------------------------------------------------

/// Les neuf teintes du nano de 5e génération (2009), en aluminium poli :
/// [base] est la teinte moyenne, [light] le reflet, [dark] les zones qui
/// ne le reçoivent pas, [deep] les flancs.
const nano5Colors = [
  Anodized('argent', 'Argent', base: Color(0xFFA9A8AA), light: Color(0xFFD6D6D7), dark: Color(0xFF939394), deep: Color(0xFF515152)),
  // (Absent des photos d'Apple : réglé d'après les autres teintes.)
  Anodized('noir', 'Noir', base: Color(0xFF2C2C2F), light: Color(0xFF4E4E52), dark: Color(0xFF1F1F21), deep: Color(0xFF0A0A0B)),
  Anodized('violet', 'Violet', base: Color(0xFF4A3281), light: Color(0xFF654891), dark: Color(0xFF351D71), deep: Color(0xFF15184E)),
  Anodized('bleu', 'Bleu', base: Color(0xFF007CD9), light: Color(0xFF1A85E1), dark: Color(0xFF005DB8), deep: Color(0xFF12366C)),
  Anodized('vert', 'Vert', base: Color(0xFF0E6D2F), light: Color(0xFF13923C), dark: Color(0xFF0B5428), deep: Color(0xFF062F1B)),
  Anodized('jaune', 'Jaune', base: Color(0xFFE6AC08), light: Color(0xFFFACD0A), dark: Color(0xFFD8990B), deep: Color(0xFF905F1D)),
  Anodized('orange', 'Orange', base: Color(0xFFEC6C0D), light: Color(0xFFF38E10), dark: Color(0xFFCD5414), deep: Color(0xFF7A3319)),
  Anodized('rose', 'Rose', base: Color(0xFFD9006F), light: Color(0xFFE11A78), dark: Color(0xFFB80051), deep: Color(0xFF6C1230)),
  Anodized('rouge', 'Rouge', base: Color(0xFFA80919), light: Color(0xFFE00A27), dark: Color(0xFF950F15), deep: Color(0xFF761114)),
];

/// Le nano de 5e génération : le boîtier galbé de la 4e (38,7 × 90,7 mm),
/// en aluminium poli, avec un écran plus haut et une molette plus petite.
class Nano5Model extends IpodModel {
  const Nano5Model(this.color);

  final Anodized color;

  static const Size _size = Size(258, 605);
  static const Rect _screen = Rect.fromLTWH(25, 22, 208, 326);
  static const double _radius = 8;

  @override
  String get id => 'nano5-${color.name}';

  @override
  String get family => 'nano5';

  @override
  String get label => 'Nano 5G';

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
  Offset get wheelCenter => const Offset(129, 468);

  /// Bouton central de la couleur du boîtier ; l'argent a une molette noire.
  @override
  WheelStyle get wheel =>
      color.wheel(radius: 88, buttonRadius: 41, tintedButton: true, flatButton: true, darkRing: color.name == 'argent');

  /// En haut à gauche : le curseur du verrou.
  @override
  HoldSwitch? get hold => const HoldSwitch(46, kind: HoldKind.metal);

  @override
  ScreenLook get look => const ClassicLook(portrait: true, tall: true);

  @override
  CustomPainter get body => AnodizedBodyPainter(color, _radius, _screen, shape: AluShape.polished);

  @override
  CustomPainter? get glass => const _ScreenGlassPainter(_screen);

  @override
  Size get windowSize => const Size(360, 720);

  @override
  bool operator ==(Object other) => other is Nano5Model && other.color == color;

  @override
  int get hashCode => Object.hash('nano5', color);
}

// --- Dessin ------------------------------------------------------------------

/// Boîtier d'un seul tenant en aluminium anodisé ; [shape] dit comment il
/// prend la lumière.
class AnodizedBodyPainter extends CustomPainter {
  const AnodizedBodyPainter(this.color, this.radius, this.screen, {required this.shape});

  final Anodized color;
  final double radius;
  final Rect screen;
  final AluShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final c = color;
    final all = Offset.zero & size;
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

    paintFloatShadow(canvas, outer);

    canvas.save();
    canvas.clipRRect(outer);
    final across = Offset(size.width, 0), down = Offset(0, size.height);
    switch (shape) {
      case AluShape.flat:
        // Plaque éclairée d'en haut ; un rien plus claire du côté de la
        // lumière.
        canvas.drawRect(all, Paint()..shader = ui.Gradient.linear(Offset.zero, down, [c.light, c.base, c.dark], const [0, 0.5, 1]));
        canvas.drawRect(
          all,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, across, [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.10),
            ], const [0, 0.35, 1]),
        );
      case AluShape.tube:
        // Flancs arrondis presque noirs, un reflet vif juste après le flanc
        // gauche, puis la face, unie.
        canvas.drawRect(
          all,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              across,
              [c.deep, c.dark, c.light, mix(c.base, c.light, 0.2), c.base, c.base, mix(c.base, c.light, 0.25), c.dark, c.deep],
              const [0, 0.022, 0.055, 0.12, 0.3, 0.9, 0.94, 0.975, 1],
            ),
        );
        // Plus clair vers le haut, d'où vient la lumière.
        canvas.drawRect(
          all,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, down, [
              Colors.white.withValues(alpha: 0.13),
              Colors.white.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.10),
            ], const [0, 0.5, 1]),
        );
      case AluShape.oval:
        // Face bombée : pleine teinte au milieu, de plus en plus sombre
        // vers les flancs.
        canvas.drawRect(
          all,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              across,
              [
                c.deep,
                c.dark,
                mix(c.dark, c.base, 0.45),
                mix(c.dark, c.base, 0.75),
                c.base,
                c.base,
                mix(c.dark, c.base, 0.75),
                mix(c.dark, c.base, 0.45),
                c.dark,
                c.deep,
              ],
              const [0, 0.06, 0.15, 0.25, 0.42, 0.58, 0.75, 0.85, 0.94, 1],
            ),
        );
        canvas.drawRect(
          all,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, down, [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.12),
            ], const [0, 0.25, 1]),
        );
      case AluShape.polished:
        // Métal poli : flancs sombres, un liseré de teinte, puis l'ombre, et
        // le large reflet qui descend à droite du milieu.
        canvas.drawRect(
          all,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              across,
              [
                c.deep,
                c.base,
                c.base,
                c.dark,
                c.dark,
                mix(c.base, c.light, 0.5),
                c.light,
                c.light,
                c.base,
                c.dark,
                mix(c.dark, c.deep, 0.6),
                mix(c.deep, Colors.black, 0.35),
              ],
              const [0, 0.03, 0.07, 0.15, 0.26, 0.4, 0.5, 0.74, 0.85, 0.9, 0.945, 1],
            ),
        );
        canvas.drawRect(
          all,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, down, [
              Colors.white.withValues(alpha: 0.08),
              Colors.white.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.10),
            ], const [0, 0.25, 1]),
        );
    }
    paintSatin(canvas, size, strength: shape == AluShape.polished ? 0.25 : (c.isBlack ? 0.6 : 1));
    canvas.restore();

    // Arêtes : un filet de lumière en haut, plus sombre en bas.
    canvas.drawRRect(
      outer.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = ui.Gradient.linear(
          Offset.zero,
          down,
          [
            Colors.white.withValues(alpha: shape == AluShape.flat ? 0.5 : 0.35),
            Colors.white.withValues(alpha: 0.06),
            Colors.black.withValues(alpha: 0.22),
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

    // Écran sous une vitre noire, affleurante (le shuffle n'en a pas).
    if (screen.isEmpty) return;
    final frame = RRect.fromRectAndRadius(screen.inflate(7), const Radius.circular(5));
    canvas.drawRRect(frame.inflate(1), Paint()..color = Colors.black.withValues(alpha: 0.3));
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF0F1012));
  }

  @override
  bool shouldRepaint(covariant AnodizedBodyPainter old) =>
      old.color != color || old.radius != radius || old.screen != screen || old.shape != shape;
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
