import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/core/settings.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/ipod.dart';
import 'package:lecteur/ipod/jack.dart';
import 'package:lecteur/ipod/screen.dart';

/// La prise telle qu'elle est peinte en ce moment (null si rien).
JackPainter? _jack(WidgetTester tester) {
  for (final e in find.byType(CustomPaint).evaluate()) {
    final painter = (e.widget as CustomPaint).painter;
    if (painter == null || !painter.runtimeType.toString().contains('LiveJack')) continue;
    final JackPainter jack = (painter as dynamic).build();
    return jack.socket == null ? null : jack;
  }
  return null;
}

void main() {
  // Au lancement, l'iPod monte débranché ; une fois arrivé, la prise
  // descend se brancher. La scène peut s'animer pendant la montée (souris
  // sur la fenêtre : les poignées sortent) : la prise doit quand même
  // attendre l'arrivée pour descendre, au lieu d'apparaître déjà branchée.
  testWidgets('la prise descend après la montée, même si la scène s\'anime pendant', (tester) async {
    tester.view
      ..physicalSize = const Size(440, 740)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Settings.setString('ipod.model', const ClassicModel().id);
    screenPower.value = false;
    ipodLanded.value = false;
    addTearDown(() => ipodLanded.value = true);
    await tester.pumpWidget(MaterialApp(
      home: Material(type: MaterialType.transparency, child: IpodStage(player: PlayerController.preview())),
    ));
    await tester.pump(const Duration(milliseconds: 16));
    // Pendant la montée, la souris passe près d'un coin du haut.
    final device = tester.getRect(find.byType(IpodDevice));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(Offset(device.right - 10, device.top + 40));
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_jack(tester), isNull, reason: 'pas de prise pendant la montée');

    ipodLanded.value = true;
    await tester.pump(const Duration(milliseconds: 16));
    final first = _jack(tester);
    expect(first, isNotNull);
    expect(first!.lift, greaterThan(JackGeometry.away * 0.9), reason: 'la prise part de loin, hors de la fenêtre');
    var descending = 0;
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final j = _jack(tester)!;
      if (j.lift > 5 && j.lift < 400) descending++;
    }
    expect(descending, greaterThan(5), reason: 'on la voit descendre');
    expect(_jack(tester)!.lift, lessThan(1), reason: 'puis elle est branchée');
    expect(screenPower.value, isTrue);
  });
}
