import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'classic.dart';
import 'look.dart';
import 'mini.dart';
import 'model.dart';
import 'wheel.dart';

/// Écran monochrome des premières générations : 160 × 128, 6 lignes.
const _monoLook = MiniLook(size: Size(160, 128), visibleRows: 6);

/// Les deux premières générations : la police Chicago, pas encore de notes.
const _chicagoLook = MiniLook(size: Size(160, 128), visibleRows: 6, font: 'ChicagoFLF', ratings: false);

/// La 1re génération (2001) : molette mécanique qui tourne vraiment,
/// entourée de quatre boutons, écran monochrome, façade blanche.
class FirstGenModel extends IpodModel {
  const FirstGenModel();

  // ≈ 6,67 unités par mm (61,8 × 102 mm).
  static const Size _size = Size(412, 680);
  static const Rect _screen = Rect.fromLTWH(76, 44, 260, 208);
  static const double _radius = 34;

  @override
  String get id => 'gen1';

  @override
  String get family => 'gen1';

  @override
  String get label => '1re génération';

  @override
  String get variantName => 'Blanc';

  @override
  Color get swatch => const Color(0xFFF7F7F5);

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => _screen;

  /// Au milieu de la tranche du haut, entre le port FireWire (à gauche) et
  /// le verrou (à droite).
  @override
  double get jackX => 212;

  @override
  Offset get wheelCenter => const Offset(206, 461);

  @override
  WheelStyle get wheel => const WheelStyle(
        radius: 172,
        buttonRadius: 62,
        innerRadius: 123,
        labelInset: 0.86,
        labelSize: 17,
        menuLabel: 'menu',
        labelSpacing: 1,
        iconScale: 0.75,
        label: Color(0xFF9A9EA3),
        ring: [Color(0xFFF4F5F6), Color(0xFFE6E8EA), Color(0xFFD8DBDE)],
        inner: [Color(0xFFFBFBFC), Color(0xFFEEEFF1), Color(0xFFDFE1E4)],
        groove: Color(0xFFB9BCC0),
      );

  /// En haut à droite.
  @override
  HoldSwitch? get hold => const HoldSwitch(330);

  @override
  ScreenLook get look => _chicagoLook;

  @override
  CustomPainter get body => const _WhiteBodyPainter(_size, _radius, _screen);

  @override
  CustomPainter? get glass => const _GlassPainter(_size, _radius, _screen);
}

/// La 2e génération (2002) : même boîtier que la première, mais la molette
/// est tactile (elle ne tourne plus), toujours entourée de ses quatre
/// boutons.
class SecondGenModel extends IpodModel {
  const SecondGenModel();

  static const Size _size = FirstGenModel._size;
  static const Rect _screen = FirstGenModel._screen;
  static const double _radius = FirstGenModel._radius;

  @override
  String get id => 'gen2';

  @override
  String get family => 'gen2';

  @override
  String get label => '2e génération';

  @override
  String get variantName => 'Blanc';

  @override
  Color get swatch => const Color(0xFFF7F7F5);

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => _screen;

  /// Au milieu de la tranche du haut, à côté de la prise télécommande ; le
  /// port FireWire (sous son volet) à gauche, le verrou à droite.
  @override
  double get jackX => 200;

  @override
  Offset get wheelCenter => const Offset(206, 461);

  /// Surface tactile lisse et fixe, un peu plus claire que la molette
  /// mécanique.
  @override
  WheelStyle get wheel => const WheelStyle(
        radius: 172,
        buttonRadius: 62,
        innerRadius: 123,
        turns: false,
        labelInset: 0.86,
        labelSize: 17,
        menuLabel: 'menu',
        labelSpacing: 1,
        iconScale: 0.75,
        label: Color(0xFF9A9EA3),
        ring: [Color(0xFFF4F5F6), Color(0xFFE6E8EA), Color(0xFFD8DBDE)],
        inner: [Color(0xFFFDFDFD), Color(0xFFF3F4F5), Color(0xFFE6E8EA)],
        groove: Color(0xFFC3C6CA),
      );

