import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide RepeatMode;

import '../core/player.dart';
import 'finish.dart';
import 'look.dart';
import 'model.dart';
import 'nav.dart';
import 'wheel.dart';
import '../core/strings.dart';

/// Teintes d'aluminium anodisé de la 1re génération, relevées sur les
/// photos d'Apple : la face ([base]), le reflet qui court le long des
/// arrondis ([light]) et l'ombre des flancs ([dark]).
enum MiniColor {
  argent('Argent', base: Color(0xFFC4C6C9), light: Color(0xFFD9DBDE), dark: Color(0xFF5A5D62)),
  bleu('Bleu', base: Color(0xFF609FCA), light: Color(0xFF7ABAE3), dark: Color(0xFF2B4F78)),
  rose('Rose', base: Color(0xFFE07BA6), light: Color(0xFFEE94B9), dark: Color(0xFF7E4157)),
  vert('Vert', base: Color(0xFF9ED354), light: Color(0xFFB2E06E), dark: Color(0xFF4F682C)),
  or('Or', base: Color(0xFFC8AB64), light: Color(0xFFD9C17C), dark: Color(0xFF63492B)),

  // 2e génération (2005) : teintes plus vives, plus d'or, et les
  // inscriptions de la molette prennent la couleur du boîtier.
  argent2('Argent', base: Color(0xFFC4C9CA), light: Color(0xFFE2E7E6), dark: Color(0xFF5A5E61), gen2: true),
  bleu2('Bleu', base: Color(0xFF1596D6), light: Color(0xFF3DB4EC), dark: Color(0xFF0A4F78), gen2: true),
  rose2('Rose', base: Color(0xFFDC559A), light: Color(0xFFEE7DB7), dark: Color(0xFF7E1F55), gen2: true),
  vert2('Vert', base: Color(0xFF7DB33B), light: Color(0xFFADD558), dark: Color(0xFF3F6B24), gen2: true);

  const MiniColor(this.displayName, {required this.base, required this.light, required this.dark, this.gen2 = false});

  /// Les cinq teintes de 2004.
  static List<MiniColor> get gen1 => [for (final c in values) if (!c.gen2) c];

  /// Les quatre teintes de 2005.
  static List<MiniColor> get gen2s => [for (final c in values) if (c.gen2) c];

  final bool gen2;
  final String displayName;
  final Color base;
  final Color light;
  final Color dark;
}

/// Le Mini : tube d'aluminium anodisé de 51 × 91 mm, petit écran
/// monochrome rétroéclairé, molette en plastique blanc cassé aux inscriptions
/// grises.
class MiniModel extends IpodModel {
  const MiniModel([this.color = MiniColor.bleu]);

  final MiniColor color;

  // ≈ 6,67 unités par mm, comme le Classic.
  static const Size _size = Size(340, 607);
  static const Rect _screen = Rect.fromLTWH(59.5, 54, 221, 176);
  static const double _radius = 22;

  @override
  String get id => color.gen2 ? 'mini2-${color.name.substring(0, color.name.length - 1)}' : 'mini-${color.name}';

  @override
  String get family => color.gen2 ? 'mini2' : 'mini';

  @override
  String get label => color.gen2 ? 'Mini 2G' : 'Mini';

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

  @override
  double get screenCornerRadius => 1;

  /// Tout à droite sur la tranche du haut, après la prise télécommande
  /// (le verrou est à gauche).
  @override
  double get jackX => 300;

  @override
  Offset get wheelCenter => const Offset(170, 419);

  @override
  WheelStyle get wheel => WheelStyle(
        radius: 132,
        buttonRadius: 45,
        iconScale: 1,
        labelSize: 17,
        labelSpacing: 0.9,
        label: color.gen2 && color != MiniColor.argent2 ? color.base : const Color(0xFF8A9394),
        recess: Color.lerp(color.dark, color.base, 0.35)!,
        ring: const [Color(0xFFF3F3F3), Color(0xFFE6E6E6), Color(0xFFDDDEDE)],
        edgeLight: 0.8,
        groove: const Color(0xFFB4B9B9),
        buttonUp: const [Color(0xFFF0F0F0), Color(0xFFE3E3E3)],
        buttonDown: const [Color(0xFFD6D7D7), Color(0xFFE6E6E6)],
      );

  /// En haut à gauche, dans le bouchon en plastique blanc.
  @override
  HoldSwitch? get hold => const HoldSwitch(75);

