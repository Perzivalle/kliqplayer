import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/settings.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/core/strings.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/drawer.dart';
import 'package:lecteur/ipod/ipod.dart';
import 'package:lecteur/ipod/mini.dart';
import 'package:lecteur/ipod/model.dart';
import 'package:lecteur/ipod/nanos.dart';
import 'package:lecteur/ipod/screen.dart';
import 'package:lecteur/ipod/shuffle.dart';
import 'package:lecteur/ipod/vintage.dart';

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
    // L'éventail ne s'ouvre qu'au survol de l'emplacement.
    // Le dernier « Violet » du tiroir : celui du nano 4G (le shuffle 2G en a un aussi).
    final violet = _swatch('Violet').last;
    final nano4 = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'nano4');
    await tester.ensureVisible(nano4); // le tiroir défile jusqu'à lui
    await _settle(tester);
    await mouse.moveTo(tester.getCenter(nano4));
    await _settle(tester);
    // Les cartes de l'éventail se chevauchent : on vise le coin du haut,
    // celui qu'on voit.
    final corner = tester.renderObject<RenderBox>(violet).localToGlobal(const Offset(8, 10));
    await mouse.moveTo(corner);
    await _settle(tester);
    expect(find.byWidgetPredicate((w) => w is IpodPreview && w.model.id == Nano4Model(nano4Colors[2]).id), findsOneWidget,
        reason: 'l\'éventail montre la teinte');
    final violetNano = Nano4Model(nano4Colors[2]).id;
    expect(screenPower.value, isTrue);
    await mouse.down(corner);
    await mouse.up();
    // Chaque chose à son tour : l'emplacement prend la teinte et l'éventail
    // se range ; on ne débranche qu'ensuite.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byWidgetPredicate((w) => w is IpodPreview && w.model.id == violetNano), findsWidgets,
        reason: 'l\'emplacement a pris la teinte');
    expect(screenPower.value, isTrue, reason: 'l\'éventail se range avant le débranchement');
    expect(find.byWidgetPredicate((w) => w is IpodDevice && w.model is ClassicModel), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(screenPower.value, isFalse, reason: 'éventail rangé : on débranche');
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byWidgetPredicate((w) => w is IpodDevice && w.model.id == Nano4Model(nano4Colors[2]).id), findsOneWidget);
  });

  testWidgets('fenêtre minuscule : des pastilles au lieu de l\'éventail', (tester) async {
    final (_, mouse) = await _hoverTopSlot(tester, const Size(340, 440), Shuffle4Model(shuffle4Colors.first), 'nano4');
    await _settle(tester);
    expect(_byType('_FanCard'), findsNothing);
    final dots = _byType('_Swatch');
    expect(dots, findsNWidgets(nano4Colors.length));
    // Survolée, une pastille habille l'appareil.
    await mouse.moveTo(tester.getCenter(dots.at(2)));
    await _settle(tester);
    expect(find.byWidgetPredicate((w) => w is IpodPreview && w.model.id == Nano4Model(nano4Colors[2]).id), findsOneWidget);
  });

  testWidgets('l\'éventail dépasserait du haut de la fenêtre : le tiroir descend l\'appareil', (tester) async {
    final (slot, _) = await _hoverTopSlot(tester, const Size(360, 520), Nano4Model(nano4Colors.first), 'gen4');
    final top = tester.getRect(find.ancestor(of: find.byType(SingleChildScrollView).last, matching: find.byType(ClipRect)).first).top;
    final before = tester.getRect(slot);
    expect(before.top - top, lessThan(before.height * 0.84 + 18), reason: 'l\'éventail ne tiendrait pas');
    await _settle(tester);
    final after = tester.getRect(slot);
    expect(after.top, greaterThan(before.top + 10));
    expect(_byType('_FanCard'), findsWidgets, reason: 'puis l\'éventail s\'ouvre');
    for (final card in _byType('_FanCard').evaluate()) {
      // Ni hors de la fenêtre, ni au-dessus du tiroir.
      expect(tester.getRect(find.byWidget(card.widget)).top, greaterThanOrEqualTo(top - 0.5));
    }
  });

  testWidgets('un appareil d\'une seule teinte se soulève aussi au survol', (tester) async {
    await _show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    final photo = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == const PhotoModel().family);
    await tester.ensureVisible(photo);
    await _settle(tester);
    final scale = find.ancestor(of: photo, matching: find.byType(AnimatedScale));
    expect(tester.widget<AnimatedScale>(scale).scale, 1);
    await mouse.moveTo(tester.getCenter(photo));
    await _settle(tester);
    expect(tester.widget<AnimatedScale>(scale).scale, greaterThan(1));
  });

  testWidgets('une teinte choisie : l\'éventail se range, même la souris dessus', (tester) async {
    await _show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    // Le Classic est en main : son emplacement (vide) propose l'autre teinte.
    final classic = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'classic');
    await tester.ensureVisible(classic.first);
    await _settle(tester);
    await mouse.moveTo(tester.getCenter(classic.first));
    await _settle(tester);
    final noir = _swatch('Noir');
    expect(noir, findsOneWidget, reason: 'l\'éventail est ouvert');
    final at = tester.getCenter(noir);
    await mouse.moveTo(at);
    await _settle(tester);
    await mouse.down(at);
    await mouse.up();
    await _settle(tester);
    expect(find.byWidgetPredicate((w) => w is IpodDevice && w.model.id == const ClassicModel(ClassicColor.noir).id), findsOneWidget);
    // La souris n'a pas bougé : l'éventail est rangé et ne se rouvre pas.
    expect(_swatch('Blanc'), findsNothing);
    expect(_swatch('Noir'), findsNothing);
    // Elle quitte l'appareil puis revient : il se rouvre.
    await mouse.moveTo(Offset.zero);
    await _settle(tester);
    await mouse.moveTo(tester.getCenter(classic.first));
    await _settle(tester);
    expect(_swatch('Blanc'), findsOneWidget);
  });

  testWidgets('en changeant d\'iPod, on reste sur le même écran', (tester) async {
    final player = PlayerController.preview(
      tracks: const [Track(id: '/x/a.flac', title: 'Néons', artist: 'Les Fréquences', album: 'Bleu nuit')],
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

  testWidgets('Réglages › Touches : Z Q S D remplace h j k l', (tester) async {
    Settings.setString('ipod.keys', 'zqsd');
    addTearDown(() => Settings.setString('ipod.keys', 'hjkl'));
    await _show(tester);
    final device = find.byType(IpodDevice);
    bool shows(String t) => find.descendant(of: device, matching: find.text(t)).evaluate().isNotEmpty;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS); // Réglages
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ); // Musique
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD); // entre dans Musique
    await _settle(tester);
    expect(shows('Artistes'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL); // plus rien en Z Q S D
    await _settle(tester);
    expect(shows('Artistes'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ); // revient
    await _settle(tester);
    expect(shows('Artistes'), isFalse);
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
    // L'écran s'éteint d'abord, puis la prise est arrachée.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
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

  testWidgets('changer de langue traduit aussi le tiroir', (tester) async {
    addTearDown(() => Lang.set(Lang.fr));
    await _show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    expect(find.text('1RE GÉNÉRATION'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    Lang.set(Lang.en);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _settle(tester);
    expect(find.text('1ST GENERATION'), findsOneWidget, reason: 'le tiroir gardé en cache doit suivre la langue');
  });

  testWidgets('En lecture : entre deux pas de la barre, plus aucune image n\'est dessinée', (tester) async {
    final player = PlayerController.preview(
      tracks: const [Track(id: '/x/a.flac', title: 'Titre', artist: 'Artiste', album: 'Album')],
      albums: const [Album(title: 'Album', artist: 'Artiste', firstIndex: 0, trackCount: 1)],
      index: 0,
      playing: true,
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
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // En lecture
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    var idle = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (!tester.binding.hasScheduledFrame) idle++;
    }
    expect(idle, greaterThan(40), reason: 'la barre avance par pas, pas à chaque image');
  });

  testWidgets('ouvrir et fermer le tiroir ne le reconstruit pas (sa photo reste prête)', (tester) async {
    await _show(tester);
    final before = tester.element(find.byType(IpodDrawer, skipOffstage: false));
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await _settle(tester);
    }
    expect(tester.element(find.byType(IpodDrawer, skipOffstage: false)), same(before));
  });
}

/// Une pastille de l'éventail, par le nom de sa teinte.
Finder _swatch(String name) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == name);

Finder _byType(String name) => find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

/// Ouvre le tiroir dans une fenêtre [window] et survole l'emplacement
/// [family], placé tout en haut de la partie visible du tiroir.
Future<(Finder, TestGesture)> _hoverTopSlot(WidgetTester tester, Size window, IpodModel model, String family) async {
  tester.view
    ..physicalSize = window
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Material(type: MaterialType.transparency, child: IpodStage(player: PlayerController.preview(), initial: model)),
  ));
  await _settle(tester);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
  await _settle(tester);
  final slot = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == family).first;
  await tester.ensureVisible(slot);
  await _settle(tester);
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isNotEmpty) {
    final top = tester.getRect(find.byType(SingleChildScrollView)).top;
    final pos = tester.state<ScrollableState>(scrollable.last).position;
    pos.jumpTo((pos.pixels + tester.getRect(slot).top - top - 4).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    await _settle(tester);
  }
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(slot));
  return (slot, mouse);
}
