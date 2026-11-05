import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/skins/ipod/ipod_skin.dart';
import 'package:lecteur/skins/ipod/classic.dart';

/// La molette seule, et le journal de ce qu'elle a déclenché.
Future<List<String>> _pumpWheel(WidgetTester tester) async {
  final log = <String>[];
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: G.wheelRadius * 2,
          height: G.wheelRadius * 2,
          child: IpodWheel(
            style: const ClassicModel().wheel,
            onScroll: (d) => log.add('scroll $d'),
            onDown: (z) => log.add('down ${z.name}'),
            onUp: (z) => log.add('up ${z.name}'),
            onCancel: () => log.add('cancel'),
          ),
        ),
      ),
    ),
  );
  return log;
}

Offset _zone(WidgetTester tester, Offset fromCenter) =>
    tester.getCenter(find.byType(IpodWheel)) + fromCenter;

void main() {
  testWidgets('clic net sur ⏭', (tester) async {
    final log = await _pumpWheel(tester);
    await tester.tapAt(_zone(tester, const Offset(100, 0)), kind: PointerDeviceKind.mouse);
    expect(log, ['down next', 'up next']);
  });

  testWidgets('clic au pavé tactile qui bouge de 3 px', (tester) async {
    final log = await _pumpWheel(tester);
    final g = await tester.startGesture(_zone(tester, const Offset(100, 0)), kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(2, 2));
    await g.moveBy(const Offset(1, 0));
    await g.up();
    expect(log, ['down next', 'up next']);
  });

  testWidgets('clic au centre', (tester) async {
    final log = await _pumpWheel(tester);
    await tester.tapAt(_zone(tester, Offset.zero), kind: PointerDeviceKind.mouse);
    expect(log, ['down center', 'up center']);
  });

  testWidgets('un vrai tour de molette fait défiler sans cliquer', (tester) async {
    final log = await _pumpWheel(tester);
    final g = await tester.startGesture(_zone(tester, const Offset(100, 0)), kind: PointerDeviceKind.mouse);
    // Quart de tour dans le sens horaire, par petits pas.
    for (var k = 1; k <= 20; k++) {
      final a = k / 20 * 3.14159 / 2;
      await g.moveTo(_zone(tester, Offset(100 * cos(a), 100 * sin(a))));
    }
    await g.up();
    expect(log.where((e) => e.startsWith('up')), isEmpty);
    expect(log.where((e) => e == 'scroll 1').length, greaterThanOrEqualTo(4));
  });
}

double cos(double a) => _c(a);
double sin(double a) => _c(a - 3.14159 / 2);
double _c(double a) {
  // cos sans dart:math pour rester bref
  var r = 1.0, t = 1.0;
  for (var n = 1; n < 12; n++) {
    t *= -a * a / ((2 * n - 1) * (2 * n));
    r += t;
  }
  return r;
}