  @override
  ScreenLook get look => const MiniLook();

  @override
  CustomPainter get body => _MiniBodyPainter(color);

  @override
  CustomPainter? get glass => const _MiniGlassPainter();

  @override
  Size get windowSize => const Size(400, 680);

  @override
  bool operator ==(Object other) => other is MiniModel && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

// --- Boîtier -------------------------------------------------------------------

class _MiniBodyPainter extends CustomPainter {
  const _MiniBodyPainter(this.color);

  final MiniColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(MiniModel._radius));

    paintFloatShadow(canvas, body, drop: 24, blur: 26);

    canvas.save();
    canvas.clipRRect(body);

    // Tube d'aluminium éclairé de la gauche : les flancs arrondis fuient
    // dans l'ombre, un reflet suit l'arrondi gauche, la face est unie.
    final c = color;
    final deep = Color.lerp(c.dark, Colors.black, 0.25)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, 0),
          [deep, c.dark, c.light, Color.lerp(c.base, c.light, 0.3)!, c.base, c.base, Color.lerp(c.base, c.dark, 0.35)!, c.dark, deep],
          const [0, 0.03, 0.075, 0.14, 0.26, 0.86, 0.925, 0.972, 1],
        ),
    );
    // Lumière venant d'en haut.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: 0.16)],
          const [0, 0.4, 1],
        ),
    );
    paintSatin(canvas, size);

    // Bouchons en plastique blanc en haut et en bas du tube.
    for (final top in [true, false]) {
      final cap = top ? Rect.fromLTWH(0, 0, size.width, 5) : Rect.fromLTWH(0, size.height - 5, size.width, 5);
      canvas.drawRect(
        cap,
        Paint()
          ..shader = ui.Gradient.linear(
            cap.topLeft,
            cap.bottomLeft,
            top ? const [Color(0xFFF2F2F0), Color(0xFFCFD0CE)] : const [Color(0xFFCFD0CE), Color(0xFFE6E6E4)],
          ),
      );
    }
    canvas.restore();

    // Fenêtre de l'écran : découpe biseautée dans l'aluminium, puis cadre noir.
    final window = RRect.fromRectAndRadius(MiniModel._screen.inflate(12), const Radius.circular(7));
    canvas.drawRRect(
      window.inflate(1.5),
      Paint()
        ..shader = ui.Gradient.linear(
          window.outerRect.topCenter,
          window.outerRect.bottomCenter,
          [c.dark, Color.lerp(c.light, Colors.white, 0.5)!],
        ),
    );
    canvas.drawRRect(window, Paint()..color = const Color(0xFF2A2D30));
    canvas.drawRRect(
      RRect.fromRectAndRadius(MiniModel._screen.inflate(4), const Radius.circular(3)),
      Paint()..color = const Color(0xFF15171A),
    );
  }

  @override
  bool shouldRepaint(covariant _MiniBodyPainter old) => old.color != color;
}

