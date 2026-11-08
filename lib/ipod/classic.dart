import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/player.dart';
import 'look.dart';
import 'model.dart';
import 'nav.dart';
import 'wheel.dart';
import '../core/strings.dart';

/// Teintes du Classic : façade et molette assorties.
enum ClassicColor {
  blanc('Blanc', front: [Color(0xFFFFFFFF), Color(0xFFF6F6F4), Color(0xFFECECEA)], swatch: Color(0xFFF7F7F5)),
  noir('Noir', front: [Color(0xFF3A3B3E), Color(0xFF242528), Color(0xFF17181A)], swatch: Color(0xFF1E1F21));

  const ClassicColor(this.displayName, {required this.front, required this.swatch});

  final String displayName;
  final List<Color> front;
  final Color swatch;
}

/// Le Classic : façade laquée, liseré chromé, écran couleur 320×240.
class ClassicModel extends IpodModel {
  const ClassicModel([this.color = ClassicColor.blanc]);

  final ClassicColor color;

  // « classic » tout court pour le blanc : les préférences déjà enregistrées
  // restent valables.
  @override
  String get id => color == ClassicColor.blanc ? 'classic' : 'classic-${color.name}';

  @override
  String get family => 'classic';

  @override
  String get label => 'Classic';

  @override
  String get variantName => color.displayName;

  @override
  Color get swatch => color.swatch;

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
  WheelStyle get wheel => switch (color) {
        ClassicColor.blanc => const WheelStyle(radius: G.wheelRadius, buttonRadius: G.buttonRadius),
        // Molette noire mate, inscriptions gris clair.
        ClassicColor.noir => const WheelStyle(
            radius: G.wheelRadius,
            buttonRadius: G.buttonRadius,
            label: Color(0xFF8E9195),
            recess: Color(0xFF0E0F10),
            ring: [Color(0xFF3C3D40), Color(0xFF2C2D30), Color(0xFF1E1F22)],
            edgeLight: 0.12,
            groove: Color(0xFF111214),
            buttonUp: [Color(0xFF47484C), Color(0xFF2A2B2E)],
            buttonDown: [Color(0xFF26272A), Color(0xFF34353A)],
          ),
      };

  @override
  ScreenLook get look => const ClassicLook();

  @override
  CustomPainter get body => BodyPainter(color);

  @override
  CustomPainter? get glass => const GlassPainter();

  @override
  bool operator ==(Object other) => other is ClassicModel && other.color == color;

  @override
  int get hashCode => color.hashCode;
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
  WheelStyle get wheel => switch (color) {
        // Molette gris clair, inscriptions blanches.
        ClassicColor.blanc => const WheelStyle(
            radius: 122,
            buttonRadius: 44,
            label: Color(0xFFFAFAFB),
            recess: Color(0xFFDCDDDF),
            ring: [Color(0xFFE2E3E5), Color(0xFFD6D7DA), Color(0xFFC9CBCE)],
            edgeLight: 0.5,
            groove: Color(0xFFBFC1C5),
          ),
        // Molette grise, bouton central noir.
        ClassicColor.noir => const WheelStyle(
            radius: 122,
            buttonRadius: 44,
            label: Color(0xFFF2F3F4),
            recess: Color(0xFF0E0F10),
            ring: [Color(0xFF8E9094), Color(0xFF7F8185), Color(0xFF6F7175)],
            edgeLight: 0.25,
            groove: Color(0xFF222326),
            buttonUp: [Color(0xFF2E2F32), Color(0xFF141517)],
            buttonDown: [Color(0xFF121314), Color(0xFF202124)],
          ),
      };

  @override
  ScreenLook get look => const ClassicLook();

  @override
  CustomPainter get body => BodyPainter(color, _screen.inflate(6), true);

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

/// Boîtier : ombre portée (il flotte), liseré chromé, façade blanche laquée
/// et cadre sombre de l'écran.
class BodyPainter extends CustomPainter {
  const BodyPainter([this.color = ClassicColor.blanc, this.frameRect = G.screenFrame, this.plastic = false]);

  final ClassicColor color;

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

    // Façade blanche.
    final front = outer.deflate(G.rim);
    canvas.drawRRect(
      front,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          color.front,
          const [0, 0.55, 1],
        ),
    );
    // Arrondi de la façade : léger assombrissement au ras du chrome.
    canvas.drawRRect(
      front.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: 0.07),
    );
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
            [Colors.white.withValues(alpha: 0.75), Colors.white.withValues(alpha: 0.25), Colors.white.withValues(alpha: 0.5)],
            const [0, 0.5, 1],
          ),
      );
    }

    // Cadre de l'écran.
    final frame = RRect.fromRectAndRadius(frameRect, const Radius.circular(6));
    canvas.drawRRect(
      frame.inflate(1),
      Paint()..color = color == ClassicColor.blanc ? const Color(0xFFD5D6D8) : const Color(0xFF0B0B0C),
    );
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF1E1F21));
  }

  @override
  bool shouldRepaint(covariant BodyPainter old) =>
      old.color != color || old.frameRect != frameRect || old.plastic != plastic;
}

