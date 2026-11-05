import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/drawer.dart';
import 'package:lecteur/ipod/ipod.dart';
import 'package:lecteur/ipod/mini.dart';
import 'package:lecteur/ipod/nanos.dart';

const _window = Size(460, 760);

/// Largeur du tiroir pour cette fenêtre (50 % bornés à 230–460).
const double _drawerW = 230;

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

/// Bord gauche du tiroir, ou null s'il est rangé (il attend alors hors de
/// la fenêtre, à droite, sa photo déjà prise).
double? _drawerLeft(WidgetTester tester) {
  final f = find.byType(IpodDrawer);
  if (f.evaluate().isEmpty) return null;
  final left = tester.getTopLeft(f).dx;
  return left >= _window.width ? null : left;
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

  testWidgets('clic sur une pastille : cet appareil, dans cette teinte, en main', (tester) async {
    await _show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    // Cachées tant qu'on ne survole pas l'emplacement.
    final violet = find.byTooltip('Violet');
    await mouse.moveTo(tester.getCenter(find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'nano4')));
    await _settle(tester);
    await mouse.moveTo(tester.getCenter(violet));
    await _settle(tester);
    expect(find.byWidgetPredicate((w) => w is IpodPreview && w.model.id == Nano4Model(nano4Colors[2]).id), findsOneWidget,
        reason: 'survolée, la teinte habille la miniature');
    await tester.tap(violet, kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byWidgetPredicate((w) => w is IpodDevice && w.model.id == Nano4Model(nano4Colors[2]).id), findsOneWidget);
  });

  testWidgets('en changeant d\'iPod, on reste sur le même écran', (tester) async {
    final player = PlayerController.preview(
      queue: const [Track(path: '/x/a.flac', title: 'Néons', artist: 'Les Fréquences', album: 'Bleu nuit')],
      index: 0,
      duration: const Duration(minutes: 3),
    );
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
    // Menu principal → « En lecture ».
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    final classic = find.byWidgetPredicate((w) => w is IpodDevice && w.model is ClassicModel);
    expect(find.descendant(of: classic, matching: find.text('Morceau au hasard')), findsNothing,
        reason: 'on a quitté le menu principal');
    expect(find.descendant(of: classic, matching: find.text('En lecture')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    await tester.tap(find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'mini'));
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final mini = find.byWidgetPredicate((w) => w is IpodDevice && w.model is MiniModel);
    expect(mini, findsOneWidget);
    expect(find.descendant(of: mini, matching: find.text('En lecture')), findsOneWidget);
    expect(find.descendant(of: mini, matching: find.text('Morceau au hasard')), findsNothing);
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
