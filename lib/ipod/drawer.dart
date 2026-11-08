import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'model.dart';
import 'screen.dart';
import 'wheel.dart';
import '../core/strings.dart';

/// Épaisseur de la façade du tiroir (celle où l'on glisse le doigt).
const double drawerFront = 26;

/// Le tiroir qui sort de derrière l'iPod : coque en aluminium, fond en
/// mousse noire, un emplacement par modèle avec ses teintes en pastilles.
/// L'emplacement du modèle en main est vide.
///
/// La façade est du côté extérieur ([frontOnRight] : il sort vers la
/// droite) ; de l'autre côté, la coque se prolonge derrière l'iPod.
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
    this.frontOnRight = false,
    this.slotKeys = const {},
    this.layoutSize,
  });

  /// Sort vers la droite : façade à droite, prolongement à gauche.
  final bool frontOnRight;

  /// Les modèles, regroupés par famille (une liste par emplacement).
  final List<List<IpodModel>> families;
  final IpodModel current;

  /// Teinte affichée dans chaque emplacement, par famille.
  final Map<String, IpodModel> shown;

  /// Largeur visible (façade et emplacements), mesurée depuis la façade ;
  /// la coque se prolonge au-delà, cachée derrière l'iPod.
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

  /// Taille pour laquelle les emplacements sont disposés (celle d'arrivée
  /// quand le tiroir change de taille) : pendant la transition, seule la
  /// coque suit la taille du moment, les emplacements ne bougent pas et
  /// gardent leurs photos au lieu d'être redessinés à chaque image.
  final Size? layoutSize;

  static const double _wall = 10;

  /// Coque, fond et emplacements pour un tiroir de taille [size].
  _Layout _layout(Size size) {
    final w = size.width;
    // Dessiné façade à gauche, puis retourné si elle est à droite.
    final inner = Rect.fromLTRB(drawerFront, _wall, w - _wall, size.height - _wall);
    final slots = frontOnRight
        ? Rect.fromLTRB(w - contentWidth, inner.top, w - drawerFront, inner.bottom)
        : Rect.fromLTRB(inner.left, inner.top, contentWidth, inner.bottom);
    // Le fond en vrai (la coque est dessinée façade à gauche puis
    // retournée) : c'est sur lui que se cale le motif de la mousse.
    final foam = frontOnRight ? Rect.fromLTRB(_wall, inner.top, w - drawerFront, inner.bottom) : inner;
    return (inner: inner, slots: slots, foam: foam);
  }

  /// Les emplacements, disposés dans [l].
  ({Widget grid, bool scrolls}) _grid(_Layout l) {
    final slots = l.slots;
    const below = 58.0; // nom gravé + pastilles
    // Même échelle pour tous : les tailles relatives sont celles des vrais.
    final all = families.expand((f) => f);
    final maxW = all.map((m) => m.size.width).reduce(math.max);
    final maxH = all.map((m) => m.size.height).reduce(math.max);
    final n = families.length;

    // Le nombre de colonnes qui donne les plus grands appareils, selon la
    // forme de la place disponible.
    double scaleFor(int columns) {
      final rows = (n / columns).ceil();
      final cellW = slots.width / columns;
      final cellH = slots.height / rows;
      return math.min((cellW - 28) / maxW, (cellH - below - 20) / maxH);
    }

    var columns = 1;
    for (var c = 2; c <= math.min(n, 4); c++) {
      if (scaleFor(c) > scaleFor(columns)) columns = c;
    }
    var scale = scaleFor(columns);

    // En dessous d'une taille où l'on vise encore facilement, on garde
    // cette taille et les emplacements défilent.
    const minDevice = 96.0; // hauteur du plus grand appareil, en pixels
    final minScale = minDevice / maxH;
    final scrolls = scale < minScale;
    if (scrolls) {
      scale = minScale;
      final fit = ((slots.width) / (maxW * minScale + 28)).floor();
      columns = fit.clamp(1, math.min(n, 4));
    }
    final rows = (n / columns).ceil();
    final cellW = slots.width / columns;
    final cellH = scrolls ? maxH * scale + below + 20 : slots.height / rows;

    final grid = SizedBox(
      width: slots.width,
      height: cellH * rows,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Qui défile avec les emplacements, calé sur le fond immobile
          // (au repos, aucun raccord) ; il déborde pour le rebond.
          if (scrolls)
            Positioned(
              left: 0,
              right: 0,
              top: -120,
              bottom: -120,
              child: _Frozen(
                child: CustomPaint(painter: _FoamPainter(origin: l.foam.topLeft - slots.topLeft + const Offset(0, 120))),
              ),
            ),
          for (var i = 0; i < n; i++)
            Positioned(
              left: (i % columns) * cellW,
              top: (i ~/ columns) * cellH,
              width: cellW,
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
        ],
      ),
    );
    return (grid: grid, scrolls: scrolls);
  }

  @override
  Widget build(BuildContext context) {
    // Construits une fois ici (hors du LayoutBuilder) : quand seule la
    // taille du tiroir change, le LayoutBuilder rend le même widget et
    // Flutter ne reconstruit pas les emplacements.
    final fixed = layoutSize == null ? null : _grid(_layout(layoutSize!));
    return LayoutBuilder(builder: (context, box) {
      final l = _layout(box.biggest);
      final (:grid, :scrolls) = fixed ?? _grid(l);
      final inner = l.inner, slots = l.slots, foam = l.foam;

      return Stack(
        children: [
          Positioned.fill(
            // L'ombre du tiroir déborde à gauche.
            // Clé par côté : la photo n'est jamais refaite quand le dessin
            // change (voir [_Frozen]), il faut un nouveau [_Frozen].
            child: _Frozen(
              key: ValueKey(('coque', frontOnRight)),
              overflow: 64,
              child: CustomPaint(painter: _TrayPainter(inner: inner, mirrored: frontOnRight)),
            ),
          ),
          Positioned.fromRect(
            rect: foam,
            child: _Frozen(key: ValueKey(('mousse', frontOnRight)), child: CustomPaint(painter: _FoamPainter(radius: 4))),
          ),
          Positioned.fromRect(
            rect: slots,
            // (Plus petit que la grille pendant que le tiroir grandit : coupé.)
            child: ClipRect(child: scrolls ? _ScrollingSlots(child: grid) : OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              child: grid,
            )),
          ),
          Positioned.fromRect(
            rect: foam,
            child: IgnorePointer(
              child: _Frozen(
                key: ValueKey(('parois', frontOnRight)),
                child: CustomPaint(painter: _WallShadowPainter(frontOnRight: frontOnRight)),
              ),
            ),
          ),
          // Façade : clic pour ouvrir ou refermer.
          Positioned(
            left: frontOnRight ? null : 0,
            right: frontOnRight ? 0 : null,
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

typedef _Layout = ({Rect inner, Rect slots, Rect foam});

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
  /// Pointeur sur l'appareil (il se soulève).
  bool _hover = false;

  /// Pointeur dans l'emplacement : les pastilles apparaissent.
  bool _inside = false;

  /// Teinte survolée : l'appareil la prend le temps du survol.
  IpodModel? _preview, _ghostModel;

  @override
  Widget build(BuildContext context) {
    final empty = widget.shown.family == widget.current.family;
    final selected = empty ? widget.current : widget.shown;
    // Vide, il garde la dernière teinte survolée pendant qu'elle s'efface.
    if (empty && _preview != null) _ghostModel = _preview;
    final m = empty ? (_preview ?? _ghostModel ?? widget.shown) : (_preview ?? widget.shown);
    // L'emplacement vide montre la teinte survolée en transparence.
    final ghost = empty && _preview != null && _preview!.id != widget.current.id;
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
              child: _Frozen(
                key: ValueKey(m.id),
                child: FittedBox(child: IpodPreview(model: m)),
              ),
            ),
          ),
        ),
      ),
    );

    final swatches = _inside && widget.variants.length > 1;
    return MouseRegion(
      onEnter: (_) => setState(() => _inside = true),
      onExit: (_) => setState(() {
        _inside = false;
        _preview = null;
      }),
      child: Column(
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
                    Positioned.fill(
                      child: _Frozen(overflow: 12, child: CustomPaint(painter: _ImprintPainter(radius))),
                    ),
                    if (!empty) Positioned.fill(child: device),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: ghost ? 0.55 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: ghost || empty ? device : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Engraved(tr(m.label)),
          const SizedBox(height: 10),
          // Pastilles, seulement au survol de l'emplacement : sur une ligne si
          // elles tiennent, sinon sur deux. Survolée, une teinte habille
          // l'appareil ; cliquée, elle le prend en main.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 18),
            child: widget.variants.length < 2
                ? null
                : IgnorePointer(
                    ignoring: !swatches,
                    child: AnimatedOpacity(
                      opacity: swatches ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: AnimatedSlide(
                        offset: swatches ? Offset.zero : const Offset(0, -0.25),
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 5,
                          children: [
                            for (final v in widget.variants)
                              _Swatch(
                                model: v,
                                selected: v.id == (_preview ?? selected).id,
                                onTap: () => widget.onSwatch(v),
                                onHover: (on) => setState(() {
                                  if (on) {
                                    _preview = v;
                                  } else if (_preview?.id == v.id) {
                                    _preview = null;
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Nom du modèle gravé dans la mousse.
class _Engraved extends StatelessWidget {
  const _Engraved(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    // Toujours sur une ligne : rétrécit dans une colonne étroite.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: _Frozen(overflow: 2, child: _text()),
      ),
    );
  }

  Widget _text() {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontFamily: 'Noto Sans',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 3,
        color: Colors.white.withValues(alpha: 0.5),
        shadows: const [Shadow(color: Color(0xAA000000), offset: Offset(0, -0.8))],
      ),
    );
  }
}

/// Pastille de teinte : petit disque d'aluminium anodisé.
class _Swatch extends StatefulWidget {
  const _Swatch({required this.model, required this.selected, required this.onTap, required this.onHover});

  final IpodModel model;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.model.swatch;
    return Tooltip(
      message: tr(widget.model.variantName),
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hover = true);
          widget.onHover(true);
        },
        onExit: (_) {
          setState(() => _hover = false);
          widget.onHover(false);
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.18 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: _Frozen(
              key: ValueKey(widget.selected),
              overflow: 6,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 14,
                height: 14,
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
      ),
    );
  }
}

/// Partie immobile du tiroir, peinte une fois en image puis réutilisée.
/// Impeller redessine toute la scène à chaque image ; sans cela, la moindre
/// animation (survol d'un appareil, titre qui défile) repeindrait mousse,
/// ombres floues et miniatures, bien trop lourd pour tenir 60 images/s.
/// La photo n'est refaite que si la taille change : quand le dessin change
/// (tiroir passé de l'autre côté), il faut une autre clé.
class _Frozen extends StatelessWidget {
  const _Frozen({super.key, this.overflow = 0, required this.child});

  /// Ce que le dessin déborde de son cadre (ombres) : l'image est prise
  /// sur un cadre élargi d'autant, sans changer la mise en page.
  final double overflow;
  final Widget child;

  static final _always = SnapshotController(allowSnapshotting: true);

  @override
  Widget build(BuildContext context) {
    if (overflow == 0) {
      return SnapshotWidget(controller: _always, mode: SnapshotMode.permissive, autoresize: true, child: child);
    }
    return _Bleed(
      margin: overflow,
      child: SnapshotWidget(
        controller: _always,
        mode: SnapshotMode.permissive,
        autoresize: true,
        child: Padding(padding: EdgeInsets.all(overflow), child: child),
      ),
    );
  }
}

/// Mise en page d'un enfant plus grand de [margin] de chaque côté, qui
/// déborde sans prendre plus de place.
class _Bleed extends SingleChildRenderObjectWidget {
  const _Bleed({required this.margin, super.child});

  final double margin;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBleed(margin);

  @override
  void updateRenderObject(BuildContext context, _RenderBleed renderObject) => renderObject.margin = margin;
}

class _RenderBleed extends RenderShiftedBox {
  _RenderBleed(this._margin) : super(null);

  double _margin;
  set margin(double value) {
    if (value == _margin) return;
    _margin = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = constraints;
    final m2 = _margin * 2;
    final child = this.child;
    if (child == null) {
      size = c.smallest;
      return;
    }
    child.layout(
      BoxConstraints(
        minWidth: c.minWidth + m2,
        maxWidth: c.maxWidth + m2,
        minHeight: c.minHeight + m2,
        maxHeight: c.maxHeight + m2,
      ),
      parentUsesSize: true,
    );
    (child.parentData! as BoxParentData).offset = Offset(-_margin, -_margin);
    size = c.constrain(Size(child.size.width - m2, child.size.height - m2));
  }

  double _shrink(double v) => (v - _margin * 2).clamp(0.0, double.infinity);

  @override
  double computeMinIntrinsicWidth(double height) => _shrink(super.computeMinIntrinsicWidth(height + _margin * 2));

  @override
  double computeMaxIntrinsicWidth(double height) => _shrink(super.computeMaxIntrinsicWidth(height + _margin * 2));

  @override
  double computeMinIntrinsicHeight(double width) => _shrink(super.computeMinIntrinsicHeight(width + _margin * 2));

  @override
  double computeMaxIntrinsicHeight(double width) => _shrink(super.computeMaxIntrinsicHeight(width + _margin * 2));
}

/// L'appareil en miniature, rangé écran éteint.
class IpodPreview extends StatelessWidget {
  const IpodPreview({super.key, required this.model});

  final IpodModel model;

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
          if (m.hasScreen) Positioned.fromRect(
            rect: m.screen,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(m.screenCornerRadius),
              child: FittedBox(
                child: SizedBox.fromSize(
                  size: look.size,
                  child: ScreenOff(look: look),
                ),
              ),
            ),
          ),
          if (glass != null) Positioned.fill(child: CustomPaint(painter: glass)),
          for (final b in m.buttons)
            Positioned.fromRect(
              rect: Rect.fromCircle(center: b.center, radius: b.radius),
              child: CustomPaint(painter: m.buttonPainter(b, pressed: false)),
            ),
          Positioned.fromRect(
            rect: Rect.fromCircle(center: m.wheelCenter, radius: m.wheel.radius),
            child: CustomPaint(painter: WheelPainter(m.wheel, WheelZone.none)),
          ),
        ],
      ),
    );
  }
}