/// Plastique transparent sur l'écran : reflet en biais et ombre interne.
class _MiniGlassPainter extends CustomPainter {
  const _MiniGlassPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final window = RRect.fromRectAndRadius(MiniModel._screen.inflate(12), const Radius.circular(7));
    canvas.save();
    canvas.clipRRect(window);
    final r = window.outerRect;
    canvas.drawPath(
      Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.left + r.width * 0.72, r.top)
        ..lineTo(r.left, r.top + r.height * 0.62)
        ..close(),
      Paint()
        ..shader = ui.Gradient.linear(
          r.topLeft,
          r.topLeft + Offset(r.width * 0.36, r.height * 0.31),
          [Colors.white.withValues(alpha: 0.20), Colors.white.withValues(alpha: 0.05)],
        ),
    );
    // L'écran est en retrait sous la vitre.
    canvas.drawRect(
      Rect.fromLTWH(MiniModel._screen.left, MiniModel._screen.top, MiniModel._screen.width, 6),
      Paint()
        ..shader = ui.Gradient.linear(
          MiniModel._screen.topLeft,
          MiniModel._screen.topLeft + const Offset(0, 6),
          [Colors.black.withValues(alpha: 0.22), Colors.black.withValues(alpha: 0)],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// --- Écran monochrome ------------------------------------------------------------

// Relevés sur l'écran rétroéclairé des photos d'Apple : fond bleuté, encre
// bleu nuit.
const _ink = Color(0xFF2B2C55);
const _lcd = Color(0xFFB5C1D5);
const _font = 'Noto Sans';
const double _barH = 18;

/// Écran monochrome rétroéclairé, à deux tons. Par défaut celui du Mini
/// (138 × 110, 5 lignes) ; les premières générations en ont un plus grand.
class MiniLook extends ScreenLook {
  const MiniLook({this.size = const Size(138, 110), this.visibleRows = 5, this.font = _font, this.ratings = true});

  /// Police de l'écran : Chicago sur les deux premières générations.
  final String font;

  /// On peut noter le morceau en étoiles (à partir de la 3e génération).
  final bool ratings;

  @override
  bool get mono => true;

  @override
  double get barHeight => _barH;

  @override
  Color get selectedInk => _lcd;

  @override
  List<NowPlayingMode> get centerCycle =>
      ratings ? const [NowPlayingMode.scrub, NowPlayingMode.rating] : const [NowPlayingMode.scrub];

  @override
  final Size size;

  @override
  final int visibleRows;

  @override
  double get rowHeight => (size.height - _barH) / visibleRows;

  @override
  double get scrollbarWidth => 6;

  @override
  TextStyle get textStyle => font == _font
      ? const TextStyle(fontFamily: _font, color: _ink, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1)
      // (Chicago n'a qu'une graisse, déjà épaisse.)
      : TextStyle(fontFamily: font, color: _ink, fontSize: 11.5, fontWeight: FontWeight.w400, height: 1);

  @override
  Color get background => _lcd;

  /// Écran LCD sans rétroéclairage : gris terne, le texte reste lisible.
  @override
  Color get unlit => const Color(0x7A4E5A5E);

  @override
  Widget statusBar({
    required String title,
    required bool playing,
    required bool hasTrack,
    bool nowPlaying = false,
    bool locked = false,
  }) =>
      Container(
        height: _barH,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _ink, width: 1)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              left: 16,
              right: locked ? 31 : 22,
              child: Center(
                child: Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5),
                ),
              ),
            ),
            if (hasTrack)
              Positioned(
                left: 3,
                top: 0,
                bottom: 0,
                child: Icon(playing ? Icons.play_arrow : Icons.pause, size: 11, color: _ink),
              ),
            if (locked) const Positioned(right: 21, top: 0, bottom: 0, child: Icon(Icons.lock, size: 9, color: _ink)),
            const Positioned(right: 4, top: 5, child: CustomPaint(size: Size(15, 7), painter: _BatteryPainter())),
          ],
        ),
      );

  @override
  Widget highlight() => const ColoredBox(color: _ink);

  @override
  Widget row(MenuEntry entry, {required bool selected, MenuKind kind = MenuKind.normal}) {
    final color = selected ? _lcd : _ink;
    final value = entry.value?.call();
    return Padding(
      padding: const EdgeInsets.only(left: 5, right: 2),
      child: Row(
        children: [
          Expanded(child: Marquee(entry.label, active: selected, style: TextStyle(color: color))),
          if (value != null)
            Padding(
              padding: EdgeInsets.only(left: 5, right: entry.open == null ? 3 : 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: size.width * 0.42),
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          if (entry.checked?.call() ?? false) Icon(Icons.check, size: 12, color: color),
          if (entry.open != null) Icon(Icons.chevron_right, size: 13, color: color),
        ],
      ),
    );
  }

  @override
  CustomPainter scrollbar(double start, double extent) => _ScrollbarPainter(start, extent);

  @override
  Widget empty() => Center(child: Text(tr('Aucun élément')));

  @override
  Widget nowPlaying(PlayerController player, NowPlayingMode mode) => _NowPlaying(player: player, mode: mode);
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = _ink;
    final body = Rect.fromLTWH(0, 0, size.width - 2, size.height);
    canvas.drawRect(
      body.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _ink,
    );
    canvas.drawRect(Rect.fromLTWH(size.width - 2, 2, 2, size.height - 4), ink);
    final inner = body.deflate(2);
    final w = (inner.width - 2) / 3;
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(inner.left + i * (w + 1), inner.top, w, inner.height), ink);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ScrollbarPainter extends CustomPainter {
  const _ScrollbarPainter(this.start, this.extent);

  final double start;
  final double extent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      (Offset.zero & size).deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _ink,
    );
    final h = (size.height * extent).clamp(6.0, size.height);
    final y = (size.height - h) * (start / (1 - extent)).clamp(0.0, 1.0);
    canvas.drawRect(Rect.fromLTWH(1.5, y + 1.5, size.width - 3, h - 3), Paint()..color = _ink);
  }

  @override
  bool shouldRepaint(covariant _ScrollbarPainter old) => old.start != start || old.extent != extent;
}

