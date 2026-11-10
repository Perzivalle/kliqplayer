import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

ui.Image? _satinTile;

/// Carreau de grain, dessiné une fois : des points clairs et sombres, très
/// fins et serrés, sur fond transparent.
ui.Image _satin() {
  const side = 192;
  final rnd = math.Random(23);
  final light = <double>[], dark = <double>[];
  for (var i = 0; i < side * side ~/ 7; i++) {
    (rnd.nextBool() ? light : dark)
      ..add(rnd.nextDouble() * side)
      ..add(rnd.nextDouble() * side);
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRawPoints(
    ui.PointMode.points,
    Float32List.fromList(light),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 0.7,
  );
  canvas.drawRawPoints(
    ui.PointMode.points,
    Float32List.fromList(dark),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.04)
      ..strokeWidth = 0.7,
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(side, side);
  picture.dispose();
  return image;
}

final _identity = Matrix4.identity().storage;

/// Grain de l'aluminium microbillé puis anodisé : il donne un satiné plutôt
/// que des points qu'on distingue. [strength] : 1 pour une teinte moyenne,
/// moins sur les noirs et le métal poli. (Un carreau répété, peint en un
/// seul rectangle : presque gratuit, même redessiné à chaque image.)
void paintSatin(Canvas canvas, Size size, {double strength = 1}) {
  final tile = _satinTile ??= _satin();
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.ImageShader(tile, TileMode.repeated, TileMode.repeated, _identity)
      ..color = Colors.white.withValues(alpha: strength.clamp(0.0, 1.0)),
  );
}

/// Les deux ombres sous un appareil qui flotte : une large et diffuse, une
/// plus serrée.
void paintFloatShadow(Canvas canvas, RRect outer, {double drop = 22, double blur = 24}) {
  canvas.drawRRect(
    outer.shift(Offset(0, drop)).deflate(8),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.32)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
  );
  canvas.drawRRect(
    outer.shift(const Offset(0, 5)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );
}