/// Reflet de la plaque d'acrylique qui couvre toute la façade.
class GlassPainter extends CustomPainter {
  const GlassPainter([this.screen = G.screen]);

  final Rect screen;

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
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// --- Écran -------------------------------------------------------------------

const double _barH = 22;
const _ink = Color(0xFF111111);
const _font = 'Noto Sans';

class ClassicLook extends ScreenLook {
  const ClassicLook({this.portrait = false});

  /// Écran vertical, 240 × 320 (nano de 4e génération).
  final bool portrait;

  @override
  Size get size => portrait ? const Size(240, 320) : const Size(320, 240);

  @override
  double get rowHeight => 24;

  @override
  int get visibleRows => portrait ? 12 : 9;

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
  bool get coverFlow => true;

  @override
  Widget statusBar({required String title, required bool playing, required bool hasTrack, bool nowPlaying = false}) =>
      portrait && nowPlaying
          ? _DarkStatusBar(title: title, playing: playing, hasTrack: hasTrack)
          : _StatusBar(title: title, playing: playing, hasTrack: hasTrack);

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
  Widget row(MenuEntry entry, {required bool selected}) => _Row(entry: entry, selected: selected);

  @override
  CustomPainter scrollbar(double start, double extent) => _ScrollbarPainter(start, extent);

  @override
  Widget empty() => Center(
        child: Text(tr('Aucun élément'), style: const TextStyle(color: Color(0xFF8A8F95))),
      );

  @override
  Widget nowPlaying(PlayerController player, NowPlayingMode mode) =>
      portrait ? _NowPlayingPortrait(player: player, mode: mode) : _NowPlaying(player: player, mode: mode);
}

// --- Barre de titre ----------------------------------------------------------

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.title, required this.playing, required this.hasTrack});

  final String title;
  final bool playing;
  final bool hasTrack;

  @override
  Widget build(BuildContext context) {
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
          // Entre l'icône de lecture et la batterie ; coupé par « … » si trop long.
          Positioned.fill(
            left: 26,
            right: 38,
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (hasTrack)
            Positioned(
              left: 6,
              top: 0,
              bottom: 0,
              child: Icon(playing ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 15, color: const Color(0xFF2E6FCB)),
            ),
          const Positioned(right: 7, top: 6, child: CustomPaint(size: Size(24, 10), painter: _BatteryPainter())),
        ],
      ),
    );
  }
}

/// Barre noire de l'écran « En lecture » du nano 4G : titre blanc, l'icône
/// de lecture à côté de la batterie.
class _DarkStatusBar extends StatelessWidget {
  const _DarkStatusBar({required this.title, required this.playing, required this.hasTrack});

  final String title;
  final bool playing;
  final bool hasTrack;

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
  const _Row({required this.entry, required this.selected});

  final MenuEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : _ink;
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
  const _NowPlaying({required this.player, required this.mode});

  final PlayerController player;
  final NowPlayingMode mode;

  @override
  Widget build(BuildContext context) {
    final track = player.current;
    if (track == null) {
      return Center(child: Text(tr('Aucun morceau')));
    }
    final albumIndex = player.currentAlbum;
    final album = albumIndex >= 0 ? player.albums[albumIndex] : null;
    final position = album == null
        ? trOf(player.index + 1, player.queue.length)
        : trOf(player.index - album.firstIndex + 1, album.trackCount);

    const art = 116.0;
    return Stack(
      children: [
        Positioned(
          left: 8,
          top: 5,
          child: Text(position, style: const TextStyle(fontSize: 11, color: Color(0xFF4A4F55))),
        ),
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
            child: mode == NowPlayingMode.volume
                ? _VolumeBar(key: const ValueKey('vol'), volume: player.volume / 100)
                : _Progress(key: const ValueKey('prog'), player: player, scrub: mode == NowPlayingMode.scrub),
          ),
        ),
      ],
    );
  }
}

/// En lecture sur l'écran vertical du nano 4G : pochette carrée bord à
/// bord, puis sur fond noir le titre et l'artiste centrés, et une seule
/// ligne temps écoulé · barre · temps restant.
class _NowPlayingPortrait extends StatelessWidget {
  const _NowPlayingPortrait({required this.player, required this.mode});

  final PlayerController player;
  final NowPlayingMode mode;

  static const _white = Color(0xFFF2F3F5);

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
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A2C31), Color(0xFF0E0F12)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(left: 0, top: 0, child: _Artwork(bytes: player.cover, size: art)),
          Positioned(
            left: 8,
            right: 8,
            top: art + 3,
            child: Column(
              children: [
                Marquee(track.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _white)),
                const SizedBox(height: 2),
                Marquee(track.artist, style: const TextStyle(fontSize: 11, color: Color(0xFFB4B8BE))),
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
              child: mode == NowPlayingMode.volume
                  ? _VolumeLine(key: const ValueKey('vol'), volume: player.volume / 100)
                  : _ProgressLine(key: const ValueKey('prog'), player: player, scrub: mode == NowPlayingMode.scrub),
            ),
          ),
        ],
      ),
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
        ? const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE9ECEF), Color(0xFFB9BFC6)],
              ),
            ),
            child: Center(child: Icon(Icons.music_note_rounded, size: 48, color: Colors.white)),
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