  @override
  HoldSwitch? get hold => const HoldSwitch(330);

  @override
  ScreenLook get look => _chicagoLook;

  @override
  CustomPainter get body => const _WhiteBodyPainter(_size, _radius, _screen);

  @override
  CustomPainter? get glass => const _GlassPainter(_size, _radius, _screen);
}

/// La 3e génération (2003) : molette tactile sans inscriptions, quatre
/// boutons ronds alignés au-dessus, rétroéclairés en orange.
class ThirdGenModel extends IpodModel {
  const ThirdGenModel();

  // ≈ 6,67 unités par mm (61,8 × 104 mm).
  static const Size _size = Size(412, 693);
  static const Rect _screen = Rect.fromLTWH(65, 46, 282, 226);
  static const double _radius = 32;

  @override
  String get id => 'gen3';

  @override
  String get family => 'gen3';

  @override
  String get label => '3e génération';

  @override
  String get variantName => 'Blanc';

  @override
  Color get swatch => const Color(0xFFF7F7F5);

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => _screen;

  /// Au milieu de la tranche du haut, entre le verrou (à gauche) et la
  /// prise télécommande (à droite).
  @override
  double get jackX => 218;

  @override
  Offset get wheelCenter => const Offset(206, 532);

  @override
  WheelStyle get wheel => const WheelStyle(
        radius: 138,
        buttonRadius: 52,
        labels: false,
        sideClicks: false,
        ring: [Color(0xFFF1F2F3), Color(0xFFE5E7E9), Color(0xFFD9DCDF)],
      );

  @override
  List<IpodButton> get buttons => const [
        IpodButton(WheelZone.previous, Offset(83, 318), 27),
        IpodButton(WheelZone.menu, Offset(165, 318), 27),
        IpodButton(WheelZone.playPause, Offset(247, 318), 27),
        IpodButton(WheelZone.next, Offset(329, 318), 27),
      ];

  /// En haut à gauche.
  @override
  HoldSwitch? get hold => const HoldSwitch(82);

  @override
  CustomPainter buttonPainter(IpodButton button, {required bool pressed}) =>
      _BacklitButtonPainter(button.zone, pressed);

  @override
  ScreenLook get look => _monoLook;

  @override
  CustomPainter get body => const _WhiteBodyPainter(_size, _radius, _screen);

  @override
  CustomPainter? get glass => const _GlassPainter(_size, _radius, _screen);
}

/// Teintes de la 4e génération : blanche, ou l'édition U2 (façade noire,
/// molette rouge).
enum FourthGenColor {
  blanc('Blanc', Color(0xFFF7F7F5)),
  u2('U2', Color(0xFFC41E26));

  const FourthGenColor(this.displayName, this.swatch);

  final String displayName;
  final Color swatch;
}

/// La 4e génération (2004) : la molette cliquable du Mini sur le grand
/// iPod, inscriptions sur la molette, écran monochrome.
class FourthGenModel extends IpodModel {
  const FourthGenModel([this.color = FourthGenColor.blanc]);

  final FourthGenColor color;

  // ≈ 6,67 unités par mm (61 × 104,1 mm).
  static const Size _size = Size(407, 694);
  static const Rect _screen = Rect.fromLTWH(70, 50, 267, 214);
  static const double _radius = 28;

  @override
  String get id => color == FourthGenColor.blanc ? 'gen4' : 'gen4-${color.name}';

  @override
  String get family => 'gen4';

  @override
  String get label => '4e génération';

  @override
  String get variantName => color.displayName;

  @override
  Color get swatch => color.swatch;

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => _screen;

  /// Au milieu de la tranche du haut, à droite de la prise télécommande
  /// (le verrou est tout à droite).
  @override
  double get jackX => 216;

  @override
  Offset get wheelCenter => const Offset(203.5, 495);

