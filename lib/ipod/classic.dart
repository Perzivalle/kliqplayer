import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart' hide RepeatMode;

import '../core/player.dart';
import 'finish.dart';
import 'look.dart';
import 'model.dart';
import 'nav.dart';
import 'wheel.dart';
import '../core/strings.dart';

/// Teintes des grands iPod à écran couleur. La 5e génération est en
/// plastique brillant, [blanc] ou [noir] ; le Classic en aluminium anodisé,
/// [argent] ou [noir] (un gris anthracite).
enum ClassicColor {
  blanc('Blanc', front: [Color(0xFFFCFCFC), Color(0xFFF8F8F8), Color(0xFFF0F0EF)], swatch: Color(0xFFF8F8F8)),
  noir('Noir', front: [Color(0xFF17191B), Color(0xFF0A0D0F), Color(0xFF050708)], swatch: Color(0xFF1B1C1E)),
  argent('Argent', front: [Color(0xFFDCDCDD), Color(0xFFD0D0D1), Color(0xFFAEAEAF)], swatch: Color(0xFFD0D0D1)),

  /// Édition U2 de la 5e génération : façade noire, molette rouge.
  u2('U2', front: [Color(0xFF17191B), Color(0xFF0A0D0F), Color(0xFF050708)], swatch: Color(0xFFCC001F));

  const ClassicColor(this.displayName, {required this.front, required this.swatch});

  final String displayName;
  final List<Color> front;
  final Color swatch;
}

/// Le Classic (2007) : façade en aluminium anodisé, liseré chromé, écran
/// couleur 320×240.
class ClassicModel extends IpodModel {
  const ClassicModel([this.color = ClassicColor.argent]);

  final ClassicColor color;

  bool get _dark => color == ClassicColor.noir;

  /// Façade anodisée, plus claire en haut : anthracite pour le noir.
  List<Color> get _front =>
      _dark ? const [Color(0xFF615E62), Color(0xFF4C4A4D), Color(0xFF2C2C2D)] : ClassicColor.argent.front;

  // « classic » tout court pour l'argent : les préférences déjà enregistrées
  // restent valables.
  @override
  String get id => _dark ? 'classic-noir' : 'classic';

  @override
  String get family => 'classic';

  @override
  String get label => 'Classic';

  @override
  String get variantName => _dark ? 'Noir' : 'Argent';

  @override
  Color get swatch => _dark ? const Color(0xFF4C4A4D) : ClassicColor.argent.swatch;

  @override
  Size get size => G.size;

  @override
  double get cornerRadius => G.radius;

  @override
  Rect get screen => G.screen;

  /// En haut à droite (le verrou est à gauche).
  @override
  double get jackX => 325;

  /// En haut à gauche : curseur métallique.
  @override
  HoldSwitch? get hold => const HoldSwitch(84, kind: HoldKind.metal);

  @override
  Offset get wheelCenter => G.wheelCenter;

  @override
  WheelStyle get wheel => _dark
      // Molette noire, inscriptions blanches, bouton anthracite creusé.
      ? const WheelStyle(
          radius: G.wheelRadius,
          buttonRadius: G.buttonRadius,
          label: Color(0xFFECECEE),
          recess: Color(0xFF111112),
          ring: [Color(0xFF272728), Color(0xFF222223), Color(0xFF1C1C1D)],
          edgeLight: 0.1,
          groove: Color(0xFF0E0E0F),
          buttonUp: [Color(0xFF333234), Color(0xFF5A575A)],
          buttonDown: [Color(0xFF262527), Color(0xFF444245)],
          buttonEdge: 0.1,
        )
      // Molette blanche, inscriptions gris bleuté, bouton argent creusé.
      : const WheelStyle(
          radius: G.wheelRadius,
          buttonRadius: G.buttonRadius,
          label: Color(0xFFB3BBC3),
          recess: Color(0xFF8E8E90),
          ring: [Color(0xFFFCFDFE), Color(0xFFF6FAFB), Color(0xFFEAEEF0)],
          groove: Color(0xFF9A9A9C),
          buttonUp: [Color(0xFFC0C0C1), Color(0xFFE0E0E1)],
          buttonDown: [Color(0xFFA9A9AA), Color(0xFFCBCBCC)],
          buttonEdge: 0.25,
        );

  @override
  ScreenLook get look => const ClassicLook();

  @override
  CustomPainter get body => BodyPainter(_front, anodized: true, dark: _dark);

  @override
  CustomPainter? get glass => const GlassPainter(G.screen, false);

  @override
  bool operator ==(Object other) => other is ClassicModel && other._dark == _dark;

  @override
  int get hashCode => _dark.hashCode;
}

/// La 5e génération « vidéo » (2005) : le format du Classic, mais une façade
/// en plastique brillant, un écran plus large au cadre noir et une molette
/// plus petite, grise.
class VideoModel extends IpodModel {
  const VideoModel([this.color = ClassicColor.blanc]);

  final ClassicColor color;