// --- En lecture --------------------------------------------------------------

String _time(Duration d) {
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Pas de pochette sur le Mini : trois lignes centrées et la barre.
class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.player, required this.mode});

  final PlayerController player;
  final NowPlayingMode mode;

  @override
  Widget build(BuildContext context) {
    final track = player.current;
    if (track == null) return Center(child: Text(tr('Aucun morceau')));
    // Rang dans ce qui a été lancé (l'album, la liste…), comme sur un vrai
    // iPod ; rien si le morceau a été lancé ailleurs (appli Spotify).
    final position = player.queueIndex >= 0 ? trOf(player.queueIndex + 1, player.nowPlaying.length) : '';

    Widget line(String text, TextStyle style) => Center(child: Marquee(text, style: style));

    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 3, 5, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Le rang, et à droite l'aléatoire et la répétition s'ils sont mis.
          Row(
            children: [
              Expanded(child: Text(position, style: const TextStyle(fontSize: 8.5))),
              if (player.shuffling) const Icon(Icons.shuffle, size: 9, color: _ink),
              if (player.repeat != RepeatMode.off)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(player.repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat, size: 9, color: _ink),
                ),
            ],
          ),
          const SizedBox(height: 6),
          line(track.title, const TextStyle(fontSize: 11.5)),
          const SizedBox(height: 4),
          line(track.artist, const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          line(track.album, const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
          const Spacer(),
          SizedBox(
            height: 22,
            child: switch (mode) {
              NowPlayingMode.volume => _volume(player.volume / 100),
              NowPlayingMode.rating => _stars(player.rating(track)),
              _ => _progress(player, mode == NowPlayingMode.scrub),
            },
          ),
        ],
      ),
    );
  }

  Widget _progress(PlayerController player, bool scrub) {
    final pos = player.smoothPosition;
    final remaining = player.duration - pos;
    return Column(
      children: [
        SizedBox(height: 7, child: CustomPaint(size: Size.infinite, painter: _BarPainter(player.progress, scrub))),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_time(pos), style: const TextStyle(fontSize: 8.5)),
            Text('-${_time(remaining.isNegative ? Duration.zero : remaining)}', style: const TextStyle(fontSize: 8.5)),
          ],
        ),
      ],
    );
  }

  /// La note : cinq étoiles, pleines jusqu'à [stars], des points au-delà.
  Widget _stars(int stars) => Align(
        alignment: Alignment.topCenter,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 5; i++)
              SizedBox(
                width: 13,
                height: 12,
                child: Center(
                  child: i < stars
                      ? const Icon(Icons.star, size: 12, color: _ink)
                      : const SizedBox(width: 2.5, height: 2.5, child: ColoredBox(color: _ink)),
                ),
              ),
          ],
        ),
      );

  Widget _volume(double v) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.volume_mute, size: 9, color: _ink),
          const SizedBox(width: 2),
          Expanded(child: SizedBox(height: 7, child: CustomPaint(size: Size.infinite, painter: _BarPainter(v, false)))),
          const SizedBox(width: 2),
          const Icon(Icons.volume_up, size: 9, color: _ink),
        ],
      );
}

/// Barre à contour noir, remplie en noir (écran à deux tons).
class _BarPainter extends CustomPainter {
  const _BarPainter(this.value, this.diamond);

  final double value;
  final bool diamond;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = _ink;
    canvas.drawRect(
      (Offset.zero & size).deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _ink,
    );
    final w = (size.width - 3) * value.clamp(0.0, 1.0);
    canvas.drawRect(Rect.fromLTWH(1.5, 1.5, w, size.height - 3), ink);
    if (diamond) {
      final c = Offset(1.5 + w, size.height / 2);
      final h = size.height / 2 + 2;
      final path = Path()
        ..moveTo(c.dx, c.dy - h)
        ..lineTo(c.dx + h * 0.7, c.dy)
        ..lineTo(c.dx, c.dy + h)
        ..lineTo(c.dx - h * 0.7, c.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = _lcd);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _ink,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.value != value || old.diamond != diamond;
}
