import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/player.dart';
import '../../physics.dart';
import 'look.dart';
import 'nav.dart';

/// L'écran : barre de titre, puis la page courante qui
/// glisse latéralement quand on entre ou sort d'un menu.
class IpodScreen extends StatefulWidget {
  const IpodScreen({super.key, required this.nav, required this.player, required this.look});

  final IpodNav nav;
  final PlayerController player;
  final ScreenLook look;

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
    final look = widget.look;
    final w = look.size.width;
    final offset = _slide.value * w * nav.direction;
    return DefaultTextStyle(
      style: look.textStyle,
      child: ColoredBox(
        color: look.background,
        child: Column(
          children: [
            look.statusBar(title: nav.page.title, playing: widget.player.playing, hasTrack: widget.player.current != null),
            Expanded(
              child: ClipRect(
                child: Stack(
                  children: [
                    if (nav.leaving != null)
                      Positioned.fill(
                        left: offset - w * nav.direction,
                        right: -(offset - w * nav.direction),
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
        MenuPage() => _MenuView(page: p, look: widget.look),
        NowPlayingPage() => widget.look.nowPlaying(widget.player, nav.mode),
      };
}

// --- Menus ---------------------------------------------------------------------

class _MenuView extends StatelessWidget {
  const _MenuView({required this.page, required this.look});

  final MenuPage page;
  final ScreenLook look;

  @override
  Widget build(BuildContext context) {
    final entries = page.entries;
    final top = page.topSpring.value;
    final visibleRows = look.visibleRows;
    final rowH = look.rowHeight;
    final scrollable = entries.length > visibleRows;
    final right = scrollable ? look.scrollbarWidth : 0.0;
    final first = top.floor().clamp(0, entries.length);
    final last = (first + visibleRows + 1).clamp(0, entries.length);

    if (entries.isEmpty) return look.empty();
    return Stack(
      children: [
        Positioned(
          top: (page.selSpring.value - top) * rowH,
          left: 0,
          right: right,
          height: rowH,
          child: look.highlight(),
        ),
        for (var i = first; i < last; i++)
          Positioned(
            top: (i - top) * rowH,
            left: 0,
            right: right,
            height: rowH,
            child: look.row(entries[i], selected: i == page.selected),
          ),
        if (scrollable)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: right,
            child: CustomPaint(
              painter: look.scrollbar(top / entries.length, visibleRows / entries.length),
            ),
          ),
      ],
    );
  }
}