  static const Rect _screen = Rect.fromLTWH(45, 34, 322, 242);

  @override
  String get id => color == ClassicColor.blanc ? 'gen5' : 'gen5-${color.name}';

  @override
  String get family => 'gen5';

  @override
  String get label => '5e génération';

  @override
  String get variantName => color.displayName;

  @override
  Color get swatch => color.swatch;

  @override
  Size get size => G.size;

  @override
  double get cornerRadius => G.radius;

  @override
  Rect get screen => _screen;

  /// En haut à droite (le verrou est à gauche).
  @override
  double get jackX => 325;

  @override
  HoldSwitch? get hold => const HoldSwitch(84);

  @override
  Offset get wheelCenter => const Offset(206, 492);

  @override
  WheelStyle get wheel => color == ClassicColor.u2
      // Molette rouge, inscriptions claires, bouton noir.
      ? const WheelStyle(
          radius: 122,
          buttonRadius: 44,
          label: Color(0xFFF7ECEC),
          recess: Color(0xFF000000),
          ring: [Color(0xFFDD0023), Color(0xFFCC001F), Color(0xFFB0001A)],
          edgeLight: 0.22,
          groove: Color(0xFF2A0006),
          buttonUp: [Color(0xFF17151A), Color(0xFF090507)],
          buttonDown: [Color(0xFF050304), Color(0xFF100D10)],
          buttonEdge: 0.14,
        )
      : color == ClassicColor.noir
      // Molette noire, à peine plus claire que la façade, bouton noir.
      ? const WheelStyle(
          radius: 122,
          buttonRadius: 44,
          label: Color(0xFFEDEEEF),
          recess: Color(0xFF000000),
          ring: [Color(0xFF22282B), Color(0xFF1B2124), Color(0xFF14191B)],
          edgeLight: 0.12,
          groove: Color(0xFF020304),
          buttonUp: [Color(0xFF14181A), Color(0xFF080C0E)],
          buttonDown: [Color(0xFF060809), Color(0xFF101315)],
          buttonEdge: 0.14,
        )
      // Molette grise, inscriptions blanches, bouton blanc.
      : const WheelStyle(
          radius: 122,
          buttonRadius: 44,
          label: Color(0xFFFBFBFC),
          recess: Color(0xFFDFE0E2),
          ring: [Color(0xFFCBCFD2), Color(0xFFC2C6CA), Color(0xFFB8BDC1)],
          edgeLight: 0.5,
          groove: Color(0xFFADB1B5),
          buttonUp: [Color(0xFFFAFAFA), Color(0xFFF1F2F2)],
          buttonDown: [Color(0xFFDDDFE2), Color(0xFFF0F1F2)],
        );

  @override
  ScreenLook get look => const ClassicLook(ui: ColorUi.video);

  @override
  CustomPainter get body =>
      BodyPainter(color.front, frameRect: _screen.inflate(6), plastic: true, dark: color != ClassicColor.blanc);

  @override
  CustomPainter? get glass => const GlassPainter(_screen);

  @override
  bool operator ==(Object other) => other is VideoModel && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

/// Dimensions du Classic, en unités de dessin (≈ 6,67 unités par mm,
/// d'après un Classic de 61,8 × 103,5 mm).
class G {
  static const Size size = Size(412, 690);
  static const double radius = 36;

  /// Liseré chromé visible tout autour de la façade.
  static const double rim = 3;

  /// Cadre sombre autour de l'écran, puis l'écran lui-même (4:3).
  static const Rect screenFrame = Rect.fromLTWH(32, 34, 348, 261);
  static const Rect screen = Rect.fromLTWH(38, 40, 336, 252);

  static const Offset wheelCenter = Offset(206, 498);
  static const double wheelRadius = 132;
  static const double buttonRadius = 50;
}

/// Boîtier : ombre portée (il flotte), liseré chromé, façade et cadre
/// sombre de l'écran.
class BodyPainter extends CustomPainter {
  const BodyPainter(this.front, {this.frameRect = G.screenFrame, this.plastic = false, this.anodized = false, this.dark = false});

  /// Dégradé de la façade, de haut en bas.
  final List<Color> front;

  /// Façade sombre : le cadre de l'écran s'y fond.
  final bool dark;

  /// Façade en aluminium anodisé (Classic) : satinée, sans vernis.
  final bool anodized;

  /// Cadre sombre autour de l'écran.
  final Rect frameRect;

  /// Façade en plastique brillant sous une épaisse couche transparente
  /// (5e génération) : un liseré clair court au ras du chrome.
  final bool plastic;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(G.radius));

    // Ombres : une large et diffuse, une plus serrée sous l'appareil.
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

    // Liseré chromé : reflets verticaux comme un métal poli.
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

