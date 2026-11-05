import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/drawer.dart';
import 'package:lecteur/ipod/ipod.dart';
import 'package:lecteur/ipod/mini.dart';

const _window = Size(460, 760);

/// Largeur du tiroir pour cette fenêtre (36 % bornés à 190–300).
const double _drawerW = 190;

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

/// Laisse les ressorts se poser.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 150; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Bord gauche du tiroir, ou null s'il est rangé.
double? _drawerLeft(WidgetTester tester) {
  final f = find.byType(IpodDrawer);
  return f.evaluate().isEmpty ? null : tester.getTopLeft(f).dx;
}

/// Glisse pas à pas (pour que la vitesse au lâcher soit réaliste).
Future<void> _drag(WidgetTester tester, Offset from, Offset by, {Duration over = const Duration(milliseconds: 400)}) async {
  final g = await tester.startGesture(from);
  const steps = 20;
  for (var i = 0; i < steps; i++) {
    await g.moveBy(by / steps.toDouble(), timeStamp: over * ((i + 1) / steps));
    await tester.pump(over ~/ steps);
  }
  await g.up();
}

void main() {
  testWidgets('tirer depuis le bord de la fenêtre ouvre le tiroir', (tester) async {
    await _show(tester);
    expect(_drawerLeft(tester), isNull);
    await _drag(tester, Offset(_window.width - 10, 380), const Offset(-150, 0));
    await _settle(tester);
    expect(_drawerLeft(tester), moreOrLessEquals(_window.width - _drawerW, epsilon: 0.5));
  });

  testWidgets('le tiroir suit la main pendant qu\'on le tire', (tester) async {
    await _show(tester);
    final g = await tester.startGesture(Offset(_window.width - 10, 380));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(-6, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 60 px tirés : le tiroir est exactement sous le pointeur.
    expect(_drawerLeft(tester)!, moreOrLessEquals(_window.width - 60, epsilon: 0.5));
    await g.up();
    await _settle(tester);
  });

  testWidgets('lâché doucement avant la moitié, il se referme', (tester) async {
    await _show(tester);
    await _drag(tester, Offset(_window.width - 10, 380), const Offset(-60, 0), over: const Duration(seconds: 2));
    await _settle(tester);
    expect(_drawerLeft(tester), isNull);
  });

  testWidgets('un petit coup sec suffit à l\'ouvrir', (tester) async {
    await _show(tester);
    await _drag(tester, Offset(_window.width - 10, 380), const Offset(-50, 0), over: const Duration(milliseconds: 60));
    await _settle(tester);
    expect(_drawerLeft(tester), moreOrLessEquals(_window.width - _drawerW, epsilon: 0.5));
  });

  testWidgets('trop tiré, il résiste puis revient en place', (tester) async {
    await _show(tester);
    await _drag(tester, Offset(_window.width - 10, 380), const Offset(-150, 0));
    await _settle(tester);
    final g = await tester.startGesture(Offset(_window.width - _drawerW + 10, 380));
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(-20, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 400 px de trop : l'élastique en laisse passer bien moins.
    final over = (_window.width - _drawerW) - _drawerLeft(tester)!;
    expect(over, inInclusiveRange(10, 0.35 * _drawerW));
    await g.up();
    await _settle(tester);
    expect(_drawerLeft(tester), moreOrLessEquals(_window.width - _drawerW, epsilon: 0.5));
    expect(tester.getTopLeft(find.byType(IpodDrawer)).dy, moreOrLessEquals(0, epsilon: 0.5));
  });

  testWidgets('lancé vers la droite, il se range', (tester) async {
    await _show(tester);
    await _drag(tester, Offset(_window.width - 10, 380), const Offset(-150, 0));
    await _settle(tester);
    await _drag(tester, Offset(_window.width - _drawerW + 10, 380), const Offset(40, 0), over: const Duration(milliseconds: 50));
    await _settle(tester);
    expect(_drawerLeft(tester), isNull);
  });

  testWidgets('choisir un autre modèle : débranché, rangé, sorti, branché', (tester) async {
    await _show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    final mini = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'mini');
    expect(mini, findsOneWidget);
    await tester.tap(mini);
    await tester.pump();
    // Pendant l'échange, le Classic est encore en main.
    expect(find.byWidgetPredicate((w) => w is IpodDevice && w.model is ClassicModel), findsOneWidget);
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byWidgetPredicate((w) => w is IpodDevice && w.model is MiniModel), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is IpodDevice && w.model is ClassicModel), findsNothing);
    expect(_drawerLeft(tester), isNull, reason: 'le tiroir se referme une fois branché');
  });

  testWidgets('la musique se coupe quand on débranche, et reprend au branchement', (tester) async {
    final player = PlayerController.preview(playing: true);
    tester.view
      ..physicalSize = _window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          type: MaterialType.transparency,
          child: IpodStage(player: player, initial: const ClassicModel()),
        ),
      ),
    );
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    await tester.tap(find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'mini'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(player.playing, isFalse, reason: 'prise arrachée');
    // Encore débranchée pendant que les appareils volent.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(player.playing, isFalse);
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(player.playing, isTrue, reason: 'rebranchée');
  });
}
