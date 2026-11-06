import 'dart:math' as math;

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
import 'package:lecteur/ipod/screen.dart';
import 'package:lecteur/ipod/shuffle.dart';

const _window = Size(460, 760);

/// Le tiroir dans cette fenêtre : 230 px de large (50 % de la fenêtre,
/// au moins 230), dont 28 restent engagés derrière l'iPod une fois ouvert ;
/// au tout début de l'ouverture, son bord extérieur part de 32 px en retrait
/// du flanc de l'iPod.
const double _drawerW = 230, _tuck = 28, _hideBack = 32;
const double _openOut = _drawerW - _tuck;

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

Rect _device(WidgetTester tester) => tester.getRect(find.byType(IpodDevice));

Rect _drawerRect(WidgetTester tester) => tester.getRect(find.byType(IpodDrawer));

/// Rangé et au repos : il n'est même plus dessiné (caché derrière l'iPod).
bool _stowed(WidgetTester tester) => find.byType(IpodDrawer).evaluate().isEmpty;

/// Côté du tiroir : 1 à droite de l'iPod, -1 à gauche.
int _side(WidgetTester tester) => _drawerRect(tester).center.dx > _device(tester).center.dx ? 1 : -1;

/// De combien le bord extérieur du tiroir dépasse du flanc de l'iPod
/// (négatif : il est rangé derrière).
double _out(WidgetTester tester) {
  final d = _device(tester), r = _drawerRect(tester);
  return _side(tester) > 0 ? r.right - d.right : d.left - r.left;
}

/// Une poignée : derrière le coin du haut, à droite (1) ou à gauche (-1).
Offset _handle(WidgetTester tester, int side) {
  final d = _device(tester);
  final y = d.top + 36 * d.width / 412 + 10 + 23; // sous l'arrondi du coin
  return Offset(side > 0 ? d.right + 6 : d.left - 6, y);
}

/// Glisse pas à pas (pour que la vitesse au lâcher soit réaliste).
Future<void> _drag(WidgetTester tester, Offset from, Offset by, {Duration over = const Duration(milliseconds: 400)}) async {
  // À la souris, comme en vrai : un glissé au doigt ferait défiler la liste.
  final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  const steps = 20;
  for (var i = 0; i < steps; i++) {
    await g.moveBy(by / steps.toDouble(), timeStamp: over * ((i + 1) / steps));
    await tester.pump(over ~/ steps);
  }
  await g.up();
}