    // Façade.
    final front = outer.deflate(G.rim);
    canvas.drawRRect(
      front,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          this.front,
          const [0, 0.45, 1],
        ),
    );
    if (anodized) {
      canvas.save();
      canvas.clipRRect(front);
      // L'aluminium accroche un peu plus la lumière du côté d'où elle vient.
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.07),
          ], const [0, 0.4, 1]),
      );
      paintSatin(canvas, size, strength: dark ? 0.6 : 1);
      canvas.restore();
      // Chanfrein poli au bord de la façade.
      canvas.drawRRect(
        front.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
            Colors.white.withValues(alpha: dark ? 0.3 : 0.7),
            Colors.white.withValues(alpha: 0.1),
            Colors.black.withValues(alpha: 0.2),
          ], const [0, 0.5, 1]),
      );
    } else {
      // Arrondi de la façade : léger assombrissement au ras du chrome.
      canvas.drawRRect(
        front.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black.withValues(alpha: 0.07),
      );
    }
    if (plastic) {
      // L'épaisseur transparente du plastique, qui accroche la lumière.
      canvas.drawRRect(
        front.deflate(2.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(size.width * 0.4, size.height),
            dark
                ? [Colors.white.withValues(alpha: 0.28), Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.14)]
                : [Colors.white.withValues(alpha: 0.75), Colors.white.withValues(alpha: 0.25), Colors.white.withValues(alpha: 0.5)],
            const [0, 0.5, 1],
          ),
      );
    }

    // Cadre de l'écran.
    final frame = RRect.fromRectAndRadius(frameRect, const Radius.circular(6));
    canvas.drawRRect(
      frame.inflate(1),
      Paint()
        ..color = dark
            ? const Color(0xFF050506)
            : anodized
                ? const Color(0xFF8F8F91)
                : const Color(0xFFD5D6D8),
    );
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF1A1C1E));
  }

  @override
  bool shouldRepaint(covariant BodyPainter old) =>
      old.front != front ||
      old.frameRect != frameRect ||
      old.plastic != plastic ||
      old.anodized != anodized ||
      old.dark != dark;
}

/// Reflet de la plaque d'acrylique qui couvre toute la façade ([band] ;
/// pas sur l'aluminium du Classic, où seule la vitre de l'écran brille).
class GlassPainter extends CustomPainter {
  const GlassPainter([this.screen = G.screen, this.band = true]);

  final Rect screen;
  final bool band;

  @override
  void paint(Canvas canvas, Size size) {
    final front = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(G.radius)).deflate(G.rim);
    canvas.save();
    canvas.clipRRect(front);
    // Bande de lumière en diagonale sur le haut.
    final band = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.78, 0)
      ..lineTo(0, size.height * 0.36)
      ..close();
    if (this.band) {
      canvas.drawPath(
        band,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(size.width * 0.4, size.height * 0.24),
            [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0)],
            const [0, 0.7, 1],
          ),
      );
    }
    // L'écran sous l'acrylique : très léger voile.
    canvas.drawRect(
      screen,
      Paint()
        ..shader = ui.Gradient.linear(
          screen.topLeft,
          screen.bottomLeft,
          [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.0)],
          const [0, 0.5],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GlassPainter old) => old.screen != screen || old.band != band;
}

// --- Écran -------------------------------------------------------------------

const double _barH = 22;
const _ink = Color(0xFF111111);
const _font = 'Noto Sans';

/// Les deux interfaces des écrans couleur : celle de 2004-2006 (iPod
/// photo, 5e génération, nano 1G et 2G), et celle de 2007 (Classic, nano
/// 3G et 4G) avec ses menus scindés, Cover Flow et les albums en vignettes.
enum ColorUi { video, classic }

class ClassicLook extends ScreenLook {
  const ClassicLook({this.portrait = false, this.tall = false, this.ui = ColorUi.classic});

  /// Écran vertical, 240 × 320 (nano de 4e génération).
  final bool portrait;

  /// Écran vertical allongé, 240 × 376 (nano de 5e génération).
  final bool tall;

  final ColorUi ui;

  bool get _modern => ui == ColorUi.classic;

  @override
  double get barHeight => _barH;

  @override
  int rowsFor(MenuKind kind) => switch (kind) {
        MenuKind.tall when _modern => portrait ? (tall ? 8 : 7) : 5,
        _ => visibleRows,
      };

  @override
  double rowHeightFor(MenuKind kind) =>
      kind == MenuKind.tall && _modern ? (size.height - _barH) / rowsFor(kind) : rowHeight;

  @override
  ({Rect menu, Rect image})? split(Size screen) {
    // (Pas sur l'écran vertical du nano 4G : menu pleine largeur.)
    if (!_modern || portrait) return null;
    // L'image prend toute la hauteur : la barre de titre s'arrête à elle.
    final w = screen.width / 2;
    return (
      menu: Rect.fromLTRB(0, _barH, w, screen.height),
      image: Rect.fromLTRB(w, 0, screen.width, screen.height),
    );
  }

  @override
  Widget preview(MenuEntry entry, PlayerController player, {required bool active}) =>
      _Preview(kind: entry.preview, seed: entry.label, player: player, active: active);