  @override
  WheelStyle get wheel => switch (color) {
    // Molette gris clair, inscriptions presque blanches.
    FourthGenColor.blanc => const WheelStyle(
      radius: 140,
      buttonRadius: 47,
      labelSize: 17,
      label: Color(0xFFF2F3F4),
      recess: Color(0xFFDDDEDF),
      ring: [Color(0xFFD3D5D8), Color(0xFFC8CACD), Color(0xFFBCBEC2)],
      edgeLight: 0.45,
      groove: Color(0xFFAEB1B5),
      buttonUp: [Color(0xFFF7F7F8), Color(0xFFE2E3E5)],
      buttonDown: [Color(0xFFD9DADC), Color(0xFFEDEEEF)],
    ),
    // Molette rouge, inscriptions claires, bouton central noir.
    FourthGenColor.u2 => const WheelStyle(
      radius: 140,
      buttonRadius: 47,
      labelSize: 17,
      label: Color(0xFFF1DADB),
      recess: Color(0xFF0E0F10),
      ring: [Color(0xFFD9333A), Color(0xFFC41E26), Color(0xFFA3151C)],
      edgeLight: 0.3,
      groove: Color(0xFF3A0B0E),
      buttonUp: [Color(0xFF47484C), Color(0xFF2A2B2E)],
      buttonDown: [Color(0xFF26272A), Color(0xFF34353A)],
    ),
  };

  @override
  ScreenLook get look => _monoLook;

  @override
  CustomPainter get body => switch (color) {
    FourthGenColor.blanc => const _WhiteBodyPainter(_size, _radius, _screen),
    FourthGenColor.u2 => const _WhiteBodyPainter(
      _size,
      _radius,
      _screen,
      front: [Color(0xFF3A3B3E), Color(0xFF242528), Color(0xFF17181A)],
    ),
  };

  @override
  CustomPainter? get glass => const _GlassPainter(_size, _radius, _screen);

  /// En haut à droite (curseur noir sur l'U2).
  @override
  HoldSwitch? get hold => color == FourthGenColor.u2
      ? const HoldSwitch(346, knob: [Color(0xFF55565A), Color(0xFF2A2B2E), Color(0xFF1A1B1D)])
      : const HoldSwitch(346);

  @override
  bool operator ==(Object other) => other is FourthGenModel && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

/// L'iPod photo (fin 2004) : le boîtier de la 4e génération, molette
/// grise, et pour la première fois un écran couleur.
class PhotoModel extends IpodModel {
  const PhotoModel();

  static const Size _size = FourthGenModel._size;
  static const Rect _screen = Rect.fromLTWH(76, 44, 256, 192);
  static const double _radius = FourthGenModel._radius;

  @override
  String get id => 'photo';

  @override
  String get family => 'photo';

  @override
  String get label => 'iPod photo';

  @override
  String get variantName => 'Blanc';

  @override
  Color get swatch => const Color(0xFFF7F7F5);

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => _screen;

  @override
  double get jackX => 216;

  @override
  Offset get wheelCenter => const Offset(203.5, 488);

  @override
  WheelStyle get wheel => const FourthGenModel().wheel;

  @override
  HoldSwitch? get hold => const HoldSwitch(346);

  @override
  ScreenLook get look => const ClassicLook(ui: ColorUi.video);

  @override
  CustomPainter get body => const _WhiteBodyPainter(_size, _radius, _screen);

  @override
  CustomPainter? get glass => const _GlassPainter(_size, _radius, _screen);
}

/// Teintes du nano de 1re génération : plastique brillant blanc ou noir.
enum Nano1Color {
  blanc('Blanc', Color(0xFFF7F7F5)),
  noir('Noir', Color(0xFF1E1F21));

  const Nano1Color(this.displayName, this.swatch);

  final String displayName;
  final Color swatch;
}

/// Le nano de 1re génération (2005) : très fin (40 × 90 mm), façade en
/// plastique brillant sous un liseré transparent, dos chromé, petit écran
/// couleur en haut, molette grise.
class Nano1Model extends IpodModel {
  const Nano1Model([this.color = Nano1Color.blanc]);

  final Nano1Color color;

  static const Size _size = Size(267, 600);
  static const Rect _screen = Rect.fromLTWH(37, 27, 193, 145);
  static const double _radius = 20;

