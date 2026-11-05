import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Grande table en noyer qui remplit la fenêtre, éclairée par une lampe
/// au-dessus du centre. [unit] : pixels par unité de la scène, pour que les
/// planches gardent la même taille relative que les objets posés dessus.
class TablePainter extends CustomPainter {
  const TablePainter(this.unit);

  final double unit;

  static const _woods = [
    [Color(0xFF6E4527), Color(0xFF5C3920)],
    [Color(0xFF7A4E2C), Color(0xFF653F22)],
    [Color(0xFF654024), Color(0xFF52331C)],
    [Color(0xFF73492A), Color(0xFF5F3C21)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final plankH = 190 * unit;
    final plankL = 1500 * unit;
    final rows = (size.height / plankH).ceil() + 1;
    // Planches centrées verticalement pour que le motif reste stable.
    final y0 = size.height / 2 - rows / 2 * plankH;
    for (var row = 0; row < rows; row++) {
      final y = y0 + row * plankH;
      final rnd = math.Random(row * 977 + 3);
      var x = -rnd.nextDouble() * plankL;
      var col = 0;
      while (x < size.width) {
        _plank(canvas, Rect.fromLTWH(x, y, plankL, plankH), row * 31 + col);
        x += plankL;
        col++;
      }
    }

    final full = Offset.zero & size;
    final c = size.center(Offset.zero);
    final r = math.max(size.width, size.height) * 0.75;

    // Lampe : centre chaud et clair, bords dans l'ombre.
    canvas.drawRect(
      full,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r,
          [
            const Color(0xFFFFD9A0).withValues(alpha: 0.13),
            const Color(0xFFFFD9A0).withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.35),
            Colors.black.withValues(alpha: 0.6),
          ],
          const [0, 0.45, 0.85, 1],
        ),
    );
    // Reflet satiné du vernis.
    canvas.drawRect(
      full,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.15, 0),
          Offset(size.width * 0.55, size.height),
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0),
          ],
          const [0.3, 0.5, 0.7],
        ),
    );
  }

  void _plank(Canvas canvas, Rect rect, int seed) {
    final rnd = math.Random(seed);
    final wood = _woods[rnd.nextInt(_woods.length)];
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [wood[0], wood[1], wood[0]], const [0, 0.6, 1]),
    );

    // Veinage : longues lignes ondulées, plus ou moins marquées.
    final grain = Paint()..style = PaintingStyle.stroke;
    final step = math.max(10.0, 18 * unit);
    for (var k = 0; k < 46; k++) {
      final y = rect.top + rnd.nextDouble() * rect.height;
      final amp = (2 + rnd.nextDouble() * 9) * unit;
      final freq = (0.0015 + rnd.nextDouble() * 0.004) / unit;
      final phase = rnd.nextDouble() * 6;
      final drift = (rnd.nextDouble() - 0.5) * rect.height * 0.25 / rect.width;
      final path = Path()..moveTo(rect.left, y);
      for (var x = rect.left; x <= rect.right + step; x += step) {
        path.lineTo(x, y + amp * math.sin((x - rect.left) * freq + phase) + (x - rect.left) * drift);
      }
      final dark = rnd.nextDouble() < 0.8;
      grain
        ..color = (dark ? const Color(0xFF2A160A) : const Color(0xFFB07A48))
            .withValues(alpha: dark ? 0.06 + rnd.nextDouble() * 0.16 : 0.05 + rnd.nextDouble() * 0.07)
        ..strokeWidth = math.max(0.6, (0.8 + rnd.nextDouble() * 3.2) * unit);
      canvas.drawPath(path, grain);
    }

    // Un nœud de temps en temps, entouré de veines resserrées.
    if (rnd.nextDouble() < 0.45) {
      final c = Offset(
        rect.left + rect.width * (0.1 + rnd.nextDouble() * 0.8),
        rect.top + rect.height * (0.3 + rnd.nextDouble() * 0.4),
      );
      for (var k = 0; k < 6; k++) {
        canvas.drawOval(
          Rect.fromCenter(center: c, width: (110 - k * 16) * unit, height: (34 - k * 5) * unit),
          Paint()
            ..style = k == 5 ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = math.max(0.8, 2.2 * unit)
            ..color = const Color(0xFF2A160A).withValues(alpha: 0.12 + k * 0.06),
        );
      }
    }

    // Joints : rainure sombre en haut et au bout de la planche, arête claire.
    final seam = math.max(1.0, 3 * unit);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, seam), Paint()..color = const Color(0xCC1A0D05));
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top + seam, rect.width, seam),
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, seam, rect.height), Paint()..color = const Color(0xCC1A0D05));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TablePainter old) => old.unit != unit;
}