  @override
  List<NowPlayingMode> get centerCycle => _modern
      ? const [NowPlayingMode.scrub, NowPlayingMode.rating, NowPlayingMode.shuffle]
      : const [NowPlayingMode.scrub, NowPlayingMode.art, NowPlayingMode.rating];

  @override
  Size get size => portrait ? Size(240, tall ? 376 : 320) : const Size(320, 240);

  @override
  double get rowHeight => 24;

  @override
  int get visibleRows => portrait ? (tall ? 14 : 12) : 9;

  @override
  double get scrollbarWidth => 9;

  @override
  TextStyle get textStyle =>
      const TextStyle(fontFamily: _font, color: _ink, fontSize: 14, fontWeight: FontWeight.w600, height: 1);

  @override
  Color get background => Colors.white;

  @override
  Color get nowPlayingBackground => portrait ? const Color(0xFF0E0F12) : background;

  @override
  bool get coverFlow => _modern;

  @override
  Widget statusBar({
    required String title,
    required bool playing,
    required bool hasTrack,
    bool nowPlaying = false,
    bool locked = false,
  }) =>
      portrait && nowPlaying
          ? _DarkStatusBar(title: title, playing: playing, hasTrack: hasTrack, locked: locked)
          : _StatusBar(title: title, playing: playing, hasTrack: hasTrack, locked: locked, modern: _modern);

  @override
  Widget highlight() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF7DBBF5), Color(0xFF3A8BE6), Color(0xFF1F6BD3)],
            stops: [0, 0.5, 1],
          ),
          border: Border(top: BorderSide(color: Color(0xFF5FA2EC)), bottom: BorderSide(color: Color(0xFF1857B3))),
        ),
      );

  @override
  Widget row(MenuEntry entry, {required bool selected, MenuKind kind = MenuKind.normal}) =>
      _Row(entry: entry, selected: selected, tall: kind == MenuKind.tall && _modern);

  @override
  CustomPainter scrollbar(double start, double extent) => _ScrollbarPainter(start, extent);

  @override
  Widget empty() => Center(
        child: Text(tr('Aucun élément'), style: const TextStyle(color: Color(0xFF8A8F95))),
      );

  @override
  Widget nowPlaying(PlayerController player, NowPlayingMode mode) =>
      portrait ? _NowPlayingPortrait(player: player, mode: mode, tall: tall) : _NowPlaying(player: player, mode: mode, modern: _modern);
}

// --- Barre de titre ----------------------------------------------------------

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.title,
    required this.playing,
    required this.hasTrack,
    required this.locked,
    required this.modern,
  });

  final String title;
  final bool playing;
  final bool hasTrack;
  final bool locked;

  /// Interface de 2007 : le titre à gauche, l'icône de lecture à côté de
  /// la batterie. Avant : le titre au milieu, l'icône à gauche.
  final bool modern;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2E6FCB);
    final text = Text(
      title,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    );
    final play = Icon(playing ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 15, color: blue);
    const lock = Icon(Icons.lock_rounded, size: 11, color: Color(0xFF4A4F55));
    return Container(
      height: _barH,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDFDFD), Color(0xFFE4E7EA), Color(0xFFCDD1D6)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF8F949A))),
      ),
      child: Stack(
        children: [
          if (modern) ...[
            Positioned.fill(
              left: 8,
              right: 38.0 + (hasTrack ? 16 : 0) + (locked ? 14 : 0),
              child: Align(alignment: Alignment.centerLeft, child: text),
            ),
            if (hasTrack) Positioned(right: 34, top: 0, bottom: 0, child: play),
            if (locked) Positioned(right: hasTrack ? 51 : 36, top: 0, bottom: 0, child: lock),
          ] else ...[
            // Entre l'icône de lecture et la batterie ; coupé par « … » si trop long.
            Positioned.fill(left: 26, right: locked ? 50 : 38, child: Center(child: text)),
            if (hasTrack) Positioned(left: 6, top: 0, bottom: 0, child: play),
            if (locked) const Positioned(right: 36, top: 0, bottom: 0, child: lock),
          ],
          const Positioned(right: 7, top: 6, child: CustomPaint(size: Size(24, 10), painter: _BatteryPainter())),
        ],
      ),
    );
  }
}

/// Barre noire de l'écran « En lecture » du nano 4G : titre blanc, l'icône
/// de lecture à côté de la batterie.
class _DarkStatusBar extends StatelessWidget {
  const _DarkStatusBar({required this.title, required this.playing, required this.hasTrack, required this.locked});

