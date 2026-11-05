import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../physics.dart';

/// Bout de papier scotché sur le bac : on y écrit l'artiste ou l'album
/// qu'on cherche. Il se soulève quand on écrit et tremble si rien ne
/// correspond.
class SearchNote extends StatefulWidget {
  const SearchNote({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCancel,
    required this.noMatch,
  });

  static const Size size = Size(310, 172);

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onCancel;
  final bool noMatch;

  @override
  State<SearchNote> createState() => _SearchNoteState();
}

class _SearchNoteState extends State<SearchNote> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  final _lift = Spring(0, stiffness: 300, damping: 0.7);
  final _shake = Spring(0, stiffness: 1400, damping: 0.16);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_wake);
  }

  @override
  void didUpdateWidget(covariant SearchNote old) {
    super.didUpdateWidget(old);
    if (widget.noMatch && !old.noMatch) {
      _shake.velocity = 700;
      _wake();
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_wake);
    _ticker.dispose();
    super.dispose();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    final step = dt.clamp(0.0, 0.05);
    _lift.step(widget.focusNode.hasFocus ? 1 : 0, step);
    _shake.step(0, step);
    setState(() {});
    if (_lift.isSettled && _shake.isSettled) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    const size = SearchNote.size;
    final lift = _lift.value;
    const ink = Color(0xFF233A86);
    return Transform.translate(
      offset: Offset(_shake.value, -10 * lift),
      child: Transform.rotate(
        angle: -0.07 + 0.04 * lift,
        child: Transform.scale(
          scale: 1 + 0.05 * lift,
          child: GestureDetector(
            onTap: widget.focusNode.requestFocus,
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: CustomPaint(painter: _PaperPainter(lift))),
                  Positioned(
                    left: 50,
                    right: 16,
                    top: 46,
                    child: CallbackShortcuts(
                      bindings: {const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel},
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        onChanged: widget.onChanged,
                        onSubmitted: (_) => widget.onSubmitted(),
                        onTapOutside: (_) =>
                            widget.focusNode.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild),
                        inputFormatters: [LengthLimitingTextInputFormatter(28)],
                        cursorColor: ink,
                        cursorWidth: 2.5,
                        cursorHeight: 34,
                        style: const TextStyle(fontFamily: 'Caveat', fontSize: 44, height: 1, color: ink),
                        decoration: const InputDecoration.collapsed(
                          hintText: 'je cherche…',
                          hintStyle: TextStyle(fontFamily: 'Caveat', fontSize: 44, height: 1, color: Color(0x667A7468)),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 310 / 2 - 62,
                    top: -16,
                    child: _Tape(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tape extends StatelessWidget {
  const _Tape();

  @override
  Widget build(BuildContext context) =>
      Transform.rotate(angle: 0.06, child: const CustomPaint(size: Size(124, 34), painter: _TapePainter()));
}

/// Papier ligné déchiré en bas, un peu jauni.
class _PaperPainter extends CustomPainter {
  const _PaperPainter(this.lift);

  final double lift;

  Path _outline(Size s) {
    final rnd = math.Random(42);
    final path = Path()
      ..moveTo(0, 2)
      ..lineTo(s.width, 0)
      ..lineTo(s.width - 1, s.height - 14);
    // Bord inférieur déchiré.
    for (var x = s.width - 1; x > 0; x -= 7) {
      path.lineTo(x, s.height - 10 + (rnd.nextDouble() - 0.5) * 9);
    }
    path
      ..lineTo(1, s.height - 8)
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _outline(size);
    canvas.drawShadow(path, Colors.black, 3 + 9 * lift, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [Color(0xFFF8F3E6), Color(0xFFEEE5CE)],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.clipPath(path);
    final rule = Paint()
      ..strokeWidth = 1.4
      ..color = const Color(0xAA8FA9D4);
    for (var y = 38.0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }
    canvas.drawLine(
      const Offset(38, 0),
      Offset(38, size.height),
      Paint()
        ..strokeWidth = 1.6
        ..color = const Color(0x99D96A6A),
    );
    // Pli léger.
    canvas.drawLine(
      Offset(size.width * 0.62, 0),
      Offset(size.width * 0.7, size.height),
      Paint()
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.drawLine(
      Offset(size.width * 0.62 + 2, 0),
      Offset(size.width * 0.7 + 2, size.height),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.04),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PaperPainter old) => old.lift != lift;
}

/// Ruban de masquage, translucide, aux bouts dentelés.
class _TapePainter extends CustomPainter {
  const _TapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final path = Path()..moveTo(0, 0);
    path.lineTo(size.width, 0);
    for (var y = 0.0; y <= size.height; y += 4) {
      path.lineTo(size.width - rnd.nextDouble() * 4, y);
    }
    path.lineTo(0, size.height);
    for (var y = size.height; y >= 0; y -= 4) {
      path.lineTo(rnd.nextDouble() * 4, y);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFFEDE2BF).withValues(alpha: 0.85), const Color(0xFFDCCDA2).withValues(alpha: 0.85)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
