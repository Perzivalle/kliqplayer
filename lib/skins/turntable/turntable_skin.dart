import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/player.dart';
import '../../physics.dart';
import '../skin.dart';
import 'crate.dart';
import 'painters.dart';
import 'table.dart';

class TurntableSkin extends Skin {
  const TurntableSkin();

  @override
  String get name => 'Platine';

  /// Le bac à gauche, la platine à droite (elle chevauche un peu sa marge).
  static const double turntableLeft = CrateGeometry.width - 20;
  static const Size scene = Size(turntableLeft + G.width, G.height);

  @override
  Size get windowSize => Size(scene.width * 0.6, scene.height * 0.6);

  /// La scène, posée au milieu d'une table en bois qui remplit la fenêtre.
  @override
  Widget build(PlayerController player) => LayoutBuilder(
        builder: (context, box) {
          final scale = math.min(box.maxWidth / scene.width, box.maxHeight / scene.height) * 0.94;
          return Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(child: CustomPaint(painter: TablePainter(scale))),
              Center(
                child: SizedBox(
                  width: scene.width * scale,
                  height: scene.height * scale,
                  child: FittedBox(child: TurntableStage(player: player)),
                ),
              ),
            ],
          );
        },
      );
}

/// Le bac et la platine côte à côte ; le disque choisi vole de l'un à l'autre.
class TurntableStage extends StatefulWidget {
  const TurntableStage({super.key, required this.player});

  final PlayerController player;

  @override
  State<TurntableStage> createState() => _TurntableStageState();
}

class _Flight {
  _Flight(this.album, this.from, this.cover);

  final int album;
  final Rect from;
  final Uint8List? cover;
  final progress = Spring(0, stiffness: 46, damping: 1);
  final fade = Spring(1, stiffness: 120, damping: 1);
  bool landed = false;
}

