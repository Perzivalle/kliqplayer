import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/player.dart';
import '../core/strings.dart';
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
      if (p is SearchPage) {
        p.cellSpring.step(p.cell.toDouble(), dt);
        busy |= !p.cellSpring.isSettled;
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
        // Cover Flow et l'écran « En lecture » du nano 4G sont sombres bord à
        // bord : un fond clair dessous filtrerait en liseré le long des bords
        // de l'écran (lissage des arêtes).
        color: nav.leaving != null
            ? look.background
            : switch (nav.page) {
                CoverFlowPage() => Colors.black,
                NowPlayingPage() => look.nowPlayingBackground,
                _ => look.background,
              },
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: Stack(
                  children: [
                    if (nav.leaving != null)
                      Positioned.fill(
                        left: offset - w * nav.direction,
                        right: -(offset - w * nav.direction),
                        child: _framed(nav.leaving!),
                      ),
                    Positioned.fill(left: offset, right: -offset, child: _framed(nav.page)),
                  ],
                ),
              ),
            ),
            // La barre de titre, par-dessus : elle s'arrête à l'image d'un
            // menu scindé sur le côté, et s'allonge ou se raccourcit pendant
            // qu'on passe d'une page à l'autre.
            Positioned(
              left: 0,
              top: 0,
              height: look.barHeight,
              width: w *
                  (nav.leaving == null
                      ? _barShare(nav.page)
                      : _barShare(nav.page) + (_barShare(nav.leaving!) - _barShare(nav.page)) * _slide.value.clamp(0.0, 1.0)),
              child: look.statusBar(
                title: nav.page.title,
                playing: widget.player.playing,
                hasTrack: widget.player.current != null,
                nowPlaying: nav.page is NowPlayingPage,
                locked: nav.locked,
              ),
            ),
          ],
        ),
      ))),
    );
  }

  /// Les zones d'un menu scindé, si [p] en est un sur cet écran.
  ({Rect menu, Rect image})? _split(IpodPage p) =>
      p is MenuPage && p.kind == MenuKind.split ? widget.look.split(widget.look.size) : null;

  /// Part de la largeur que la barre de titre occupe au-dessus de [p].
  double _barShare(IpodPage p) {
    final parts = _split(p);
    return parts != null && parts.image.top == 0 ? parts.menu.width / widget.look.size.width : 1;
  }

  /// La page à sa place : sous la barre de titre, sauf un menu scindé, qui
  /// se place lui-même sur l'écran entier.
  Widget _framed(IpodPage p) =>
      _split(p) != null ? _page(p) : Padding(padding: EdgeInsets.only(top: widget.look.barHeight), child: _page(p));

  Widget _page(IpodPage p) => switch (p) {
        MenuPage() => _MenuView(page: p, look: widget.look, player: widget.player, lit: _lit && screenPower.value),
        SearchPage() => _SearchView(page: p, look: widget.look),
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
  const _MenuView({required this.page, required this.look, required this.player, required this.lit});

  final MenuPage page;
  final ScreenLook look;
  final PlayerController player;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final entries = page.entries;
    if (entries.isEmpty) return look.empty();
    final parts = page.kind == MenuKind.split ? look.split(look.size) : null;
    if (parts == null) return _list(entries);
    // Menu scindé : la liste d'un côté, l'image de la ligne choisie de
    // l'autre (sur les écrans qui le font). On a alors l'écran entier.
    return LayoutBuilder(builder: (context, box) {
      final selected = entries[page.selected.clamp(0, entries.length - 1)];
      return Stack(
        children: [
          Positioned.fromRect(rect: parts.image, child: look.preview(selected, player, active: lit)),
          Positioned.fromRect(rect: parts.menu, child: ClipRect(child: _list(entries))),
        ],
      );
    });
  }

  Widget _list(List<MenuEntry> entries) {
    final top = page.topSpring.value;
    final visibleRows = look.rowsFor(page.kind);
    final rowH = look.rowHeightFor(page.kind);
    final scrollable = entries.length > visibleRows;
    final right = scrollable ? look.scrollbarWidth : 0.0;
    final first = top.floor().clamp(0, entries.length);
    final last = (first + visibleRows + 1).clamp(0, entries.length);

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
            child: look.row(entries[i], selected: i == page.selected, kind: page.kind),
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

// --- Recherche -------------------------------------------------------------------

/// Ce qu'on a tapé, les morceaux trouvés, et en bas la réglette de lettres
/// (la case choisie sous le bandeau de sélection).
class _SearchView extends StatelessWidget {
  const _SearchView({required this.page, required this.look});

  final SearchPage page;
  final ScreenLook look;

  @override
  Widget build(BuildContext context) {
    final rowH = look.rowHeight;
    final ink = look.textStyle.color!;
    return LayoutBuilder(builder: (context, box) {
      final stripH = rowH + 2;
      final rows = ((box.maxHeight - stripH - rowH) / rowH).floor().clamp(0, 99);
      final cellW = (look.textStyle.fontSize ?? 12) * 1.75;
      final pos = page.cellSpring.value;
      final cx = box.maxWidth / 2;
      final results = page.results;
      return Stack(
        children: [
          // Ce qu'on a tapé (ou le mode d'emploi), et le nombre de morceaux.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: rowH,
            child: look.row(
              MenuEntry(
                page.query.isEmpty ? tr('Choisir des lettres') : '${page.query}_',
                value: page.query.isEmpty ? null : () => '${results.length}',
              ),
              selected: false,
            ),
          ),
          Positioned(left: 0, right: 0, top: rowH - 0.5, height: 1, child: ColoredBox(color: ink.withValues(alpha: 0.35))),
          for (var i = 0; i < rows && i < results.length; i++)
            Positioned(
              left: 0,
              right: 0,
              top: (i + 1) * rowH,
              height: rowH,
              child: Opacity(opacity: 0.75, child: look.row(MenuEntry(results[i].title), selected: false)),
            ),
          Positioned(left: 0, right: 0, bottom: stripH - 0.5, height: 1, child: ColoredBox(color: ink.withValues(alpha: 0.35))),
          Positioned(left: cx - cellW / 2, bottom: 1, width: cellW, height: rowH, child: look.highlight()),
          for (var i = 0; i < SearchPage.cells; i++)
            if (((i - pos) * cellW).abs() < cx + cellW)
              Positioned(
                left: cx + (i - pos) * cellW - cellW / 2,
                bottom: 1,
                width: cellW,
                height: rowH,
                child: Center(child: _cell(i, i == page.cell ? look.selectedInk : ink)),
              ),
        ],
      );
    });
  }

  /// Une case de la réglette : une lettre, ou le dessin de la touche
  /// (espace, effacer : toutes les polices n'ont pas ces signes).
  Widget _cell(int i, Color color) {
    final size = look.textStyle.fontSize ?? 12;
    return switch (i) {
      SearchPage.space => Icon(Icons.space_bar_rounded, size: size * 1.15, color: color),
      SearchPage.delete => Icon(Icons.backspace_outlined, size: size, color: color),
      _ => Text(
          SearchPage.cellLabel(i),
          maxLines: 1,
          softWrap: false,
          // « OK » tient dans une case.
          style: TextStyle(color: color, fontSize: i == SearchPage.done ? size * 0.82 : null),
        ),
    };
  }
}