// --- Coque en aluminium et mousse -----------------------------------------

class _TrayPainter extends CustomPainter {
  const _TrayPainter({required this.inner, this.mirrored = false});

  final Rect inner;

  /// Façade à droite : tout est dessiné en miroir.
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    if (mirrored) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final all = Offset.zero & size;
    // Arrondi côté façade, plus serré au fond.
    final outer = RRect.fromRectAndCorners(
      all,
      topLeft: const Radius.circular(14),
      bottomLeft: const Radius.circular(14),
      topRight: const Radius.circular(8),
      bottomRight: const Radius.circular(8),
    );

    // Ombre portée du tiroir.
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
    canvas.drawRawPoints(
      ui.PointMode.points,
      _grain(Offset.zero & size, 30, 3),
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

    // Fond en mousse, avec le chanfrein brillant du métal tout autour.
    final foam = RRect.fromRectAndRadius(inner, const Radius.circular(4));
    canvas.drawRRect(foam.inflate(1.5), Paint()..color = const Color(0xFFF2F4F5));
    canvas.drawRRect(foam, Paint()..color = _Foam.base);
  }

  static final _grainCache = <(Rect, double, int), Float32List>{};

  /// Grains semés au hasard (toujours les mêmes pour un rectangle donné).
  static Float32List _grain(Rect r, double perDot, int seed) {
    return _grainCache.putIfAbsent((r, perDot, seed), () {
      if (_grainCache.length > 16) _grainCache.clear();
      final rnd = math.Random(seed);
      final n = (r.width * r.height / perDot).round();
      final pts = Float32List(n * 2);
      for (var i = 0; i < n; i++) {
        pts[i * 2] = r.left + rnd.nextDouble() * r.width;
        pts[i * 2 + 1] = r.top + rnd.nextDouble() * r.height;
      }
      return pts;
    });
  }