class _TurntableStageState extends State<TurntableStage> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  _Flight? _flight;

  static final _platter = const Offset(TurntableSkin.turntableLeft, 0) + G.center;

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _pick(int album, Rect sleeve) {
    final player = widget.player;
    if (_flight != null) return;
    // On soulève le bras le temps de changer de disque.
    if (player.playing) player.pause();
    _flight = _Flight(album, sleeve, player.albumCovers[album]);
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    setState(() {});
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    final step = dt.clamp(0.0, 0.05);
    final f = _flight;
    if (f == null) {
      _ticker.stop();
      return;
    }
    f.progress.step(1, step);
    if (!f.landed && f.progress.value > 0.985) {
      f.landed = true;
      widget.player.playAlbum(f.album);
    }
    if (f.landed) f.fade.step(0, step);
    if (f.landed && f.fade.value < 0.01) {
      _flight = null;
      _ticker.stop();
      setState(() {});
    }
    _frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TurntableSkin.scene.width,
      height: TurntableSkin.scene.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: CrateGeometry.width,
            height: CrateGeometry.height,
            child: Crate(player: widget.player, onPick: _pick),
          ),
          Positioned(
            left: TurntableSkin.turntableLeft,
            top: 0,
            width: G.width,
            height: G.height,
            child: Turntable(player: widget.player),
          ),
          if (_flight != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder(
                  valueListenable: _frame,
                  builder: (_, _, _) => _flyingDisc(_flight!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _flyingDisc(_Flight f) {
    final p = f.progress.value.clamp(0.0, 1.0);
    final start = f.from.center;
    // Courbe de Bézier : le disque sort par le haut puis plane vers le plateau.
    final control = Offset((start.dx + _platter.dx) / 2, math.min(start.dy, _platter.dy) - 320);
    final q = 1 - p;
    final center = start * (q * q) + control * (2 * q * p) + _platter * (p * p);
    final radius = ui.lerpDouble(f.from.width * 0.46, G.recordR, p)!;
    final opacity = (math.min(1.0, p / 0.08) * f.fade.value).clamp(0.0, 1.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: Rect.fromCircle(center: center, radius: radius),
          child: Opacity(
            opacity: opacity,
            child: Transform.rotate(
              angle: p * 2.4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const RepaintBoundary(child: CustomPaint(painter: _FlyingRecordPainter())),
                  FractionallySizedBox(
                    widthFactor: G.labelR / G.recordR,
                    heightFactor: G.labelR / G.recordR,
                    child: ClipOval(
                      child: f.cover != null
                          ? Image.memory(f.cover!, fit: BoxFit.cover, cacheWidth: 300, gaplessPlayback: true)
                          : const ColoredBox(color: Color(0xFFB8322D)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Le vinyle seul, pendant qu'il passe du bac au plateau.
class _FlyingRecordPainter extends CustomPainter {
  const _FlyingRecordPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c + Offset(0, r * 0.06),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
    );
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0D0D0F));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.05);
    for (var k = 0.36; k < 0.97; k += 0.018) {
      canvas.drawCircle(c, r * k, groove);
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.sweep(
          c,
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.1),
            Colors.white.withValues(alpha: 0),
          ],
          const [0, 0.12, 0.25, 0.5, 0.62, 0.75],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Turntable extends StatefulWidget {
  const Turntable({super.key, required this.player});

  final PlayerController player;

  @override
  State<Turntable> createState() => _TurntableState();
}

enum _Drag { none, arm, knob, pitch }

class _TurntableState extends State<Turntable> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;

  PlayerController get player => widget.player;

  // Plateau : angle et vitesse angulaire (rad/s), avec inertie.
  double _rotation = 0;
  double _omega = 0;

  // Bras : ressort vers sa cible. « Parqué » = sur le repose-bras.
  final _arm = Spring(G.armRest, stiffness: 55, damping: 0.92);
  bool _parked = true;
  double? _armDragTarget;
  bool _wasPlayingBeforeLift = false;

  // Boutons, lampe, volume, variateur.
  final _startPress = Spring(0, stiffness: 600, damping: 0.6);
  final _press33 = Spring(0, stiffness: 600, damping: 0.6);
  final _press45 = Spring(0, stiffness: 600, damping: 0.6);
  final _lamp = Spring(0, stiffness: 40, damping: 1);
  final _knob = Spring(_knobAngleFor(100), stiffness: 220, damping: 0.75);
  bool _speed45 = false;
  double _pitch = 0; // -1 à 1
  String? _pressed;
  _Drag _drag = _Drag.none;

  // Bulle d'information sur le morceau.
  bool _hoverRecord = false;
  int? _shownIndex;
  DateTime _infoUntil = DateTime(0);

  static double _knobAngleFor(double volume) => 3 * math.pi / 4 + 1.5 * math.pi * (volume / 100).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    player.addListener(_onPlayer);
    _knob.value = _knobAngleFor(player.volume);
    _ticker.start();
  }

  @override
  void didUpdateWidget(covariant Turntable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != player) {
      oldWidget.player.removeListener(_onPlayer);
      player.addListener(_onPlayer);
    }
  }

  @override
  void dispose() {
    player.removeListener(_onPlayer);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onPlayer() {
    if (player.playing) _parked = false;
    if (player.index != _shownIndex) {
      _shownIndex = player.index;
      _infoUntil = DateTime.now().add(const Duration(seconds: 4));
    }
    _wake();
    setState(() {}); // pochette, titre
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  double get _rateFactor => (_speed45 ? 45 / (100 / 3) : 1) * (1 + _pitch * G.pitchRange);

  void _applyRate() => player.setRate(_rateFactor);

  // --- Animation ------------------------------------------------------------

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    final step = dt.clamp(0.0, 0.05);

    // Plateau : démarrage en ~0,7 s, freinage un peu plus long.
    final target = player.playing ? 2 * math.pi * (100 / 3) / 60 * _rateFactor : 0.0;
    final k = target > _omega ? 4.0 : 2.2;
    _omega += (target - _omega) * (1 - math.exp(-k * step));
    if (target == 0 && _omega < 0.002) _omega = 0;
    _rotation = (_rotation + _omega * step) % (2 * math.pi);

    // Bras : suit le doigt, sinon la position de lecture.
    final double armTarget;
    if (_armDragTarget != null) {
      armTarget = _armDragTarget!;
      _arm.stiffness = 700;
    } else {
      armTarget = (_parked || player.current == null) ? G.armRest : G.armAngleForProgress(player.progress);
      _arm.stiffness = 55;
    }
    _arm.step(armTarget, step);

    _startPress.step(_pressed == 'start' ? 1 : (player.playing ? 0.35 : 0), step);
    _press33.step(_pressed == '33' || !_speed45 ? 1 : 0, step);
    _press45.step(_pressed == '45' || _speed45 ? 1 : 0, step);
    _lamp.step(player.playing ? 1 : 0, step);
    _knob.step(_knobAngleFor(player.volume), step);

    _frame.value++;

    final settled = !player.playing &&
        _omega == 0 &&
        _armDragTarget == null &&
        [_arm, _startPress, _press33, _press45, _lamp, _knob].every((s) => s.isSettled) &&
        DateTime.now().isAfter(_infoUntil);
    if (settled) _ticker.stop();
  }

  // --- Gestes ---------------------------------------------------------------

  bool _onKnob(Offset p) => (p - G.knob).distance < G.knobR * 1.5;

  bool _onPitch(Offset p) =>
      (p.dx - G.pitchX).abs() < 40 && p.dy > G.pitchTop - 20 && p.dy < G.pitchBottom + 20;

  String? _buttonAt(Offset p) {
    if (G.startButton.inflate(10).contains(p)) return 'start';
    if (G.speed33.inflate(8).contains(p)) return '33';
    if (G.speed45.inflate(8).contains(p)) return '45';
    return null;
  }

  void _onTapDown(TapDownDetails d) {
    _pressed = _buttonAt(d.localPosition);
    _wake();
  }

  void _onTapUp(TapUpDetails d) {
    final pressed = _pressed;
    _pressed = null;
    switch (pressed) {
      case 'start':
        _startStop();
      case '33':
        _speed45 = false;
        _applyRate();
      case '45':
        _speed45 = true;
        _applyRate();
      default:
        // Toucher le curseur du variateur le remet à zéro (verrouillage quartz).
        if (_onPitch(d.localPosition)) {
          _pitch = 0;
          _applyRate();
        }
    }
    _wake();
  }

  void _startStop() {
    if (player.playing) {
      player.pause();
    } else {
      // Le bras quitte son repose-bras et se pose sur le disque.
      _parked = false;
      player.play();
    }
  }

  void _onPanStart(DragStartDetails d) {
    final p = d.localPosition;
    _pressed = null;
    if (G.hitsArm(p, _arm.value)) {
      _drag = _Drag.arm;
      _armDragTarget = _arm.value;
      // Soulever le bras coupe le son, comme sur une vraie platine.
      _wasPlayingBeforeLift = player.playing;
      if (player.playing) player.pause();
    } else if (_onKnob(p)) {
      _drag = _Drag.knob;
    } else if (_onPitch(p)) {
      _drag = _Drag.pitch;
      _setPitchFrom(p);
    }
    _wake();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final p = d.localPosition;
    switch (_drag) {
      case _Drag.arm:
        final v = p - G.pivot;
        _armDragTarget = G.clampArm(math.atan2(v.dy, v.dx));
      case _Drag.knob:
        player.setVolume(player.volume - d.delta.dy * 0.6);
      case _Drag.pitch:
        _setPitchFrom(p);
      case _Drag.none:
        break;
    }
    _wake();
  }

  void _onPanEnd(DragEndDetails _) {
    if (_drag == _Drag.arm && _armDragTarget != null) {
      final progress = G.progressForAngle(_armDragTarget!);
      if (progress != null && player.current != null) {
        // Pointe posée sur le disque : on lit à cet endroit.
        _parked = false;
        player.seekProgress(progress).then((_) => player.play());
      } else {
        // Reposé sur le repose-bras (ou à côté) : arrêt.
        _parked = true;
        if (_wasPlayingBeforeLift) player.pause();
      }
      _armDragTarget = null;
    }
    _drag = _Drag.none;
    _wake();
  }

  void _setPitchFrom(Offset p) {
    const mid = (G.pitchTop + G.pitchBottom) / 2;
    const half = (G.pitchBottom - G.pitchTop) / 2;
    _pitch = ((p.dy - mid) / half).clamp(-1.0, 1.0);
    _applyRate();
  }

  void _onScroll(PointerSignalEvent e) {
    if (e is PointerScrollEvent && _onKnob(e.localPosition)) {
      player.setVolume(player.volume + (e.scrollDelta.dy < 0 ? 5 : -5));
      _wake();
    }
  }

  void _onHover(PointerHoverEvent e) {
    final over = (e.localPosition - G.center).distance < G.recordR;
    if (over != _hoverRecord) {
      setState(() => _hoverRecord = over);
      _wake();
    }
  }

  MouseCursor _cursorFor(Offset p) {
    if (G.hitsArm(p, _arm.value)) return SystemMouseCursors.grab;
    if (_buttonAt(p) != null || _onKnob(p) || _onPitch(p)) return SystemMouseCursors.click;
    return SystemMouseCursors.basic;
  }

  MouseCursor _cursor = SystemMouseCursors.basic;

  // --- Construction ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cover = player.cover;
    const s = 900.0; // demi-côté du canevas du bras (assez grand pour tout le bras)
    final armBox = Rect.fromCenter(center: G.pivot, width: 2 * s, height: 2 * s);
    final shadowBox = armBox.shift(const Offset(10, 24));

    return Listener(
      onPointerSignal: _onScroll,
      child: MouseRegion(
        cursor: _cursor,
        onHover: (e) {
          _onHover(e);
          final c = _cursorFor(e.localPosition);
          if (c != _cursor) setState(() => _cursor = c);
        },
        onExit: (_) => setState(() => _hoverRecord = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: () => _pressed = null,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: SizedBox(
            width: G.width,
            height: G.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: PlinthPainter()))),

                // Étiquette : la pochette, qui tourne avec le disque.
                Positioned.fromRect(
                  rect: Rect.fromCircle(center: G.center, radius: G.labelR),
                  child: ValueListenableBuilder(
                    valueListenable: _frame,
                    builder: (_, _, child) => Transform.rotate(angle: _rotation, child: child),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      child: ClipOval(
                        key: ValueKey(cover?.hashCode ?? player.index),
                        child: cover != null
                            ? Image.memory(cover, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium)
                            : CustomPaint(painter: _DefaultLabel(player.current?.title ?? '', player.current?.artist ?? '')),
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: Rect.fromCircle(center: G.center, radius: G.labelR),
                  child: const IgnorePointer(child: CustomPaint(painter: LabelOverlayPainter())),
                ),

                // Lampe stroboscopique.
                Positioned.fromRect(
                  rect: Rect.fromCircle(center: G.lamp, radius: G.lampR * 3.2),
                  child: ValueListenableBuilder(
                    valueListenable: _frame,
                    builder: (_, _, _) => CustomPaint(painter: LampPainter(_lamp.value.clamp(0.0, 1.0))),
                  ),
                ),

                // Boutons.
                for (final (rect, spring, label, color) in [
                  (G.startButton, _startPress, 'START·STOP', const Color(0xFF5AFF82)),
                  (G.speed33, _press33, null, const Color(0xFFFF9632)),
                  (G.speed45, _press45, null, const Color(0xFFFF9632)),
                ])
                  Positioned.fromRect(
                    rect: rect,
                    child: ValueListenableBuilder(
                      valueListenable: _frame,
                      builder: (_, _, _) => CustomPaint(
                        painter: ButtonPainter(
                          pressed: spring.value.clamp(0.0, 1.2),
                          led: rect == G.startButton
                              ? _lamp.value.clamp(0.0, 1.0)
                              : (rect == G.speed33 ? !_speed45 : _speed45)
                                  ? _lamp.value.clamp(0.0, 1.0)
                                  : 0,
                          label: label,
                          ledColor: color,
                        ),
                      ),
                    ),
                  ),

                // Curseur du variateur.
                ValueListenableBuilder(
                  valueListenable: _frame,
                  builder: (_, _, _) {
                    const mid = (G.pitchTop + G.pitchBottom) / 2;
                    const half = (G.pitchBottom - G.pitchTop) / 2;
                    return Positioned(
                      left: G.pitchX - 27,
                      top: mid + _pitch * half - 14,
                      width: 54,
                      height: 28,
                      child: const CustomPaint(painter: PitchKnobPainter()),
                    );
                  },
                ),

                // Bouton de volume.
                Positioned.fromRect(
                  rect: Rect.fromCircle(center: G.knob, radius: G.knobR * 1.2),
                  child: ValueListenableBuilder(
                    valueListenable: _frame,
                    builder: (_, _, _) => CustomPaint(painter: KnobPainter(_knob.value)),
                  ),
                ),

                // Bras et son ombre (l'ombre ne tourne pas autour du même point).
                for (final (box, shadow) in [(shadowBox, true), (armBox, false)])
                  Positioned.fromRect(
                    rect: box,
                    child: IgnorePointer(
                      child: ValueListenableBuilder(
                        valueListenable: _frame,
                        builder: (_, _, child) => Transform.rotate(angle: _arm.value, child: child),
                        child: RepaintBoundary(child: CustomPaint(painter: ArmPainter(shadow: shadow))),
                      ),
                    ),
                  ),

                // Bulle d'information (au survol du disque ou au changement de morceau).
                Positioned(
                  left: G.center.dx - 300,
                  width: 600,
                  top: G.center.dy - G.recordR + 50,
                  child: IgnorePointer(
                    child: ValueListenableBuilder(
                      valueListenable: _frame,
                      builder: (_, _, _) => AnimatedOpacity(
                        opacity: (_hoverRecord || DateTime.now().isBefore(_infoUntil)) && player.current != null ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        child: _InfoPill(player: player),
                      ),
                    ),
                  ),
                ),

                if (player.loading || player.queue.isEmpty)
                  Positioned(
                    left: G.center.dx - 300,
                    width: 600,
                    top: G.center.dy + G.labelR + 40,
                    child: Text(
                      player.loading ? 'Lecture de la bibliothèque…' : 'Aucun morceau trouvé',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFB9BAC0), fontSize: 24),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bulle translucide façon iOS avec titre, artiste et album.
class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final t = player.current;
    if (t == null) return const SizedBox.shrink();
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
            color: Colors.black.withValues(alpha: 0.45),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${t.artist} · ${t.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 20)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Étiquette par défaut quand le morceau n'a pas de pochette.
class _DefaultLabel extends CustomPainter {
  const _DefaultLabel(this.title, this.artist);

  final String title;
  final String artist;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFB8322D));
    canvas.drawCircle(c, r * 0.82, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x88FAE6D2));
    void line(String text, double dy, double fontSize, FontWeight w) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: const Color(0xFFFAE6D2), fontSize: fontSize, fontWeight: w, letterSpacing: 1)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: r * 1.4);
      tp.paint(canvas, c + Offset(-tp.width / 2, dy - tp.height / 2));
    }

    line(artist.toUpperCase(), -r * 0.42, 15, FontWeight.w700);
    line(title, r * 0.42, 17, FontWeight.w500);
  }

  @override
  bool shouldRepaint(covariant _DefaultLabel old) => old.title != title || old.artist != artist;
}