  @override
  String get id => color == Nano1Color.blanc ? 'nano1' : 'nano1-${color.name}';

  @override
  String get family => 'nano1';

  @override
  String get label => 'Nano 1G';

  @override
  String get variantName => color.displayName;

  @override
  Color get swatch => color.swatch;

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => _screen;

  /// En bas à gauche, à côté du connecteur dock.
  @override
  double get jackX => 46;

  @override
  bool get jackOnTop => false;

  /// En haut à droite.
  @override
  HoldSwitch? get hold => const HoldSwitch(206);

  @override
  Offset get wheelCenter => const Offset(133.5, 350);

  @override
  WheelStyle get wheel => switch (color) {
    // Molette gris clair, inscriptions blanches, bouton central blanc.
    Nano1Color.blanc => const WheelStyle(
      radius: 104,
      buttonRadius: 47,
      iconScale: 0.7,
      labelSize: 12,
      labelSpacing: 0.8,
      label: Color(0xFFF7F8F9),
      recess: Color(0xFFDDDEE0),
      ring: [Color(0xFFCDCED3), Color(0xFFC3C5CA), Color(0xFFB8BAC0)],
      edgeLight: 0.4,
      groove: Color(0xFFAAADB2),
    ),
    // Molette gris anthracite, bouton central noir.
    Nano1Color.noir => const WheelStyle(
      radius: 104,
      buttonRadius: 47,
      iconScale: 0.7,
      labelSize: 12,
      labelSpacing: 0.8,
      label: Color(0xFFC9CBCE),
      recess: Color(0xFF0E0F10),
      ring: [Color(0xFF6E7074), Color(0xFF5E6064), Color(0xFF4E5054)],
      edgeLight: 0.18,
      groove: Color(0xFF111214),
      buttonUp: [Color(0xFF3A3B3E), Color(0xFF1F2022)],
      buttonDown: [Color(0xFF1C1D1F), Color(0xFF2C2D30)],
    ),
  };

  @override
  ScreenLook get look => const ClassicLook(ui: ColorUi.video);

  @override
  CustomPainter get body => switch (color) {
    Nano1Color.blanc => const _WhiteBodyPainter(_size, _radius, _screen, rim: 2.5),
    Nano1Color.noir => const _WhiteBodyPainter(
      _size,
      _radius,
      _screen,
      rim: 2.5,
      front: [Color(0xFF2E2F32), Color(0xFF1B1C1E), Color(0xFF111213)],
    ),
  };

  @override
  CustomPainter? get glass => const _GlassPainter(_size, _radius, _screen);

  @override
  Size get windowSize => const Size(360, 720);

  @override
  bool operator ==(Object other) => other is Nano1Model && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

// --- Boîtier blanc à dos chromé -------------------------------------------------

class _WhiteBodyPainter extends CustomPainter {
  const _WhiteBodyPainter(this.bodySize, this.radius, this.screen, {this.front = _ivory, this.rim = 3.5});

  final Size bodySize;

  /// Épaisseur du dos chromé visible autour de la façade.
  final double rim;
  final double radius;
  final Rect screen;

  /// Dégradé de la façade, de haut en bas.
  final List<Color> front;

  static const _ivory = [Color(0xFFFDFDFB), Color(0xFFF3F3F0), Color(0xFFE8E8E4)];

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.drawRRect(
      outer.shift(const Offset(0, 26)).deflate(10),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.drawRRect(
      outer.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // Dos en acier poli, visible tout autour.
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
    // Façade en plastique blanc, un peu plus ivoire que le Classic.
    final front = outer.deflate(rim);
    canvas.drawRRect(
      front,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), this.front, const [0, 0.55, 1]),
    );
    canvas.drawRRect(
      front.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: 0.07),
    );
    // Écran monochrome dans un cadre gris foncé.
    final frame = RRect.fromRectAndRadius(screen.inflate(9), const Radius.circular(7));
    canvas.drawRRect(frame.inflate(1), Paint()..color = const Color(0xFFD2D3D5));
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF34373B));
  }

  @override
  bool shouldRepaint(covariant _WhiteBodyPainter old) =>
      old.screen != screen || old.radius != radius || old.front != front || old.rim != rim;
}

