import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/player.dart';
import 'look.dart';
import 'model.dart';
import 'nav.dart';
import 'wheel.dart';

/// Teintes d'aluminium anodisé, avec la molette en plastique assortie.
enum MiniColor {
  argent(
    'Argent',
    base: Color(0xFFC4C8CC),
    light: Color(0xFFE4E7EA),
    dark: Color(0xFF8A8F94),
    wheel: [Color(0xFFF5F6F7), Color(0xFFE8EAEC), Color(0xFFD8DBDF)],
    label: Color(0xFFA4A9AE),
  ),
  bleu(
    'Bleu',
    base: Color(0xFF79AFDC),
    light: Color(0xFFAED2EF),
    dark: Color(0xFF3C72A2),
    wheel: [Color(0xFFEAF3FB), Color(0xFFD6E6F4), Color(0xFFC0D6EA)],
    label: Color(0xFF86A9CA),
  ),
  rose(
    'Rose',
    base: Color(0xFFE5A3C2),
    light: Color(0xFFF4CDE0),
    dark: Color(0xFFB0688C),
    wheel: [Color(0xFFFBEBF3), Color(0xFFF3D8E5), Color(0xFFE7C2D5)],
    label: Color(0xFFD29AB6),
  ),
  vert(
    'Vert',
    base: Color(0xFFA4CC88),
    light: Color(0xFFCAE5B6),
    dark: Color(0xFF6A964E),
    wheel: [Color(0xFFEFF7E8), Color(0xFFDDEDD0), Color(0xFFC9E0B7)],
    label: Color(0xFF9EC285),
  ),
  or(
    'Or',
    base: Color(0xFFD6C38C),
    light: Color(0xFFEDE1BD),
    dark: Color(0xFFA38F57),
    wheel: [Color(0xFFF9F4E5), Color(0xFFEFE6CD), Color(0xFFE2D6B3)],
    label: Color(0xFFC2B183),
  );

  const MiniColor(this.displayName, {required this.base, required this.light, required this.dark, required this.wheel, required this.label});

  final String displayName;
  final Color base;
  final Color light;
  final Color dark;
  final List<Color> wheel;
  final Color label;
}

/// Le Mini : tube d'aluminium anodisé de 51 × 91 mm, petit écran
/// monochrome rétroéclairé, molette en plastique de la couleur du boîtier.
class MiniModel extends IpodModel {
  const MiniModel([this.color = MiniColor.bleu]);

  final MiniColor color;

  // ≈ 6,67 unités par mm, comme le Classic.
  static const Size _size = Size(340, 607);
  static const Rect _screen = Rect.fromLTWH(59.5, 54, 221, 176);
  static const double _radius = 22;

  @override
  String get name => 'Baladeur Mini (${color.displayName})';

  @override
  String get id => 'mini-${color.name}';

  @override
  String get label => 'Mini ${color.displayName.toLowerCase()}';

  @override
  Size get size => _size;

  @override
  double get cornerRadius => _radius;

  @override
  Rect get screen => _screen;

  @override
  double get screenCornerRadius => 1;

  @override
  Offset get wheelCenter => const Offset(170, 402);

  @override
  WheelStyle get wheel => WheelStyle(
        radius: 100,
        buttonRadius: 37,
        iconScale: 0.76,
        labelSize: 13,
        labelSpacing: 0.9,
        label: color.label,
        recess: Color.lerp(color.dark, color.base, 0.4)!,
        ring: color.wheel,
        edgeLight: 0.8,
        groove: Color.lerp(color.wheel.last, color.label, 0.45)!,
        buttonUp: [color.wheel.first, color.wheel[1]],
        buttonDown: [color.wheel.last, color.wheel[1]],
      );

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

    // Ombres : il flotte.
    canvas.drawRRect(
      body.shift(const Offset(0, 24)).deflate(8),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );
    canvas.drawRRect(
      body.shift(const Offset(0, 5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    canvas.save();
    canvas.clipRRect(body);

    // Tube d'aluminium : bords qui fuient dans l'ombre, reflet près de chaque
    // arrondi, face avant mate.
    final c = color;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, 0),
          [c.dark, c.base, c.light, c.base, c.base, c.light, c.base, c.dark],
          const [0, 0.035, 0.09, 0.22, 0.78, 0.91, 0.965, 1],
        ),
    );
    // Lumière venant d'en haut.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: 0.08)],
          const [0, 0.45, 1],
        ),
    );
    // Grain du microbillage (déterministe).
    final rnd = math.Random(11);
    final light = <Offset>[];
    final dark = <Offset>[];
    for (var i = 0; i < 5200; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      (rnd.nextBool() ? light : dark).add(p);
    }
    canvas.drawPoints(
      ui.PointMode.points,
      light,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..strokeWidth = 0.9,
    );
    canvas.drawPoints(
      ui.PointMode.points,
      dark,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.07)
        ..strokeWidth = 0.9,
    );

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

const _ink = Color(0xFF1C2830);
const _lcd = Color(0xFFC6D4DA);
const _font = 'Noto Sans';
const double _barH = 18;

class MiniLook extends ScreenLook {
  const MiniLook();

  @override
  Size get size => const Size(138, 110);

  @override
  double get rowHeight => (110 - _barH) / 5;

  @override
  int get visibleRows => 5;

  @override
  double get scrollbarWidth => 6;

  @override
  TextStyle get textStyle =>
      const TextStyle(fontFamily: _font, color: _ink, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1);

  @override
  Color get background => _lcd;

  @override
  Widget statusBar({required String title, required bool playing, required bool hasTrack}) => Container(
        height: _barH,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _ink, width: 1)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              left: 16,
              right: 22,
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
            const Positioned(right: 4, top: 5, child: CustomPaint(size: Size(15, 7), painter: _BatteryPainter())),
          ],
        ),
      );

  @override
  Widget highlight() => const ColoredBox(color: _ink);

  @override
  Widget row(MenuEntry entry, {required bool selected}) {
    final color = selected ? _lcd : _ink;
    return Padding(
      padding: const EdgeInsets.only(left: 5, right: 2),
      child: Row(
        children: [
          Expanded(child: Marquee(entry.label, active: selected, style: TextStyle(color: color))),
          if (entry.open != null) Icon(Icons.chevron_right, size: 13, color: color),
        ],
      ),
    );
  }

  @override
  CustomPainter scrollbar(double start, double extent) => _ScrollbarPainter(start, extent);

  @override
  Widget empty() => const Center(child: Text('Aucun élément'));

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
    if (track == null) return const Center(child: Text('Aucun morceau'));
    final albumIndex = player.currentAlbum;
    final album = albumIndex >= 0 ? player.albums[albumIndex] : null;
    final position = album == null
        ? '${player.index + 1} sur ${player.queue.length}'
        : '${player.index - album.firstIndex + 1} sur ${album.trackCount}';

    Widget line(String text, TextStyle style) => Center(child: Marquee(text, style: style));

    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 3, 5, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(position, style: const TextStyle(fontSize: 8.5)),
          const SizedBox(height: 6),
          line(track.title, const TextStyle(fontSize: 11.5)),
          const SizedBox(height: 4),
          line(track.artist, const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          line(track.album, const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
          const Spacer(),
          SizedBox(
            height: 22,
            child: mode == NowPlayingMode.volume
                ? _volume(player.volume / 100)
                : _progress(player, mode == NowPlayingMode.scrub),
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