  @override
  bool shouldRepaint(covariant _TrayPainter old) => old.inner != inner || old.mirrored != mirrored;
}

/// Mousse de calage noire, comme au fond des tiroirs de servante
/// d'atelier : un charbon mat, granuleux comme du papier de verre, semé de
/// petits grains clairs qui accrochent la lumière. En carreau qui se répète
/// sans raccord visible ; généré une fois, puis posé en motif.
class _Foam {
  static const base = Color(0xFF1D1E20);
  static const _tile = 256.0;
  static const _res = 2.0; // net sur un écran HiDPI

  static final ui.Image image = _make();

  static ui.Image _make() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(_res);
    const t = _tile;
    c.drawRect(const Rect.fromLTWH(0, 0, t, t), Paint()..color = base);
    final rnd = math.Random(41);
    // Ce qui déborde d'un côté du carreau revient de l'autre : le motif se
    // raccorde.
    void wrapped(Offset p, double margin, void Function(Offset p) draw) {
      if (p.dx > margin && p.dy > margin && p.dx < t - margin && p.dy < t - margin) {
        draw(p);
        return;
      }
      for (final dx in const [-t, 0.0, t]) {
        for (final dy in const [-t, 0.0, t]) {
          draw(p + Offset(dx, dy));
        }
      }
    }