  final String title;
  final bool playing;
  final bool hasTrack;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _barH,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF55585E), Color(0xFF2C2E33), Color(0xFF17181B)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF000000))),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            left: 30,
            right: 52,
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFF2F3F5)),
              ),
            ),
          ),
          if (hasTrack)
            Positioned(
              right: 33,
              top: 0,
              bottom: 0,
              child: Icon(playing ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 15, color: const Color(0xFFE9EBEE)),
            ),
          if (locked)
            const Positioned(left: 7, top: 0, bottom: 0, child: Icon(Icons.lock_rounded, size: 11, color: Color(0xFFE9EBEE))),
          const Positioned(right: 7, top: 6, child: CustomPaint(size: Size(24, 10), painter: _BatteryPainter())),
        ],
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width - 2, size.height), const Radius.circular(2));
    canvas.drawRRect(body, Paint()..color = const Color(0xFF6B7076));
    final inner = body.deflate(1.2);
    canvas.drawRRect(
      inner,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB8F08A), Color(0xFF4FB320), Color(0xFF2F8A12)],
        ).createShader(inner.outerRect),
    );
    canvas.drawRect(Rect.fromLTWH(size.width - 2, 3, 2, size.height - 6), Paint()..color = const Color(0xFF6B7076));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.selected, this.tall = false});

  final MenuEntry entry;
  final bool selected;

  /// Ligne haute : la vignette de l'album, son titre, et l'artiste dessous.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : _ink;
    if (tall) {
      return Padding(
        padding: const EdgeInsets.only(left: 5, right: 4),
        child: LayoutBuilder(builder: (context, box) {
          final art = box.maxHeight - 8;
          return Row(
            children: [
              _Artwork(bytes: entry.art?.call(), size: art),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Marquee(entry.label, active: selected, style: TextStyle(color: color)),
                    if (entry.subtitle case final sub?) ...[
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: selected ? const Color(0xFFE3EEFB) : const Color(0xFF6A6F75),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.open != null) Icon(Icons.chevron_right_rounded, size: 18, color: color),
            ],
          );
        }),
      );
    }
    final value = entry.value?.call();
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Row(
        children: [
          Expanded(child: Marquee(entry.label, active: selected, style: TextStyle(color: color))),
          if (value != null)
            Padding(
              padding: EdgeInsets.only(left: 8, right: entry.open == null ? 4 : 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: selected ? Colors.white : const Color(0xFF6A6F75), fontWeight: FontWeight.w500),
                ),
              ),
            ),
          if (entry.checked?.call() ?? false)
            Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.check_rounded, size: 16, color: color)),
          if (entry.open != null) Icon(Icons.chevron_right_rounded, size: 18, color: color),
        ],
      ),
    );
  }
}

class _ScrollbarPainter extends CustomPainter {
  const _ScrollbarPainter(this.start, this.extent);

  final double start;
  final double extent;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Offset.zero & size;
    canvas.drawRect(
      track,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFFC9CDD2), Color(0xFFEFF1F3)]).createShader(track),
    );
    canvas.drawLine(Offset.zero, Offset(0, size.height), Paint()..color = const Color(0xFF9DA2A8));
    final h = (size.height * extent).clamp(12.0, size.height);
    final y = (size.height - h) * (start / (1 - extent)).clamp(0.0, 1.0);
    final thumb = RRect.fromRectAndRadius(Rect.fromLTWH(1.5, y + 1, size.width - 3, h - 2), const Radius.circular(3));
    canvas.drawRRect(
      thumb,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF3F8EE8), Color(0xFF7DBBF5), Color(0xFF2E78D8)])
            .createShader(thumb.outerRect),
    );
  }

  @override
  bool shouldRepaint(covariant _ScrollbarPainter old) => old.start != start || old.extent != extent;
}

// --- En lecture --------------------------------------------------------------

String _time(Duration d) {
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.player, required this.mode, required this.modern});

  final PlayerController player;
  final NowPlayingMode mode;

  /// Interface de 2007 : la pochette de biais, avec son reflet.
  final bool modern;

  @override
  Widget build(BuildContext context) {
    final track = player.current;
    if (track == null) {
      return Center(child: Text(tr('Aucun morceau')));
    }
    // La pochette en grand (bouton central, 5e génération et consorts).
    if (mode == NowPlayingMode.art) {
      return LayoutBuilder(
        builder: (context, box) => Center(child: _Artwork(bytes: player.cover, size: box.maxHeight - 14)),
      );
    }
    // Rang dans ce qui a été lancé (l'album, la liste…), comme sur un vrai
    // iPod ; rien si le morceau a été lancé ailleurs (appli Spotify).
    final position = player.queueIndex >= 0 ? trOf(player.queueIndex + 1, player.nowPlaying.length) : '';

    final art = modern ? 108.0 : 116.0;
    return Stack(
      children: [
        Positioned(
          left: 8,
          top: 5,
          child: Text(position, style: const TextStyle(fontSize: 11, color: Color(0xFF4A4F55))),
        ),
        // L'aléatoire et la répétition, s'ils sont mis.
        Positioned(right: 8, top: 4, child: _PlayIcons(player: player, color: const Color(0xFF2E6FCB), size: 13)),
        if (modern)
          Positioned(left: 12, top: 22, child: _TiltedArtwork(bytes: player.cover, size: art))
        else
          Positioned(left: 10, top: 24, child: _Artwork(bytes: player.cover, size: art)),
        Positioned(
          left: 10 + art + 12,
          right: 8,
          top: 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Marquee(track.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Marquee(track.artist, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Marquee(track.album, style: const TextStyle(fontSize: 13, color: Color(0xFF5A5F66))),
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 10,
          height: 36,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (mode) {
              NowPlayingMode.volume => _VolumeBar(key: const ValueKey('vol'), volume: player.volume / 100),
              NowPlayingMode.rating => _Stars(
                  key: const ValueKey('stars'),
                  stars: player.rating(track),
                  size: 22,
                  on: const Color(0xFF2E6FCB),
                  off: const Color(0xFFB4B9BF),
                ),
              NowPlayingMode.shuffle => _ShuffleChoice(key: const ValueKey('shuffle'), on: player.shuffle, color: _ink),
              _ => _Progress(key: const ValueKey('prog'), player: player, scrub: mode == NowPlayingMode.scrub),
            },
          ),
        ),
      ],
    );
  }
}

