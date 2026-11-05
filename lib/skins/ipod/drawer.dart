import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'model.dart';
import 'nav.dart';
import 'wheel.dart';

/// Épaisseur de la façade du tiroir (celle qui porte la poignée) : c'est
/// elle qui dépasse du bord de la fenêtre quand on l'approche.
const double drawerFront = 26;

/// Le tiroir sorti du bord droit de la fenêtre : cadre en noyer, fond en
/// feutrine, un emplacement par modèle. Celui de l'appareil en main est vide.
class IpodDrawer extends StatelessWidget {
  const IpodDrawer({
    super.key,
    required this.models,
    required this.current,
    required this.contentWidth,
    required this.onPick,
    required this.onFront,
  });

  final List<IpodModel> models;
  final IpodModel current;

  /// Largeur utile (les emplacements) ; le bois se prolonge au-delà.
  final double contentWidth;
  final ValueChanged<IpodModel> onPick;

  /// Clic sur la façade (ouvrir / fermer).
  final VoidCallback onFront;

  static const double _wall = 14;
  static const int _columns = 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final inner = Rect.fromLTRB(drawerFront, _wall, box.maxWidth, box.maxHeight - _wall);
      final slots = Rect.fromLTRB(inner.left, inner.top, contentWidth, inner.bottom);
      final rows = (models.length / _columns).ceil();
      final cell = Size(slots.width / _columns, slots.height / rows);
      const plate = 18.0;
      // Même échelle pour tous : les tailles relatives sont celles des vrais.
      final biggest = models.map((m) => m.size).reduce((a, b) => Size(math.max(a.width, b.width), math.max(a.height, b.height)));
      final scale = math.min((cell.width - 28) / biggest.width, (cell.height - plate - 26) / biggest.height);

      return Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _TrayPainter(inner: inner))),
          for (var i = 0; i < models.length; i++)
            Positioned(
              left: slots.left + (i % _columns) * cell.width,
              top: slots.top + (i ~/ _columns) * cell.height,
              width: cell.width,
              height: cell.height,
              child: _Slot(
                model: models[i],
                scale: scale,
                empty: models[i].id == current.id,
                onTap: () => onPick(models[i]),
              ),
            ),
          // Façade : clic pour ouvrir ou refermer.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: drawerFront,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onFront,
              child: const MouseRegion(cursor: SystemMouseCursors.click),
            ),
          ),
        ],
      );
    });
  }
}

class _Slot extends StatefulWidget {
  const _Slot({required this.model, required this.scale, required this.empty, required this.onTap});

  final IpodModel model;
  final double scale;
  final bool empty;
  final VoidCallback onTap;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final size = m.size * widget.scale;
    final radius = m.cornerRadius * widget.scale;
    final lifted = _hover && !widget.empty;

    final device = AnimatedScale(
      scale: lifted ? 1.07 : 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: lifted ? 0.55 : 0.45),
              blurRadius: lifted ? 18 : 4,
              offset: Offset(0, lifted ? 12 : 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox.fromSize(size: size, child: FittedBox(child: IpodPreview(model: m))),
        ),
      ),
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        MouseRegion(
          cursor: widget.empty ? MouseCursor.defer : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.empty ? null : widget.onTap,
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Empreinte creusée dans la feutrine.
                  Positioned.fill(child: CustomPaint(painter: _ImprintPainter(radius))),
                  if (!widget.empty) Positioned.fill(child: device),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        _Plate(m.label),
      ],
    );
  }
}

/// Petite plaque de laiton gravée sous chaque emplacement.
class _Plate extends StatelessWidget {
  const _Plate(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE9D9A6), Color(0xFFC8AE68), Color(0xFFA88C4A)],
        ),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Noto Sans',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Color(0xFF4A3A16),
          shadows: [Shadow(color: Color(0x66FFFFFF), offset: Offset(0, 0.6))],
        ),
      ),
    );
  }
}

/// L'appareil en miniature, figé sur son menu principal.
class IpodPreview extends StatelessWidget {
  const IpodPreview({super.key, required this.model});

  final IpodModel model;

  static final _entries = [
    MenuEntry('Musique', open: NowPlayingPage.new),
    const MenuEntry('Morceau au hasard'),
    MenuEntry('En lecture', open: NowPlayingPage.new),
  ];

