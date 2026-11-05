import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'model.dart';
import 'nav.dart';
import 'wheel.dart';

/// Épaisseur de la façade du tiroir (celle où l'on glisse le doigt) : c'est
/// elle qui dépasse du bord de la fenêtre quand on l'approche.
const double drawerFront = 26;

/// Le tiroir sorti du bord droit de la fenêtre : coque en aluminium, fond
/// en feutrine, un emplacement par modèle avec ses teintes en pastilles.
/// L'emplacement du modèle en main est vide.
class IpodDrawer extends StatelessWidget {
  const IpodDrawer({
    super.key,
    required this.families,
    required this.current,
    required this.shown,
    required this.contentWidth,
    required this.onPick,
    required this.onSwatch,
    required this.onFront,
    this.slotKeys = const {},
  });

  /// Les modèles, regroupés par famille (une liste par emplacement).
  final List<List<IpodModel>> families;
  final IpodModel current;

  /// Teinte affichée dans chaque emplacement, par famille.
  final Map<String, IpodModel> shown;

  /// Largeur utile (les emplacements) ; la coque se prolonge au-delà.
  final double contentWidth;

  /// Clic sur un appareil : on le prend en main.
  final ValueChanged<IpodModel> onPick;

  /// Clic sur une pastille.
  final ValueChanged<IpodModel> onSwatch;

  /// Clic sur la façade (ouvrir / fermer).
  final VoidCallback onFront;

  /// Clés posées sur la forme de chaque emplacement, par famille : la scène
  /// s'en sert pour faire voler les appareils jusqu'à leur place.
  final Map<String, GlobalKey> slotKeys;

  static const double _wall = 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final inner = Rect.fromLTRB(drawerFront, _wall, box.maxWidth, box.maxHeight - _wall);
      final slots = Rect.fromLTRB(inner.left, inner.top, contentWidth, inner.bottom);
      final cellH = slots.height / families.length;
      const below = 58.0; // nom gravé + pastilles
      // Même échelle pour tous : les tailles relatives sont celles des vrais.
      final all = families.expand((f) => f);
      final maxW = all.map((m) => m.size.width).reduce(math.max);
      final maxH = all.map((m) => m.size.height).reduce(math.max);
      final scale = math.min((slots.width - 40) / maxW, (cellH - below - 24) / maxH);

      return Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _TrayPainter(inner: inner))),
          for (var i = 0; i < families.length; i++)
            Positioned(
              left: slots.left,
              top: slots.top + i * cellH,
              width: slots.width,
              height: cellH,
              child: _Slot(
                shapeKey: slotKeys[families[i].first.family],
                variants: families[i],
                shown: shown[families[i].first.family] ?? families[i].first,
                current: current,
                scale: scale,
                onPick: onPick,
                onSwatch: onSwatch,
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
  const _Slot({
    this.shapeKey,
    required this.variants,
    required this.shown,
    required this.current,
    required this.scale,
    required this.onPick,
    required this.onSwatch,
  });

  final GlobalKey? shapeKey;
  final List<IpodModel> variants;
  final IpodModel shown;
  final IpodModel current;
  final double scale;
  final ValueChanged<IpodModel> onPick;
  final ValueChanged<IpodModel> onSwatch;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.shown;
    final empty = m.family == widget.current.family;
    final selected = empty ? widget.current : m;
    final size = m.size * widget.scale;
    final radius = m.cornerRadius * widget.scale;
    final lifted = _hover && !empty;

    final device = AnimatedScale(
      scale: lifted ? 1.06 : 1,
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
          child: SizedBox.fromSize(
            size: size,
            // Changement de teinte : fondu enchaîné.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: FittedBox(key: ValueKey(m.id), child: IpodPreview(model: m)),
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        MouseRegion(
          cursor: empty ? MouseCursor.defer : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: empty ? null : () => widget.onPick(m),
            child: SizedBox.fromSize(
              key: widget.shapeKey,
              size: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: CustomPaint(painter: _ImprintPainter(radius))),
                  if (!empty) Positioned.fill(child: device),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Engraved(m.label),
        const SizedBox(height: 10),
        SizedBox(
          height: 20,
          child: widget.variants.length < 2
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final v in widget.variants)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _Swatch(
                          model: v,
                          selected: v.id == selected.id,
                          onTap: () => widget.onSwatch(v),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Nom du modèle gravé dans la feutrine.
class _Engraved extends StatelessWidget {
  const _Engraved(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Noto Sans',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 3,
        color: Colors.white.withValues(alpha: 0.32),
        shadows: const [Shadow(color: Color(0xAA000000), offset: Offset(0, -0.8))],
      ),
    );
  }
}

/// Pastille de teinte : petit disque d'aluminium anodisé.
class _Swatch extends StatefulWidget {
  const _Swatch({required this.model, required this.selected, required this.onTap});

  final IpodModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.model.swatch;
    return Tooltip(
      message: widget.model.variantName,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.18 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(c, Colors.white, 0.45)!, c, Color.lerp(c, Colors.black, 0.2)!],
                ),
                border: Border.all(
                  color: widget.selected ? Colors.white.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.35),
                  width: widget.selected ? 2 : 1,
                ),
                boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 3, offset: Offset(0, 1.5))],
              ),
            ),
          ),
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

