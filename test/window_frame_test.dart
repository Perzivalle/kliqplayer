import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/ipod.dart';
import 'package:lecteur/ipod/nanos.dart';

void main() {
  const screen = Rect.fromLTWH(0, 0, 1920, 1080);

  test('prise en haut : la fenêtre monte jusqu\'en haut de l\'écran', () {
    const m = ClassicModel();
    final device = Rect.fromLTWH(800, 300, m.size.width, m.size.height);
    final f = windowFrameFor(m, device, screen);
    expect(f.top, 0);
    expect(f.bottom, device.bottom + m.margin.bottom);
    expect(f.left, lessThan(device.left));
    expect(f.right, greaterThan(device.right));
    expect(f.center.dx, closeTo(device.center.dx, 0.01), reason: 'centrée sur l\'appareil, tiroir rentré');
  });

  test('prise en bas : la fenêtre descend jusqu\'en bas de l\'écran', () {
    final m = Nano4Model(nano4Colors.first);
    final device = Rect.fromLTWH(800, 200, m.size.width, m.size.height);
    final f = windowFrameFor(m, device, screen);
    expect(f.top, device.top - m.margin.top);
    expect(f.bottom, 1080);
  });

  test('tiroir sorti : la fenêtre s\'élargit de son côté seulement', () {
    const m = ClassicModel();
    final device = Rect.fromLTWH(800, 300, m.size.width, m.size.height);
    final closed = windowFrameFor(m, device, screen);
    final right = windowFrameFor(m, device, screen, drawerSide: 1, drawerRoom: 300);
    final left = windowFrameFor(m, device, screen, drawerSide: -1, drawerRoom: 300);
    expect(right.left, closed.left);
    expect(right.right, closed.right + 300);
    expect(left.left, closed.left - 300);
    expect(left.right, closed.right);
  });

  test('appareil remonté au-dessus de l\'écran : la fenêtre le suit', () {
    const m = ClassicModel();
    final device = Rect.fromLTWH(800, -50, m.size.width, m.size.height);
    expect(windowFrameFor(m, device, screen).top, -50 - m.margin.top);
  });
}
