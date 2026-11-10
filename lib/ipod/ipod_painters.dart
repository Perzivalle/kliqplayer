part of 'ipod.dart';

/// Peintre qui recalcule la prise au moment de peindre, une fois toute la
/// mise en page (et les transformations de l'appareil) connue.
class _LiveJackPainter extends CustomPainter {
  const _LiveJackPainter(this.build);

  final JackPainter Function() build;

  @override
  void paint(Canvas canvas, Size size) => build().paint(canvas, size);

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

/// Le curseur du verrou, qui dépasse à peine de la tranche.
class HoldPainter extends CustomPainter {
  const HoldPainter(this.hold, {this.on = false});

  final HoldSwitch hold;

  /// Poussé : le curseur se décale et découvre la marque orange.
  final bool on;

  static const _orange = Color(0xFFF2861A);

  /// Ce qui dépasse de la tranche.
  static const double depth = 3;

  @override
  void paint(Canvas canvas, Size size) {
    // Vers l'extérieur de l'appareil : le haut pour un verrou du haut.
    if (!hold.onTop) {
      canvas.translate(0, size.height);
      canvas.scale(1, -1);
    }
    final w = size.width, h = size.height;
    switch (hold.kind) {
      case HoldKind.pin:
        // Demi-perle de métal poli, avec son reflet.
        final dome = Rect.fromLTWH(0, 0, w, h * 2);
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, w, h + 0.5));
        canvas.drawOval(
          dome,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.6),
              radius: 0.9,
              colors: hold.knob ?? const [Color(0xFFFFFFFF), Color(0xFFC3C7CC), Color(0xFF7D8287)],
              stops: const [0, 0.45, 1],
            ).createShader(dome),
        );
        canvas.restore();
        if (on) canvas.drawRect(Rect.fromLTWH(-3, h - 1.4, 3, 1.9), Paint()..color = _orange);
      case HoldKind.plastic || HoldKind.metal:
        final shift = on ? w * 0.3 : 0.0;
        if (on) canvas.drawRect(Rect.fromLTWH(0.5, h * 0.45, shift, h * 0.55 + 0.5), Paint()..color = _orange);
        final knob = RRect.fromRectAndCorners(
          Rect.fromLTWH(shift, 0, w - shift, h + 0.5),
          topLeft: const Radius.circular(1.5),
          topRight: const Radius.circular(1.5),
        );
        final colors =
            hold.knob ??
            (hold.kind == HoldKind.metal
                ? const [Color(0xFFE9EBED), Color(0xFFA3A7AC), Color(0xFFD5D8DB)]
                : const [Color(0xFFFFFFFF), Color(0xFFE3E5E7), Color(0xFFC7CACE)]);
        canvas.drawRRect(
          knob,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ).createShader(knob.outerRect),
        );
        canvas.drawRRect(
          knob,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6
            ..color = Colors.black.withValues(alpha: 0.25),
        );
    }
  }

  @override
  bool shouldRepaint(covariant HoldPainter old) => old.hold != hold || old.on != on;
}

/// Ne laisse voir que ce qui est au-delà de [x], du côté où sort le tiroir.
class _SideClip extends CustomClipper<Rect> {
  const _SideClip(this.x, this.right);

  final double x;
  final bool right;

  @override
  Rect getClip(Size size) =>
      right ? Rect.fromLTRB(x, -1e4, size.width + 1e4, 1e4) : Rect.fromLTRB(-1e4, -1e4, x, 1e4);

  @override
  bool shouldReclip(_SideClip old) => old.x != x || old.right != right;
}

/// Poignée du tiroir : une languette d'aluminium microbillé, arrondie du
/// côté qui dépasse, avec une encoche pour le doigt.
class _HandlePainter extends CustomPainter {
  const _HandlePainter(this.side, {this.arrow = false});

  /// 1 : elle dépasse à droite ; -1 : à gauche.
  final int side;

  /// Une flèche gravée vers l'extérieur au lieu de l'encoche (bouton qui
  /// déplace l'iPod).
  final bool arrow;

  @override
  void paint(Canvas canvas, Size size) {
    if (side < 0) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final r = Offset.zero & size;
    final shape = RRect.fromRectAndCorners(
      r,
      topRight: const Radius.circular(9),
      bottomRight: const Radius.circular(9),
    );
    canvas.drawRRect(
      shape.shift(const Offset(1, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = ui.Gradient.linear(
          r.topCenter,
          r.bottomCenter,
          const [Color(0xFFE2E5E8), Color(0xFFC6CACE), Color(0xFFA9AEB3)],
          const [0, 0.5, 1],
        ),
    );
    // Arête : un filet de lumière en haut, plus sombre en bas.
    canvas.drawRRect(
      shape.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = ui.Gradient.linear(
          r.topCenter,
          r.bottomCenter,
          [Colors.white.withValues(alpha: 0.9), Colors.black.withValues(alpha: 0.2)],
        ),
    );
    if (arrow) {
      // Chevron gravé : un trait sombre, doublé d'un reflet en dessous.
      final c = Offset(size.width - 11, size.height / 2);
      final path = Path()
        ..moveTo(c.dx - 3, c.dy - 5)
        ..lineTo(c.dx + 2, c.dy)
        ..lineTo(c.dx - 3, c.dy + 5);
      Paint stroke() => Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      // Même teinte que l'encoche de l'autre poignée.
      final ink = stroke()
        ..shader = ui.Gradient.linear(
          Offset(c.dx - 4, c.dy),
          Offset(c.dx + 3, c.dy),
          const [Color(0xFF7C8085), Color(0xFFD2D5D8)],
        );
      canvas
        ..drawPath(path.shift(const Offset(0, 1)), stroke()..color = Colors.white.withValues(alpha: 0.7))
        ..drawPath(path, ink);
      return;
    }
    // Encoche pour le doigt, près du bout.
    final notch = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width - 8, size.height / 2), width: 4, height: size.height * 0.5),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      notch,
      Paint()
        ..shader = ui.Gradient.linear(
          notch.outerRect.centerLeft,
          notch.outerRect.centerRight,
          const [Color(0xFF7C8085), Color(0xFFD2D5D8)],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _HandlePainter old) => old.side != side || old.arrow != arrow;
}

/// Voyant d'état d'un shuffle, sur la tranche du haut : éteint, ou vert vif
/// avec son halo.
class _LedPainter extends CustomPainter {
  const _LedPainter(this.on);

  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 3);
    if (on) {
      canvas.drawCircle(
        c,
        7,
        Paint()
          ..color = const Color(0xAA4CFF6A)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawCircle(c, 2.6, Paint()..color = on ? const Color(0xFFB8FFC4) : const Color(0xFF3B4A3E));
  }

  @override
  bool shouldRepaint(covariant _LedPainter old) => old.on != on;
}
