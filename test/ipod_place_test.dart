import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/ipod.dart';

/// Une fenêtre bien plus large que l'iPod : de la place sur les côtés.
const _window = Size(1000, 700);

Future<void> _show(WidgetTester tester) async {
  tester.view
    ..physicalSize = _window
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        type: MaterialType.transparency,
        child: IpodStage(player: PlayerController.preview(), initial: const ClassicModel()),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 150; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Rect _device(WidgetTester tester) => tester.getRect(find.byType(IpodDevice));

/// Un point dans la zone du bouton de déplacement de ce côté (juste hors
/// du flanc, sous la poignée du tiroir).
Offset _moveButton(WidgetTester tester, int side) {
  final dev = _device(tester);
  const m = ClassicModel();
  final corner = m.cornerRadius * dev.width / m.size.width;
  final y = dev.top + corner + 10 + 46 + 8 + 15;
  return Offset(side < 0 ? dev.left - 12 : dev.right + 12, y);
}

Future<void> _click(WidgetTester tester, TestGesture mouse, Offset at) async {
  await mouse.moveTo(at);
  await _settle(tester);
  await mouse.down(at);
  await mouse.up();
  await _settle(tester);
}

void main() {
  testWidgets('les boutons sous les poignées décalent l\'iPod d\'un cran', (tester) async {
    await _show(tester);
    final centered = _device(tester);
    expect(centered.center.dx, closeTo(_window.width / 2, 1));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(5, 5));

    // Du milieu à gauche.
    await _click(tester, mouse, _moveButton(tester, -1));
    final left = _device(tester);
    expect(left.left, lessThan(40));
    expect(left.width, closeTo(centered.width, 0.01));

    // Déjà à gauche : le bouton gauche ne fait plus rien.
    await _click(tester, mouse, _moveButton(tester, -1));
    expect(_device(tester).left, closeTo(left.left, 0.01));

    // De gauche au milieu, puis à droite.
    await _click(tester, mouse, _moveButton(tester, 1));
    expect(_device(tester).center.dx, closeTo(_window.width / 2, 1));
    await _click(tester, mouse, _moveButton(tester, 1));
    expect(_device(tester).right, greaterThan(_window.width - 40));

    // Et de droite au milieu.
    await _click(tester, mouse, _moveButton(tester, -1));
    expect(_device(tester).center.dx, closeTo(_window.width / 2, 1));
  });

  testWidgets('cliquer ailleurs à côté de l\'iPod ne le déplace pas', (tester) async {
    await _show(tester);
    final before = _device(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(5, 5));
    await _click(tester, mouse, const Offset(60, 40));
    await _click(tester, mouse, Offset(before.left - 12, before.bottom - 40));
    expect(_device(tester).center.dx, closeTo(before.center.dx, 0.01));
  });
}