  @override
  Widget build(BuildContext context) {
    final m = model;
    final look = m.look;
    final glass = m.glass;
    return SizedBox.fromSize(
      size: m.size,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: m.body)),
          Positioned.fromRect(
            rect: m.screen,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(m.screenCornerRadius),
              child: FittedBox(
                child: SizedBox.fromSize(
                  size: look.size,
                  child: DefaultTextStyle(
                    style: look.textStyle,
                    child: ColoredBox(
                      color: look.background,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          look.statusBar(title: 'Lecteur', playing: false, hasTrack: false),
                          for (var i = 0; i < _entries.length; i++)
                            SizedBox(
                              height: look.rowHeight,
                              child: Stack(
                                children: [
                                  if (i == 0) Positioned.fill(child: look.highlight()),
                                  Positioned.fill(child: look.row(_entries[i], selected: i == 0)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (glass != null) Positioned.fill(child: CustomPaint(painter: glass)),
          Positioned.fromRect(
            rect: Rect.fromCircle(center: m.wheelCenter, radius: m.wheel.radius),
            child: CustomPaint(painter: WheelPainter(m.wheel, WheelZone.none)),
          ),
        ],
      ),
    );
  }
}

// --- Bois et feutrine --------------------------------------------------------------

class _TrayPainter extends CustomPainter {
  const _TrayPainter({required this.inner});

  final Rect inner;

  static const _walnut = [Color(0xFF6B4226), Color(0xFF7E4F2D), Color(0xFF5A361E)];

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    final outer = RRect.fromRectAndCorners(all, topLeft: const Radius.circular(10), bottomLeft: const Radius.circular(10));

    // Ombre portée du tiroir vers la gauche.
    canvas.drawRRect(
      outer.shift(const Offset(-6, 10)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // Parois en noyer, avec un veinage horizontal.
    canvas.save();
    canvas.clipRRect(outer);
    canvas.drawRect(
      all,
      Paint()
        ..shader = ui.Gradient.linear(all.topLeft, all.bottomLeft, _walnut, const [0, 0.5, 1]),
    );
    final rnd = math.Random(5);
    final grain = Paint()..style = PaintingStyle.stroke;
    for (var k = 0; k < 140; k++) {
      final y = rnd.nextDouble() * size.height;
      final path = Path()..moveTo(0, y);
      final amp = 1 + rnd.nextDouble() * 3;
      final f = 0.004 + rnd.nextDouble() * 0.01;
      final ph = rnd.nextDouble() * 6;
      for (var x = 0.0; x <= size.width; x += 8) {
        path.lineTo(x, y + amp * math.sin(x * f + ph));
      }
      grain
        ..strokeWidth = 0.6 + rnd.nextDouble() * 1.4
        ..color = const Color(0xFF2A160A).withValues(alpha: 0.08 + rnd.nextDouble() * 0.14);
      canvas.drawPath(path, grain);
    }
    // Façade un peu plus claire, arête vive éclairée.
    final front = Rect.fromLTWH(0, 0, drawerFront, size.height);
    canvas.drawRect(front, Paint()..color = Colors.white.withValues(alpha: 0.06));
    canvas.drawLine(
      Offset(drawerFront - 0.5, inner.top),
      Offset(drawerFront - 0.5, inner.bottom),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );
    canvas.restore();

    // Poignée de laiton sur la façade.
    final pull = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(drawerFront / 2, size.height / 2), width: 8, height: 64),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      pull.shift(const Offset(1.5, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRRect(
      pull,
      Paint()
        ..shader = ui.Gradient.linear(
          pull.outerRect.centerLeft,
          pull.outerRect.centerRight,
          const [Color(0xFF8C6F33), Color(0xFFF1DFA5), Color(0xFFB8994F), Color(0xFF7A5E28)],
          const [0, 0.35, 0.7, 1],
        ),
    );

    // Fond en feutrine, dans l'ombre des parois.
    canvas.drawRect(inner, Paint()..color = const Color(0xFF262A31));
    final fuzz = math.Random(9);
    final dots = <Offset>[
      for (var i = 0; i < (inner.width * inner.height / 26).round(); i++)
        Offset(inner.left + fuzz.nextDouble() * inner.width, inner.top + fuzz.nextDouble() * inner.height),
    ];
    canvas.drawPoints(
      ui.PointMode.points,
      dots,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..strokeWidth = 1.2,
    );
    // Ombre intérieure le long des parois.
    for (final (edge, from, to) in [
      (Rect.fromLTWH(inner.left, inner.top, inner.width, 18), inner.topCenter, inner.topCenter + const Offset(0, 18)),
      (Rect.fromLTWH(inner.left, inner.top, 18, inner.height), inner.centerLeft, inner.centerLeft + const Offset(18, 0)),
      (Rect.fromLTWH(inner.left, inner.bottom - 10, inner.width, 10), inner.bottomCenter, inner.bottomCenter - const Offset(0, 10)),
    ]) {
      canvas.drawRect(
        edge,
        Paint()
          ..shader = ui.Gradient.linear(from, to, [Colors.black.withValues(alpha: 0.5), Colors.black.withValues(alpha: 0)]),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrayPainter old) => old.inner != inner;
}

/// Creux en forme d'appareil dans la feutrine.
class _ImprintPainter extends CustomPainter {
  const _ImprintPainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius((Offset.zero & size).inflate(3), Radius.circular(radius + 3));
    canvas.drawRRect(r, Paint()..color = const Color(0xFF1B1E23));
    canvas.save();
    canvas.clipRRect(r);
    // Ombre en haut à gauche, lumière en bas à droite : c'est un creux.
    canvas.drawRRect(
      r.shift(const Offset(3, 4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          r.outerRect.topLeft,
          r.outerRect.bottomRight,
          [Colors.black.withValues(alpha: 0.5), Colors.white.withValues(alpha: 0.10)],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _ImprintPainter old) => old.radius != radius;
}