// --- Coque en aluminium et feutrine -----------------------------------------

class _TrayPainter extends CustomPainter {
  const _TrayPainter({required this.inner});

  final Rect inner;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    final outer = RRect.fromRectAndCorners(all, topLeft: const Radius.circular(14), bottomLeft: const Radius.circular(14));

    // Ombre portée du tiroir vers la gauche.
    canvas.drawRRect(
      outer.shift(const Offset(-6, 10)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // Aluminium microbillé : clair en haut, plus sombre en bas.
    canvas.save();
    canvas.clipRRect(outer);
    canvas.drawRect(
      all,
      Paint()
        ..shader = ui.Gradient.linear(
          all.topLeft,
          all.bottomLeft,
          const [Color(0xFFDCDFE2), Color(0xFFC6CACE), Color(0xFFAFB3B8)],
          const [0, 0.5, 1],
        ),
    );
    // Façade un peu bombée : reflet vertical.
    final front = Rect.fromLTWH(0, 0, drawerFront, size.height);
    canvas.drawRect(
      front,
      Paint()
        ..shader = ui.Gradient.linear(
          front.centerLeft,
          front.centerRight,
          [Colors.black.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.22), Colors.black.withValues(alpha: 0.06)],
          const [0, 0.4, 1],
        ),
    );
    final rnd = math.Random(3);
    final grain = <Offset>[
      for (var i = 0; i < (size.width * size.height / 30).round(); i++)
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
    ];
    canvas.drawPoints(
      ui.PointMode.points,
      grain,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.06)
        ..strokeWidth = 0.9,
    );
    canvas.restore();

    // Arête biseautée tout autour : un filet de lumière.
    canvas.drawRRect(
      outer.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = ui.Gradient.linear(
          all.topLeft,
          all.bottomLeft,
          [Colors.white.withValues(alpha: 0.9), Colors.white.withValues(alpha: 0.25)],
        ),
    );

    // Encoche pour le doigt, creusée dans la façade.
    final notch = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(drawerFront / 2, size.height / 2), width: 9, height: 72),
      const Radius.circular(4.5),
    );
    canvas.drawRRect(
      notch,
      Paint()
        ..shader = ui.Gradient.linear(
          notch.outerRect.centerLeft,
          notch.outerRect.centerRight,
          const [Color(0xFF7C8085), Color(0xFFA7ABB0), Color(0xFFD2D5D8)],
          const [0, 0.5, 1],
        ),
    );
    canvas.drawRRect(
      notch,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          notch.outerRect.topCenter,
          notch.outerRect.bottomCenter,
          [Colors.black.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0.7)],
        ),
    );

    // Fond en feutrine, avec le chanfrein brillant du métal tout autour.
    final felt = RRect.fromRectAndCorners(inner, topLeft: const Radius.circular(4), bottomLeft: const Radius.circular(4));
    canvas.drawRRect(felt.inflate(1.5), Paint()..color = const Color(0xFFF2F4F5));
    canvas.drawRRect(felt, Paint()..color = const Color(0xFF262A31));
    canvas.save();
    canvas.clipRRect(felt);
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
      (Rect.fromLTWH(inner.left, inner.top, inner.width, 16), inner.topCenter, inner.topCenter + const Offset(0, 16)),
      (Rect.fromLTWH(inner.left, inner.top, 16, inner.height), inner.centerLeft, inner.centerLeft + const Offset(16, 0)),
      (Rect.fromLTWH(inner.left, inner.bottom - 8, inner.width, 8), inner.bottomCenter, inner.bottomCenter - const Offset(0, 8)),
    ]) {
      canvas.drawRect(
        edge,
        Paint()
          ..shader = ui.Gradient.linear(from, to, [Colors.black.withValues(alpha: 0.5), Colors.black.withValues(alpha: 0)]),
      );
    }
    canvas.restore();
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