void main() {
  testWidgets('rangé, il est caché derrière l\'iPod', (tester) async {
    await _show(tester);
    expect(_stowed(tester), isTrue);
  });

  testWidgets('tirer la poignée de droite le fait sortir à droite', (tester) async {
    await _show(tester);
    await _drag(tester, _handle(tester, 1), const Offset(150, 0));
    await _settle(tester);
    expect(_side(tester), 1);
    expect(_out(tester), moreOrLessEquals(_openOut, epsilon: 0.5));
  });

  testWidgets('un clic sur la poignée de gauche le fait sortir à gauche', (tester) async {
    await _show(tester);
    await tester.tapAt(_handle(tester, -1));
    await _settle(tester);
    expect(_side(tester), -1);
    expect(_out(tester), moreOrLessEquals(_openOut, epsilon: 0.5));
    // Ouvert et refermé, l'iPod revient au centre.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(_device(tester).center.dx, moreOrLessEquals(_window.width / 2, epsilon: 0.5));
  });

  testWidgets('le tiroir suit la main pendant qu\'on le tire', (tester) async {
    await _show(tester);
    final g = await tester.startGesture(_handle(tester, 1), kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(6, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 60 px tirés : il est sorti d'autant.
    expect(_out(tester), moreOrLessEquals(-_hideBack + 60, epsilon: 0.5));
    await g.up();
    await _settle(tester);
  });

  testWidgets('lâché doucement avant la moitié, il se referme', (tester) async {
    await _show(tester);
    await _drag(tester, _handle(tester, 1), const Offset(60, 0), over: const Duration(seconds: 2));
    await _settle(tester);
    expect(_stowed(tester), isTrue);
  });

  testWidgets('un petit coup sec suffit à l\'ouvrir', (tester) async {
    await _show(tester);
    await _drag(tester, _handle(tester, -1), const Offset(-50, 0), over: const Duration(milliseconds: 60));
    await _settle(tester);
    expect(_side(tester), -1);
    expect(_out(tester), moreOrLessEquals(_openOut, epsilon: 0.5));
  });

  testWidgets('trop tiré, il résiste puis revient en place', (tester) async {
    await _show(tester);
    await tester.tapAt(_handle(tester, 1));
    await _settle(tester);
    final r = _drawerRect(tester);
    final g = await tester.startGesture(Offset(r.right - 40, r.center.dy), kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(20, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 400 px de trop : l'élastique en laisse passer bien moins.
    final over = _out(tester) - _openOut;
    expect(over, inInclusiveRange(10, 0.4 * _drawerW));
    await g.up();
    await _settle(tester);
    expect(_out(tester), moreOrLessEquals(_openOut, epsilon: 0.5));
    expect(_drawerRect(tester).center.dy, moreOrLessEquals(_device(tester).center.dy, epsilon: 0.5));
  });

  testWidgets('lancé vers l\'iPod, il se range', (tester) async {
    await _show(tester);
    await tester.tapAt(_handle(tester, 1));
    await _settle(tester);
    final r = _drawerRect(tester);
    await _drag(tester, Offset(r.right - 40, r.center.dy), const Offset(-40, 0), over: const Duration(milliseconds: 50));
    await _settle(tester);
    expect(_stowed(tester), isTrue);
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
    expect(_stowed(tester), isTrue, reason: 'le tiroir se referme une fois branché');
  });

  testWidgets('clic sur une pastille : cet appareil, dans cette teinte, en main', (tester) async {
    await _show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    // Cachées tant qu'on ne survole pas l'emplacement.
    // Le dernier « Violet » du tiroir : celui du nano 4G (le shuffle 2G en a un aussi).
    final violet = find.byTooltip('Violet').last;
    final nano4 = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'nano4');
    await tester.ensureVisible(nano4); // le tiroir défile jusqu'à lui
    await _settle(tester);
    await mouse.moveTo(tester.getCenter(nano4));
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

  testWidgets('h j k l : naviguer dans les menus comme dans vim', (tester) async {
    await _show(tester);
    final device = find.byType(IpodDevice);
    bool shows(String t) => find.descendant(of: device, matching: find.text(t)).evaluate().isNotEmpty;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ); // Réglages
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK); // Musique
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL); // entre dans Musique
    await _settle(tester);
    expect(shows('Artistes'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH); // revient
    await _settle(tester);
    expect(shows('Artistes'), isFalse);
    expect(shows('Réglages'), isTrue);
  });

  testWidgets('glisser le boîtier ne fait rien d\'autre (déplace la fenêtre)', (tester) async {
    await _show(tester);
    final d = _device(tester);
    // Sous l'écran, sur le boîtier : ni tiroir, ni menu ne bougent.
    await _drag(tester, Offset(d.center.dx, d.top + d.height * 0.47), const Offset(120, 40));
    await _settle(tester);
    expect(_stowed(tester), isTrue);
    expect(_device(tester), d);
  });

  testWidgets('shuffle : pas d\'écran, le bouton central lance la lecture et le voyant s\'allume', (tester) async {
    final player = PlayerController.preview();
    tester.view
      ..physicalSize = _window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          type: MaterialType.transparency,
          child: IpodStage(player: player, initial: Shuffle4Model(shuffle4Colors.first)),
        ),
      ),
    );
    await _settle(tester);
    expect(find.byType(IpodScreen), findsNothing);
    await tester.tapAt(tester.getCenter(find.byType(IpodWheel)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(player.playing, isTrue);
    await _settle(tester);
  });

  testWidgets('changer pour un modèle d\'un autre format : le tiroir change de taille en douceur', (tester) async {
    await _show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    final shuffle = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'shuffle4');
    await tester.ensureVisible(shuffle);
    await _settle(tester);
    await tester.tap(shuffle, kind: PointerDeviceKind.mouse);
    final heights = <double>[];
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final f = find.byType(IpodDrawer);
      if (f.evaluate().isNotEmpty) heights.add(tester.getSize(f).height);
    }
    expect(find.byWidgetPredicate((w) => w is IpodDevice && w.model is Shuffle4Model), findsOneWidget);
    var jump = 0.0;
    for (var i = 1; i < heights.length; i++) {
      jump = math.max(jump, (heights[i] - heights[i - 1]).abs());
    }
    expect(heights.first - heights.last, greaterThan(20), reason: 'le tiroir a bien changé de taille');
    expect(jump, lessThan(20), reason: 'sans saut d\'une image à l\'autre');
  });

  testWidgets('l\'emplacement vide hors de vue : le tiroir défile jusqu\'à lui avant le rangement', (tester) async {
    await _show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    final classicSlot = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'classic', skipOffstage: false);
    Rect view() => tester.getRect(find.byType(Scrollable).first);
    // Le tiroir est en haut : l'emplacement du Classic, plus bas, n'est pas visible.
    final slot = find.byType(IpodDrawer);
    expect(tester.getRect(slot).height, greaterThan(0));
    final classicTop = tester.getRect(find.ancestor(of: classicSlot, matching: find.byType(SizedBox)).first).top;
    expect(classicTop, greaterThan(view().bottom), reason: 'hors de vue au départ');
    await tester.tap(find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'gen1'), kind: PointerDeviceKind.mouse);
    // Le temps que la prise sorte : le tiroir a défilé.
    var seenStowing = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final empty = find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_ImprintPainter');
    for (final e in empty.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      if (r.center.dy > view().top && r.center.dy < view().bottom) seenStowing = true;
    }
    expect(seenStowing, isTrue, reason: 'l\'emplacement vide est revenu dans le tiroir');
    // Rangé tout en bas : le tiroir remonte jusqu'à la 1re génération avant
    // qu'elle s'en envole.
    final gen1Label = find.text('1RE GÉNÉRATION', skipOffstage: false);
    bool gen1Visible() {
      final r = tester.getRect(gen1Label);
      return r.top >= view().top && r.bottom <= view().bottom;
    }
    expect(gen1Visible(), isFalse, reason: 'le tiroir a défilé vers le bas pour le rangement');
    // Il doit y être avant le vol (≈ 1 s) : plus tard, il ne ferait que
    // suivre l'appareil déjà sorti.
    int? seenAt;
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      // (Une fois branché, le tiroir se referme et disparaît.)
      if (seenAt == null && find.byType(Scrollable).evaluate().isNotEmpty && gen1Label.evaluate().isNotEmpty) {
        if (gen1Visible()) seenAt = i;
      }
    }
    expect(seenAt, isNotNull, reason: 'le tiroir est remonté jusqu\'à l\'emplacement du nouvel appareil');
    expect(seenAt, lessThan(40), reason: 'avant que le nouvel appareil s\'envole');
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

  testWidgets('un shuffle joue toujours au hasard, sans toucher au réglage Lecture aléatoire', (tester) async {
    final player = PlayerController.preview();
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
    expect(player.shuffling, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    final shuffle1Slot = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'shuffle1');
    await tester.ensureVisible(shuffle1Slot);
    await _settle(tester);
    await tester.tap(shuffle1Slot, kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(player.shuffling, isTrue, reason: 'shuffle en main');
    expect(player.shuffle, isFalse, reason: 'le réglage, lui, ne change pas');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    final classicSlot = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'classic');
    await tester.ensureVisible(classicSlot);
    await _settle(tester);
    await tester.tap(classicSlot, kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(player.shuffling, isFalse, reason: 'de retour sur un appareil à écran');
  });
}