    // Très légères variations, à peine visibles : la mousse n'est pas
    // parfaitement uniforme.
    for (var i = 0; i < 16; i++) {
      final p = Offset(rnd.nextDouble() * t, rnd.nextDouble() * t);
      final r = 24 + rnd.nextDouble() * 40;
      final paint = Paint()
        ..color = rnd.nextBool() ? Colors.white.withValues(alpha: 0.018) : Colors.black.withValues(alpha: 0.12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.7);
      wrapped(p, 200, (q) => c.drawCircle(q, r, paint));
    }
    // Creux entre les grains : un peu plus noirs.
    final pit = Paint();
    for (var i = 0; i < 4000; i++) {
      final p = Offset(rnd.nextDouble() * t, rnd.nextDouble() * t);
      final r = 0.4 + rnd.nextDouble() * 0.8;
      pit.color = Colors.black.withValues(alpha: 0.15 + rnd.nextDouble() * 0.2);
      wrapped(p, 3, (q) => c.drawCircle(q, r, pit));
    }
    // Grains : serrés, minuscules, gris clair, quelques-uns plus brillants.
    final grain = Paint();
    final shade = Paint();
    for (var i = 0; i < 8000; i++) {
      final p = Offset(rnd.nextDouble() * t, rnd.nextDouble() * t);
      final u = rnd.nextDouble();
      final r = 0.22 + u * u * 0.55;
      final bright = rnd.nextInt(16) == 0;
      grain.color = Colors.white.withValues(alpha: bright ? 0.3 + rnd.nextDouble() * 0.15 : 0.06 + rnd.nextDouble() * 0.1);
      shade.color = Colors.black.withValues(alpha: 0.25);
      wrapped(p, 3, (q) {
        // Ombre du grain en bas à droite (la lumière vient d'en haut).
        if (r > 0.45) c.drawCircle(q + Offset(r * 0.6, r * 0.7), r, shade);
        c.drawCircle(q, r, grain);
      });
    }
    final size = (_tile * _res).round();
    return rec.endRecording().toImageSync(size, size);
  }

  /// Motif dont le carreau commence à [origin] (coordonnées locales).
  static Paint paint(Offset origin) {
    final m = Matrix4.identity()
      ..translateByDouble(origin.dx, origin.dy, 0, 1)
      ..scaleByDouble(1 / _res, 1 / _res, 1, 1);
    return Paint()
      ..shader = ImageShader(image, TileMode.repeated, TileMode.repeated, m.storage)
      ..filterQuality = FilterQuality.medium;
  }
}