/// Les icônes aléatoire et répétition de l'écran « En lecture ».
class _PlayIcons extends StatelessWidget {
  const _PlayIcons({required this.player, required this.color, required this.size});

  final PlayerController player;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (player.shuffling) Icon(Icons.shuffle_rounded, size: size, color: color),
          if (player.repeat != RepeatMode.off)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Icon(
                player.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                size: size,
                color: color,
              ),
            ),
        ],
      );
}

/// La note du morceau : cinq étoiles, pleines jusqu'à [stars], des points
/// au-delà (la molette en ajoute ou en retire).
class _Stars extends StatelessWidget {
  const _Stars({super.key, required this.stars, required this.size, required this.on, required this.off});

  final int stars;
  final double size;
  final Color on, off;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 5; i++)
              SizedBox(
                width: size + 4,
                height: size,
                child: Center(
                  child: i < stars
                      ? Icon(Icons.star_rounded, size: size, color: on)
                      : DecoratedBox(
                          decoration: BoxDecoration(color: off, shape: BoxShape.circle),
                          child: SizedBox.square(dimension: size * 0.22),
                        ),
                ),
              ),
          ],
        ),
      );
}

/// Lecture aléatoire, réglée depuis « En lecture » (la molette la met ou
/// l'enlève).
class _ShuffleChoice extends StatelessWidget {
  const _ShuffleChoice({super.key, required this.on, required this.color, this.fontSize = 13});

  final bool on;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shuffle_rounded, size: fontSize + 3, color: color),
            const SizedBox(width: 6),
            Text(
              '${tr('Lecture aléatoire')} : ${on ? tr('Morceaux') : tr('Non')}',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(fontSize: fontSize, color: color),
            ),
          ],
        ),
      );
}

/// La pochette tournée d'un quart vers la droite, et son reflet sur le
/// fond blanc (Classic, nano 3G).
class _TiltedArtwork extends StatelessWidget {
  const _TiltedArtwork({required this.bytes, required this.size});

  final dynamic bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    const reflection = 34.0;
    return Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0016)
        ..rotateY(-0.38),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Artwork(bytes: bytes, size: size),
          const SizedBox(height: 1),
          SizedBox(
            width: size,
            height: reflection,
            child: ClipRect(
              child: Stack(
                children: [
                  // La pochette à l'envers : son bas touche le bas de l'autre.
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Transform.scale(scaleY: -1, child: _Artwork(bytes: bytes, size: size)),
                  ),
                  // …qui se perd dans le blanc.
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99FFFFFF), Color(0xFFFFFFFF)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// L'image d'un menu scindé : la pochette d'un album qui glisse lentement,
/// remplacée par une autre de temps en temps ; la pochette en cours pour
/// « En lecture » ; un engrenage pour les Réglages.
class _Preview extends StatefulWidget {
  const _Preview({
    required this.kind,
    required this.seed,
    required this.player,
    required this.active,
  });

  final MenuPreview kind;

  /// La ligne du menu : en changer fait passer à une autre pochette.
  final String seed;
  final PlayerController player;

  /// Écran allumé : l'image bouge.
  final bool active;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  /// Durée d'une pochette, en secondes.
  static const _stay = 9;

  Timer? _timer;
  DateTime _start = clock.now();
  Object? _shown;
  int _serial = 0;

  /// Les pochettes de la ligne en cours, tirées au hasard : tous les albums
  /// passent une fois avant qu'un seul ne revienne.
  final _random = math.Random();
  final _picks = <int>[];
  final _bag = <int>[];
  int _count = 0;

  int _album(int n, int count) {
    if (count != _count) {
      _count = count;
      _picks.clear();
      _bag.clear();
    }
    while (_picks.length <= n) {
      if (_bag.isEmpty) {
        _bag
          ..addAll(Iterable.generate(count))
          ..shuffle(_random);
        // Jamais deux fois de suite la même, d'un tour au suivant.
        if (count > 1 && _bag.last == _lastPick) _bag.insert(0, _bag.removeLast());
      }
      _picks.add(_lastPick = _bag.removeLast());
    }
    return _picks[n];
  }

  int? _lastPick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Preview old) {
    super.didUpdateWidget(old);
    if (old.seed != widget.seed || old.kind != widget.kind) {
      _start = clock.now();
      _picks.clear();
    }
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Vingt images par seconde suffisent à un glissement aussi lent, et
  /// seulement tant que l'écran est allumé.
  void _sync() {
    final moving = widget.active && widget.kind != MenuPreview.settings;
    if (moving == (_timer != null)) return;
    _timer?.cancel();
    _timer = moving
        ? Timer.periodic(const Duration(milliseconds: 50), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final t = clock.now().difference(_start).inMilliseconds / 1000;
    final Widget image;
    final Object key;
    switch (widget.kind) {
      case MenuPreview.settings:
        key = 'réglages';
        image = DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF2F4F6), Color(0xFFC3C9D0)],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, box) => Center(
              child: Icon(Icons.settings_rounded, size: math.min(96, box.maxHeight * 0.72), color: const Color(0xFF8A929B)),
            ),
          ),
        );
      case MenuPreview.nowPlaying:
        key = 'en lecture';
        image = _Pan(bytes: player.cover, phase: (t % (_stay * 2)) / (_stay * 2), back: false);
      case MenuPreview.covers:
        final count = player.albums.length;
        if (count == 0) {
          key = 'vide';
          image = const _Pan(bytes: null, phase: 0, back: false);
        } else {
          final turn = t ~/ _stay;
          int album(int n) => _album(n, count);
          player.albumCover(album(turn + 1)); // la suivante se prépare
          key = album(turn);
          image = _Pan(bytes: player.albumCover(album(turn)), phase: (t % _stay) / _stay, back: turn.isOdd);
        }
    }
    // Un numéro neuf à chaque changement d'image : la même peut revenir
    // pendant que la précédente s'efface encore.
    if (key != _shown) {
      _shown = key;
      _serial++;
    }
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            child: KeyedSubtree(key: ValueKey(_serial), child: image),
          ),
          // L'ombre du menu sur l'image, le long de leur bord commun.
          const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0x59000000), Color(0x00000000)]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une pochette plus grande que son cadre, qui le traverse lentement en
