import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/player.dart';
import '../physics.dart';
import 'coverflow.dart';
import 'look.dart';
import 'nav.dart';

/// Écran sous tension. Au lancement, l'iPod monte écran éteint
/// (voir main.dart) et ne s'allume qu'une fois arrivé.
final screenPower = ValueNotifier(true);

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
    // La navigation peut venir d'un autre appareil : on reprend là où elle
    // en est, sans rejouer la dernière transition.
    _transition = nav.transition;
    nav.addListener(_wake);
    widget.player.addListener(_wake);
    screenPower.addListener(_powerChanged);
    _wake();
  }

  void _powerChanged() {
    if (!mounted) return;
    // Allumé : rétroéclairage plein, et son délai repart de zéro.
    if (screenPower.value) nav.touch();
    setState(_scheduleBacklight);
  }

  // --- Rétroéclairage ----------------------------------------------------------

  Timer? _backlightTimer;
  bool _lit = true;

  /// Éteint l'écran à l'heure dite ; une action entre-temps repousse
  /// l'échéance (on revérifie à chaque fois).
  void _scheduleBacklight() {
    _backlightTimer?.cancel();
    _lit = nav.lit;
    if (!_lit || nav.backlight == 0) return;
    final due = nav.lastInput.add(Duration(seconds: nav.backlight)).difference(clock.now());
    _backlightTimer = Timer(due + const Duration(milliseconds: 20), () {
      if (!mounted) return;
      setState(_scheduleBacklight);
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _backlightTimer?.cancel();
    nav.removeListener(_wake);
    widget.player.removeListener(_wake);
    screenPower.removeListener(_powerChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _wake() {
    _scheduleBacklight();
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
    for (final p in [nav.page, ?nav.leaving]) {
      if (p is CoverFlowPage) {
        p.pos.step(p.selected.toDouble(), dt);
        p.flip.step(p.flipped ? 1 : 0, dt);
        p.trackSpring.step(p.track.toDouble(), dt);
        p.trackTopSpring.step(p.trackTop.toDouble(), dt);
        busy |= !p.pos.isSettled || !p.flip.isSettled || !p.trackSpring.isSettled || !p.trackTopSpring.isSettled;
      }
    }
    var playing = false;
    if (nav.page is NowPlayingPage) {
      nav.expireMode();
      busy |= nav.mode != NowPlayingMode.progress;
      playing = widget.player.playing;
    }
    setState(() {});
    if (!busy) {
      _ticker.stop();
      // En lecture, la barre n'avance que d'un pixel de temps en temps : on
      // ne redessine que quand elle (ou le temps affiché) change, pas à
      // chaque image.
      if (playing) _scheduleProgress();
    }
  }

  Timer? _progressTimer;

  void _scheduleProgress() {
    _progressTimer?.cancel();
    final player = widget.player;
    // La barre fait au plus ~300 points de large : un pas toutes les
    // durée / 600, et au changement de seconde pour le temps écrit.
    final step = (player.duration.inMicroseconds / 600).clamp(1e6 / 30, 5e5);
    final toNextSecond = 1e6 - player.smoothPosition.inMicroseconds % 1000000;
    final wait = Duration(microseconds: math.min(step, toNextSecond + 2000).round());
    _progressTimer = Timer(wait, () {
      if (!mounted || nav.page is! NowPlayingPage || !widget.player.playing || _ticker.isActive) return;
      setState(() {});
      _scheduleProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final w = look.size.width;
    final offset = _slide.value * w * nav.direction;
    return DefaultTextStyle(
      style: look.textStyle,
      child: _PowerOff(on: screenPower.value, look: look, child: _Backlight(lit: _lit, tint: look.unlit, child: ColoredBox(
        // Cover Flow est noir bord à bord : un fond clair dessous filtrerait
        // en liseré le long des bords de l'écran (lissage des arêtes).
        color: nav.page is CoverFlowPage && nav.leaving == null ? Colors.black : look.background,
        child: Column(
          children: [
            look.statusBar(
              title: nav.page.title,
              playing: widget.player.playing,
              hasTrack: widget.player.current != null,
              nowPlaying: nav.page is NowPlayingPage,
            ),
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
      ))),
    );
  }

  Widget _page(IpodPage p) => switch (p) {
        MenuPage() => _MenuView(page: p, look: widget.look),
        NowPlayingPage() => widget.look.nowPlaying(widget.player, nav.mode),
        CoverFlowPage() => CoverFlowView(page: p, player: widget.player),
      };
}

/// Voile de l'écran éteint : il tombe doucement, et disparaît d'un coup dès
/// qu'on touche l'appareil.
class _Backlight extends StatelessWidget {
  const _Backlight({required this.lit, required this.tint, required this.child});

  final bool lit;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: lit ? 0 : 1,
              duration: lit ? const Duration(milliseconds: 90) : const Duration(milliseconds: 900),
              curve: Curves.easeOut,
              child: ColoredBox(color: tint),
            ),
          ),
        ),
      ],
    );
  }
}

/// Écran hors tension : vide, rétroéclairage éteint. À l'allumage, le
/// contenu apparaît presque d'un coup.
class _PowerOff extends StatelessWidget {
  const _PowerOff({required this.on, required this.look, required this.child});

  final bool on;
  final ScreenLook look;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: on ? 0 : 1,
              // S'allume d'un coup (comme le rétroéclairage), s'éteint en douceur.
              duration: on ? const Duration(milliseconds: 90) : const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: ScreenOff(look: look),
            ),
          ),
        ),
      ],
    );
  }
}

/// Un écran hors tension : vide, sans rétroéclairage.
class ScreenOff extends StatelessWidget {
  const ScreenOff({super.key, required this.look});

  final ScreenLook look;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: look.background, child: ColoredBox(color: look.unlit));
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