/// La mousse, son motif calé sur [origin] : le même carreau sur le fond
/// immobile et sous les emplacements qui défilent.
class _FoamPainter extends CustomPainter {
  const _FoamPainter({this.origin = Offset.zero, this.radius = 0});

  final Offset origin;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      _Foam.paint(origin),
    );
  }

  @override
  bool shouldRepaint(covariant _FoamPainter old) => old.origin != origin || old.radius != radius;
}

/// Ombre des parois sur la mousse, par-dessus les emplacements (les
/// parois, elles, ne défilent pas). [frontOnRight] : façade à droite.
class _WallShadowPainter extends CustomPainter {
  const _WallShadowPainter({required this.frontOnRight});

  final bool frontOnRight;

  @override
  void paint(Canvas canvas, Size size) {
    final inner = Offset.zero & size;
    canvas.clipRRect(RRect.fromRectAndRadius(inner, const Radius.circular(4)));
    final side = frontOnRight
        ? (Rect.fromLTWH(inner.right - 16, inner.top, 16, inner.height), inner.centerRight, inner.centerRight - const Offset(16, 0))
        : (Rect.fromLTWH(inner.left, inner.top, 16, inner.height), inner.centerLeft, inner.centerLeft + const Offset(16, 0));
    for (final (edge, from, to) in [
      (Rect.fromLTWH(inner.left, inner.top, inner.width, 16), inner.topCenter, inner.topCenter + const Offset(0, 16)),
      side,
      (Rect.fromLTWH(inner.left, inner.bottom - 8, inner.width, 8), inner.bottomCenter, inner.bottomCenter - const Offset(0, 8)),
    ]) {
      canvas.drawRect(
        edge,
        Paint()
          ..shader = ui.Gradient.linear(from, to, [Colors.black.withValues(alpha: 0.5), Colors.black.withValues(alpha: 0)]),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WallShadowPainter old) => old.frontOnRight != frontOnRight;
}

/// Découpe en forme d'appareil dans la mousse.
class _ImprintPainter extends CustomPainter {
  const _ImprintPainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    // La découpe, un peu plus large que l'appareil.
    final hole = RRect.fromRectAndRadius(all.inflate(6), Radius.circular(radius + 6));
    // Fond de la découpe, en retrait de l'épaisseur de la paroi.
    final floor = RRect.fromRectAndRadius(all.inflate(3), Radius.circular(radius + 3));

    // Paroi : la lumière vient d'en haut, la paroi du bas la reçoit, celle
    // du haut reste dans l'ombre.
    canvas.drawRRect(
      hole,
      Paint()
        ..shader = ui.Gradient.linear(
          hole.outerRect.topCenter,
          hole.outerRect.bottomCenter,
          const [Color(0xFF050506), Color(0xFF1A1B1D), Color(0xFF3A3C40)],
          const [0, 0.55, 1],
        ),
    );
    canvas.drawRRect(floor, Paint()..color = const Color(0xFF0E0F10));
    canvas.save();
    canvas.clipRRect(floor);
    // Ombre portée par la paroi du haut sur le fond.
    canvas.drawRRect(
      floor.shift(const Offset(2, 4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = Colors.black.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ImprintPainter old) => old.radius != radius;
}

/// Emplacements trop nombreux pour la hauteur de la fenêtre : ils défilent
/// à la molette (sans barre de défilement).
class _ScrollingSlots extends StatefulWidget {
  const _ScrollingSlots({required this.child});

  final Widget child;

  @override
  State<_ScrollingSlots> createState() => _ScrollingSlotsState();
}

class _ScrollingSlotsState extends State<_ScrollingSlots> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, overscroll: false),
      child: SingleChildScrollView(
        controller: _controller,
        physics: const BouncingScrollPhysics(),
        child: widget.child,
      ),
    );
  }
}
