import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'look.dart';
import 'mini.dart';
import 'model.dart';
import 'wheel.dart';

/// Écran monochrome des premières générations : 160 × 128, 6 lignes.
const _monoLook = MiniLook(size: Size(160, 128), visibleRows: 6);

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

  /// À droite sur la tranche du haut (le port FireWire est à gauche).
  @override
  double get jackX => 318;

  @override
  Offset get wheelCenter => const Offset(206, 470);

  @override
  WheelStyle get wheel => const WheelStyle(
        radius: 132,
        buttonRadius: 42,
        innerRadius: 94,
        labelInset: 0.86,
        labelSize: 13,
        labelSpacing: 1,
        iconScale: 0.75,
        label: Color(0xFF9A9EA3),
        ring: [Color(0xFFF4F5F6), Color(0xFFE6E8EA), Color(0xFFD8DBDE)],
        inner: [Color(0xFFFBFBFC), Color(0xFFEEEFF1), Color(0xFFDFE1E4)],
        groove: Color(0xFFB9BCC0),
      );

  @override
  ScreenLook get look => _monoLook;

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
  static const Rect _screen = Rect.fromLTWH(76, 40, 260, 208);
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

  /// À droite sur la tranche du haut, à côté de la prise télécommande.
  @override
  double get jackX => 322;

  @override
  Offset get wheelCenter => const Offset(206, 506);

  @override
  WheelStyle get wheel => const WheelStyle(
        radius: 122,
        buttonRadius: 42,
        labels: false,
        sideClicks: false,
        ring: [Color(0xFFF1F2F3), Color(0xFFE5E7E9), Color(0xFFD9DCDF)],
      );

  @override
  List<IpodButton> get buttons => const [
        IpodButton(WheelZone.previous, Offset(83, 304), 27),
        IpodButton(WheelZone.menu, Offset(165, 304), 27),
        IpodButton(WheelZone.playPause, Offset(247, 304), 27),
        IpodButton(WheelZone.next, Offset(329, 304), 27),
      ];

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

// --- Boîtier blanc à dos chromé -------------------------------------------------

class _WhiteBodyPainter extends CustomPainter {
  const _WhiteBodyPainter(this.bodySize, this.radius, this.screen);

  final Size bodySize;
  final double radius;
  final Rect screen;

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
    final front = outer.deflate(3.5);
    canvas.drawRRect(
      front,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          const [Color(0xFFFDFDFB), Color(0xFFF3F3F0), Color(0xFFE8E8E4)],
          const [0, 0.55, 1],
        ),
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
  bool shouldRepaint(covariant _WhiteBodyPainter old) => old.screen != screen || old.radius != radius;
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
