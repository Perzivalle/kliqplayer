import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/player.dart';
import '../../physics.dart';
import 'nav.dart';

const double _w = 320;
const double _barH = 22;
const double _rowH = 24;

const _ink = Color(0xFF111111);
const _font = 'Noto Sans';

/// L'écran couleur 320×240 : barre de titre, puis la page courante qui
/// glisse latéralement quand on entre ou sort d'un menu.
class IpodScreen extends StatefulWidget {
  const IpodScreen({super.key, required this.nav, required this.player});

  final IpodNav nav;
  final PlayerController player;

  @override
  State<IpodScreen> createState() => _IpodScreenState();
}

class _IpodScreenState extends State<IpodScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  /// Décalage de la page entrante : 1 = hors écran, 0 = en place.
  final _slide = Spring(0, stiffness: 520, damping: 1);
  int _transition = 0;

  IpodNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    nav.addListener(_wake);
    widget.player.addListener(_wake);
    _wake();
  }

  @override
  void dispose() {
    nav.removeListener(_wake);
    widget.player.removeListener(_wake);
    _ticker.dispose();
    super.dispose();
  }

  void _wake() {
    if (nav.transition != _transition) {
      _transition = nav.transition;
      _slide
        ..value = 1
        ..velocity = 0;
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    if (mounted) setState(() {});
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = elapsed;

    var busy = false;
    _slide.step(0, dt);
    if (_slide.isSettled) {
      _slide.value = 0;
      nav.transitionDone();
    } else {
      busy = true;
    }
    for (final p in [nav.page, ?nav.leaving]) {
      if (p is MenuPage) {
        p.selSpring.step(p.selected.toDouble(), dt);
        p.topSpring.step(p.top.toDouble(), dt);
        busy |= !p.selSpring.isSettled || !p.topSpring.isSettled;
      }
    }
    if (nav.page is NowPlayingPage) {
      nav.expireMode();
      busy |= widget.player.playing || nav.mode != NowPlayingMode.progress;
    }
    setState(() {});
    if (!busy) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final offset = _slide.value * _w * nav.direction;
    return DefaultTextStyle(
      style: const TextStyle(fontFamily: _font, color: _ink, fontSize: 14, fontWeight: FontWeight.w600, height: 1),
      child: ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            _StatusBar(title: nav.page.title, playing: widget.player.playing, hasTrack: widget.player.current != null),
            Expanded(
              child: ClipRect(
                child: Stack(
                  children: [
                    if (nav.leaving != null)
                      Positioned.fill(
                        left: offset - _w * nav.direction,
                        right: -(offset - _w * nav.direction),
                        child: _page(nav.leaving!),
                      ),
                    Positioned.fill(left: offset, right: -offset, child: _page(nav.page)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(IpodPage p) => switch (p) {
        MenuPage() => _MenuView(page: p),
        NowPlayingPage() => _NowPlaying(player: widget.player, mode: nav.mode),
      };
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

// --- Menus ---------------------------------------------------------------------

class _MenuView extends StatelessWidget {
  const _MenuView({required this.page});

  final MenuPage page;

  @override
  Widget build(BuildContext context) {
    final entries = page.entries;
    final top = page.topSpring.value;
    final scrollable = entries.length > visibleRows;
    final right = scrollable ? 9.0 : 0.0;
    final first = top.floor().clamp(0, entries.length);
    final last = (first + visibleRows + 1).clamp(0, entries.length);

    if (entries.isEmpty) {
      return const Center(
        child: Text('Aucun élément', style: TextStyle(color: Color(0xFF8A8F95))),
      );
    }
    return Stack(
      children: [
        Positioned(
          top: (page.selSpring.value - top) * _rowH,
          left: 0,
          right: right,
          height: _rowH,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF7DBBF5), Color(0xFF3A8BE6), Color(0xFF1F6BD3)],
                stops: [0, 0.5, 1],
              ),
              border: Border(top: BorderSide(color: Color(0xFF5FA2EC)), bottom: BorderSide(color: Color(0xFF1857B3))),
            ),
          ),
        ),
        for (var i = first; i < last; i++)
          Positioned(
            top: (i - top) * _rowH,
            left: 0,
            right: right,
            height: _rowH,
            child: _Row(entry: entries[i], selected: i == page.selected),
          ),
        if (scrollable)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: right,
            child: CustomPaint(
              painter: _ScrollbarPainter(top / entries.length, visibleRows / entries.length),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.selected});

  final MenuEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : _ink;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Row(
        children: [
          Expanded(child: _Marquee(entry.label, active: selected, style: TextStyle(color: color))),
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

// --- Texte défilant ---------------------------------------------------------

/// Texte sur une ligne qui, s'il est trop long et [active], défile vers la
/// gauche jusqu'à sa fin, s'y arrête, puis revient au début (comme sur
/// l'appareil). Sinon il est coupé par « … ».
class _Marquee extends StatefulWidget {
  const _Marquee(this.text, {this.style, this.active = true});

  final String text;
  final TextStyle? style;
  final bool active;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  static const _pause = 1.4; // secondes à chaque bout
  static const _speed = 34.0; // pixels par seconde

  late final Ticker _ticker = createTicker(_tick);
  double _overflow = 0;
  double _offset = 0;

  @override
  void didUpdateWidget(_Marquee old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.active != widget.active) {
      _ticker.stop();
      _offset = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final travel = _overflow / _speed;
    final c = t % (_pause + travel + _pause);
    final next = c < _pause ? 0.0 : (c < _pause + travel ? (c - _pause) * _speed : _overflow);
    if (next != _offset) setState(() => _offset = next);
  }

  /// Démarre ou arrête l'animation après la mise en page (pas pendant).
  void _sync(bool scroll) {
    if (scroll == _ticker.isActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (scroll && !_ticker.isActive) {
        _ticker.start();
      } else if (!scroll && _ticker.isActive) {
        _ticker.stop();
        setState(() => _offset = 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return LayoutBuilder(builder: (context, box) {
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      _overflow = tp.width - box.maxWidth + 2;
      final scroll = widget.active && _overflow > 0;
      _sync(scroll);
      if (!scroll) {
        return Text(widget.text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style);
      }
      return SizedBox(
        width: box.maxWidth,
        height: tp.height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: Transform.translate(
              offset: Offset(-_offset, 0),
              child: Text(widget.text, maxLines: 1, softWrap: false, style: style),
            ),
          ),
        ),
      );
    });
  }
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
      return const Center(child: Text('Aucun morceau'));
    }
    final albumIndex = player.currentAlbum;
    final album = albumIndex >= 0 ? player.albums[albumIndex] : null;
    final position = album == null
        ? '${player.index + 1} sur ${player.queue.length}'
        : '${player.index - album.firstIndex + 1} sur ${album.trackCount}';

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
              _Marquee(track.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _Marquee(track.artist, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              _Marquee(track.album, style: const TextStyle(fontSize: 13, color: Color(0xFF5A5F66))),
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