class _GlassPainter extends CustomPainter {
  const _GlassPainter(this.bodySize, this.radius, this.screen);

  final Size bodySize;
  final double radius;
  final Rect screen;

  @override
  void paint(Canvas canvas, Size size) {
    final front = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(3.5);
    canvas.save();
    canvas.clipRRect(front);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width * 0.78, 0)
        ..lineTo(0, size.height * 0.36)
        ..close(),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width * 0.4, size.height * 0.24),
          [Colors.white.withValues(alpha: 0.2), Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0)],
          const [0, 0.7, 1],
        ),
    );
    // L'écran est en retrait sous la façade.
    canvas.drawRect(
      Rect.fromLTWH(screen.left, screen.top, screen.width, 7),
      Paint()
        ..shader = ui.Gradient.linear(
          screen.topLeft,
          screen.topLeft + const Offset(0, 7),
          [Colors.black.withValues(alpha: 0.22), Colors.black.withValues(alpha: 0)],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// --- Boutons rétroéclairés de la 3e génération --------------------------------

class _BacklitButtonPainter extends CustomPainter {
  const _BacklitButtonPainter(this.zone, this.pressed);

  final WheelZone zone;
  final bool pressed;

  static const _glow = Color(0xFFFF6A1E);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // Bague grise, puis touche blanche légèrement bombée.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFC9CCD0));
    canvas.drawCircle(
      c,
      r - 2.5,
      Paint()
        ..shader = ui.Gradient.linear(
          c.translate(0, -r),
          c.translate(0, r),
          pressed ? const [Color(0xFFE2E4E7), Color(0xFFF2F3F4)] : const [Color(0xFFFFFFFF), Color(0xFFEDEEF0)],
        ),
    );
    // Inscription éclairée par-dessous : un halo, puis le trait net.
    for (final glow in [true, false]) {
      final ink = Paint()
        ..color = glow ? _glow.withValues(alpha: 0.55) : _glow
        ..maskFilter = glow ? const MaskFilter.blur(BlurStyle.normal, 3) : null;
      _symbol(canvas, c, r, ink);
    }
  }

  void _symbol(Canvas canvas, Offset c, double r, Paint ink) {
    final k = r / 27;
    switch (zone) {
      case WheelZone.menu:
        final tp = TextPainter(
          text: TextSpan(
            text: 'MENU',
            style: TextStyle(
              fontFamily: 'Noto Sans',
              fontSize: 11 * k,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              foreground: ink,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      case WheelZone.next || WheelZone.previous:
        final dir = zone == WheelZone.next ? 1.0 : -1.0;
        final h = 7 * k;
        final w = 7 * k;
        for (final dx in [-w, 0.0]) {
          final x0 = c.dx + dx * dir;
          canvas.drawPath(
            Path()
              ..moveTo(x0, c.dy - h)
              ..lineTo(x0 + w * dir, c.dy)
              ..lineTo(x0, c.dy + h)
              ..close(),
            ink,
          );
        }
        final bar = c.dx + w * dir;
        canvas.drawRect(
          Rect.fromLTRB(math.min(bar, bar + 2 * k * dir), c.dy - h, math.max(bar, bar + 2 * k * dir), c.dy + h),
          ink,
        );
      case WheelZone.playPause:
        final h = 6.5 * k;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - 10 * k, c.dy - h)
            ..lineTo(c.dx + 1 * k, c.dy)
            ..lineTo(c.dx - 10 * k, c.dy + h)
            ..close(),
          ink,
        );
        canvas.drawRect(Rect.fromLTWH(c.dx + 3.5 * k, c.dy - h, 2.5 * k, h * 2), ink);
        canvas.drawRect(Rect.fromLTWH(c.dx + 8.5 * k, c.dy - h, 2.5 * k, h * 2), ink);
      case WheelZone.center || WheelZone.none:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _BacklitButtonPainter old) => old.pressed != pressed || old.zone != zone;
}