/// biais ([phase] de 0 à 1 ; [back] : dans l'autre sens).
class _Pan extends StatelessWidget {
  const _Pan({required this.bytes, required this.phase, required this.back});

  final dynamic bytes;
  final double phase;
  final bool back;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (bytes == null) {
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE9ECEF), Color(0xFFB9BFC6)],
            ),
          ),
          child: Center(child: Icon(Icons.music_note_rounded, size: 72, color: Colors.white)),
        );
      }
      final side = math.max(box.maxWidth, box.maxHeight) * 1.25;
      final p = back ? 1 - phase : phase;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: side,
          maxWidth: side,
          minHeight: side,
          maxHeight: side,
          child: Transform.translate(
            offset: Offset(-(side - box.maxWidth) * p, -(side - box.maxHeight) * (0.15 + 0.7 * p)),
            child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium),
          ),
        ),
      );
    });
  }
}

/// En lecture sur l'écran vertical du nano 4G : pochette carrée bord à
/// bord, puis sur fond noir le titre et l'artiste centrés, et une seule
/// ligne temps écoulé · barre · temps restant.
class _NowPlayingPortrait extends StatelessWidget {
  const _NowPlayingPortrait({required this.player, required this.mode, this.tall = false});

  final PlayerController player;
  final NowPlayingMode mode;

  /// Écran allongé du nano 5G : titre, artiste et album en haut, sous la
  /// barre de titre, puis la pochette. Sinon (nano 4G) la pochette d'abord,
  /// le titre et l'artiste dessous, sur son reflet.
  final bool tall;

  static const _white = Color(0xFFF2F3F5);
  static const _grey = Color(0xFFB4B8BE);
  static const _bg = Color(0xFF0E0F12);

