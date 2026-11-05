import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/player.dart';
import 'nav.dart';

/// Apparence de l'écran d'un modèle : la logique (menus, transitions,
/// défilement) est commune, seul le dessin change.
abstract class ScreenLook {
  const ScreenLook();

  /// Résolution logique de l'interface.
  Size get size;
  double get rowHeight;
  int get visibleRows;
  double get scrollbarWidth;

  /// Style de texte par défaut et fond de l'écran.
  TextStyle get textStyle;
  Color get background;

  Widget statusBar({required String title, required bool playing, required bool hasTrack});

  /// Bandeau de la ligne sélectionnée.
  Widget highlight();
  Widget row(MenuEntry entry, {required bool selected});
  CustomPainter scrollbar(double start, double extent);
  Widget empty();
  Widget nowPlaying(PlayerController player, NowPlayingMode mode);
}

// --- Texte défilant ---------------------------------------------------------

/// Texte sur une ligne qui, s'il est trop long et [active], défile vers la
/// gauche jusqu'à sa fin, s'y arrête, puis revient au début (comme sur
/// l'appareil). Sinon il est coupé par « … ».
class Marquee extends StatefulWidget {
  const Marquee(this.text, {super.key, this.style, this.active = true});

  final String text;
  final TextStyle? style;
  final bool active;

  @override
  State<Marquee> createState() => MarqueeState();
}

class MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  static const _pause = 1.4; // secondes à chaque bout
  static const _speed = 34.0; // pixels par seconde

  late final Ticker _ticker = createTicker(_tick);
  double _overflow = 0;
  double _offset = 0;

  @override
  void didUpdateWidget(Marquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.active != widget.active) {
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