  @override
  Widget build(BuildContext context) {
    final track = player.current;
    if (track == null) {
      return ColoredBox(
        color: const Color(0xFF0E0F12),
        child: Center(child: Text(tr('Aucun morceau'), style: const TextStyle(color: _white))),
      );
    }
    const art = 240.0;
    final top = tall ? 50.0 : 0.0;
    final cover = _Artwork(bytes: player.cover, size: art);
    final title = Marquee(track.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _white));
    final artist = Marquee(track.artist, style: const TextStyle(fontSize: 11, color: _grey));
    return ColoredBox(
      color: _bg,
      child: Stack(
        children: [
          Positioned(left: 0, top: top, child: cover),
          // Le reflet de la pochette, comme posée sur une table noire : il
          // occupe tout le bas de l'écran, sous le texte et la barre.
          Positioned(left: 0, top: top + art, width: art, bottom: 0, child: _Reflection(size: art, child: cover)),
          Positioned(
            left: 8,
            right: 8,
            top: tall ? 4 : art + 3,
            child: Column(
              children: [
                title,
                const SizedBox(height: 2),
                artist,
                if (tall && track.album.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Marquee(track.album, style: const TextStyle(fontSize: 11, color: _grey)),
                ],
              ],
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 5,
            height: 14,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: switch (mode) {
                NowPlayingMode.volume => _VolumeLine(key: const ValueKey('vol'), volume: player.volume / 100),
                NowPlayingMode.rating => _Stars(
                    key: const ValueKey('stars'),
                    stars: player.rating(track),
                    size: 14,
                    on: _white,
                    off: const Color(0xFF8A8F96),
                  ),
                NowPlayingMode.shuffle =>
                  _ShuffleChoice(key: const ValueKey('shuffle'), on: player.shuffle, color: _white, fontSize: 10.5),
                _ => _ProgressLine(key: const ValueKey('prog'), player: player, scrub: mode == NowPlayingMode.scrub),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Le haut du reflet de [child] (un carré de côté [size]) : retourné, sous
/// un voile qui se fond dans le fond de l'écran.
class _Reflection extends StatelessWidget {
  const _Reflection({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: size,
            maxHeight: size,
            child: Transform.flip(flipY: true, child: child),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x990E0F12), _NowPlayingPortrait._bg],
              stops: [0, 0.9],
            ),
          ),
        ),
      ],
    );
  }
}

/// 0:21 ━━━━━━━━━ -2:15, sur une ligne.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({super.key, required this.player, required this.scrub});

  final PlayerController player;
  final bool scrub;

  @override
  Widget build(BuildContext context) {
    final pos = player.smoothPosition;
    final remaining = player.duration - pos;
    const time = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _NowPlayingPortrait._white);
    return Row(
      children: [
        SizedBox(width: 30, child: Text(_time(pos), style: time)),
        Expanded(child: SizedBox(height: 8, child: CustomPaint(size: Size.infinite, painter: _BarPainter(player.progress, scrub)))),
        SizedBox(
          width: 34,
          child: Text(
            '-${_time(remaining.isNegative ? Duration.zero : remaining)}',
            style: time,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _VolumeLine extends StatelessWidget {
  const _VolumeLine({super.key, required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context) {
    const icon = Color(0xFFD5D8DC);
    return Row(
      children: [
        const Icon(Icons.volume_mute_rounded, size: 13, color: icon),
        const SizedBox(width: 4),
        Expanded(child: SizedBox(height: 8, child: CustomPaint(size: Size.infinite, painter: _BarPainter(volume, false)))),
        const SizedBox(width: 4),
        const Icon(Icons.volume_up_rounded, size: 13, color: icon),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.bytes, required this.size});

  final dynamic bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget image = bytes == null
        ? DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE9ECEF), Color(0xFFB9BFC6)],
              ),
            ),
            child: Center(child: Icon(Icons.music_note_rounded, size: math.min(48, size * 0.42), color: Colors.white)),
          )
        : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: Border.all(color: const Color(0x33000000))),
        child: image,
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({super.key, required this.player, required this.scrub});

  final PlayerController player;
  final bool scrub;

  @override
  Widget build(BuildContext context) {
    final pos = player.smoothPosition;
    final remaining = player.duration - pos;
    return Column(
      children: [
        SizedBox(height: 12, child: CustomPaint(size: Size.infinite, painter: _BarPainter(player.progress, scrub))),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_time(pos), style: const TextStyle(fontSize: 11)),
            Text('-${_time(remaining.isNegative ? Duration.zero : remaining)}', style: const TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _VolumeBar extends StatelessWidget {
  const _VolumeBar({super.key, required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.volume_mute_rounded, size: 14, color: Color(0xFF4A4F55)),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SizedBox(height: 12, child: CustomPaint(size: Size.infinite, painter: _BarPainter(volume, false))),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.volume_up_rounded, size: 14, color: Color(0xFF4A4F55)),
      ],
    );
  }
}

/// Barre bombée façon verre : creux gris, remplissage bleu brillant.
class _BarPainter extends CustomPainter {
  const _BarPainter(this.value, this.diamond);

  final double value;
  final bool diamond;

  @override
  void paint(Canvas canvas, Size size) {
    final r = const Radius.circular(2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(
      track,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFBFC4CA), Color(0xFFF4F5F7)],
        ).createShader(track.outerRect),
    );
    final fillW = size.width * value.clamp(0.0, 1.0);
    if (fillW > 0) {
      final fill = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fillW, size.height), r);
      canvas.drawRRect(
        fill,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF9CCCF8), Color(0xFF3A8BE6), Color(0xFF2167CC)],
            stops: [0, 0.5, 1],
          ).createShader(fill.outerRect),
      );
    }
    canvas.drawRRect(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF7D838A),
    );
    if (diamond) {
      final c = Offset(fillW, size.height / 2);
      final h = size.height / 2 + 3;
      final path = Path()
        ..moveTo(c.dx, c.dy - h)
        ..lineTo(c.dx + h * 0.75, c.dy)
        ..lineTo(c.dx, c.dy + h)
        ..lineTo(c.dx - h * 0.75, c.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.white);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF33383E),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.value != value || old.diamond != diamond;
}

