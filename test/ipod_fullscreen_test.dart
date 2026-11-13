import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/ipod.dart';
import 'package:lecteur/ipod/nav.dart';
import 'package:lecteur/ipod/vintage.dart';

void main() {
  group('découpe de la fenêtre', () {
    test('l\'appareil et son câble : un seul contour, du câble étroit au boîtier large', () {
      final outline = outlineOf(const [
        Rect.fromLTRB(100, 200, 500, 900), // l'appareil
        Rect.fromLTRB(350, 0, 450, 200), // le câble, jusqu'en haut
      ]);
      expect(outline, const [
        Offset(450, 0), Offset(450, 200), Offset(500, 200), Offset(500, 900),
        Offset(100, 900), Offset(100, 200), Offset(350, 200), Offset(350, 0),
      ]);
    });

    test('des zones qui se chevauchent : le bord le plus à gauche et le plus à droite à chaque hauteur', () {
      final outline = outlineOf(const [Rect.fromLTRB(0, 0, 100, 100), Rect.fromLTRB(50, 50, 200, 150)]);
      expect(outline, const [
        Offset(100, 0), Offset(100, 50), Offset(200, 50), Offset(200, 100), Offset(200, 150),
        Offset(50, 150), Offset(50, 100), Offset(0, 100), Offset(0, 50), Offset(0, 0),
      ]);
    });

    test('rien à englober : pas de contour', () {
      expect(outlineOf(const [Rect.zero]), isEmpty);
    });
  });

  group('zone de travail', () {
    const first = (bounds: Rect.fromLTWH(0, 0, 1920, 1080), work: Rect.fromLTWH(0, 0, 1920, 1032));
    const second = (bounds: Rect.fromLTWH(1920, 0, 2560, 1440), work: Rect.fromLTWH(1920, 0, 2560, 1392));

    test('celle de l\'écran où est la fenêtre', () {
      expect(workAreaFor(const Rect.fromLTWH(700, 200, 400, 700), [first, second]), first.work);
      expect(workAreaFor(const Rect.fromLTWH(2500, 200, 400, 700), [first, second]), second.work);
    });

    test('barre des tâches masquée : une ligne de moins que l\'écran, pour ne pas passer pour du plein écran', () {
      const hidden = (bounds: Rect.fromLTWH(0, 0, 1920, 1080), work: Rect.fromLTWH(0, 0, 1920, 1080));
      expect(workAreaFor(const Rect.fromLTWH(0, 0, 400, 700), [hidden]), const Rect.fromLTWH(0, 0, 1920, 1079));
    });

    test('aucun écran connu : rien', () {
      expect(workAreaFor(const Rect.fromLTWH(0, 0, 400, 700), const []), isNull);
    });
  });

  group('rangée par Windows, ou seulement déplacée', () {
    const area = Rect.fromLTWH(0, 0, 1920, 1032);
    const fill = Size(1920, 1032);

    test('elle couvre la zone de travail (même agrandie, à quelques points près) : plein écran', () {
      expect(windowFit(area, area, fill), WindowFit.fills);
      expect(windowFit(area.inflate(8), area, fill), WindowFit.fills);
    });

    test('rangée à gauche, dans un quart ou dans une colonne : elle y reste', () {
      expect(windowFit(const Rect.fromLTWH(0, 0, 960, 1032), area, fill), WindowFit.docked);
      expect(windowFit(const Rect.fromLTWH(960, 516, 960, 516), area, fill), WindowFit.docked);
      expect(windowFit(const Rect.fromLTWH(1280, 0, 640, 1032), area, fill), WindowFit.docked);
    });

    test('rangée en haut ou en bas (toute la largeur, la moitié de la hauteur) : elle y reste', () {
      expect(windowFit(const Rect.fromLTWH(0, 0, 1920, 516), area, fill), WindowFit.docked);
    });

    test('passée sur un écran plus grand en gardant sa taille : on la recale', () {
      const bigger = Rect.fromLTWH(1920, 0, 2560, 1392);
      expect(windowFit(const Rect.fromLTWH(2240, 180, 1920, 1032), bigger, fill), WindowFit.refit);
    });

    test('sortie de sa zone à la souris, à sa taille de plein écran : on la recale', () {
      expect(windowFit(const Rect.fromLTWH(300, 120, 1920, 1032), area, fill), WindowFit.refit);
    });

    test('plus grande que l\'écran où elle arrive : on la recale', () {
      expect(windowFit(const Rect.fromLTWH(0, 0, 2560, 1392), area, const Size(2560, 1392)), WindowFit.refit);
    });
  });

  group('lâché après avoir été tenu', () {
    const window = Size(1400, 800);

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('l\'iPod part d\'où on l\'a posé et glisse jusqu\'à sa place', (tester) async {
      tester.view
        ..physicalSize = window
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
      await settle(tester);
      final home = tester.getRect(find.byType(IpodDevice));

      // Lâché 300 à droite et 120 plus bas que sa place, dans la même fenêtre.
      final dynamic stage = tester.state(find.byType(IpodStage));
      stage.debugGlideHome(home.center + const Offset(300, 120), Offset.zero & window);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final start = tester.getRect(find.byType(IpodDevice));
      expect(start.center.dx, greaterThan(home.center.dx + 250));
      expect(start.center.dy, greaterThan(home.center.dy + 90));

      // En chemin : entre les deux.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final midway = tester.getRect(find.byType(IpodDevice));
      expect(midway.center.dx, lessThan(start.center.dx));
      expect(midway.center.dx, greaterThan(home.center.dx));

      await settle(tester);
      final end = tester.getRect(find.byType(IpodDevice));
      expect(end.center.dx, closeTo(home.center.dx, 0.5));
      expect(end.center.dy, closeTo(home.center.dy, 0.5));
    });

    testWidgets('position libre : lâché, il reste là, entier dans la fenêtre ; position fixe, il revient à sa place', (tester) async {
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      IpodStage.debugDragInside = true;
      ipodFree.value = true;
      addTearDown(() {
        IpodStage.debugDragInside = false;
        ipodFree.value = false;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            type: MaterialType.transparency,
            child: IpodStage(player: PlayerController.preview(), initial: const ClassicModel()),
          ),
        ),
      );
      await settle(tester);
      final home = tester.getRect(find.byType(IpodDevice));

      // (Peu de jeu en hauteur : l'iPod prend presque toute la fenêtre.)
      final gesture = await tester.startGesture(Offset(home.left + 12, home.center.dy));
      await gesture.moveBy(const Offset(-30, 5));
      await gesture.moveBy(const Offset(-220, 10));
      await tester.pump();
      final held = tester.getRect(find.byType(IpodDevice));
      await gesture.up();
      await settle(tester);
      expect(tester.getRect(find.byType(IpodDevice)).center, held.center, reason: 'il reste où on l\'a lâché');

      // Tiroir sorti : il ne retourne pas au milieu.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await settle(tester);
      final open = tester.getRect(find.byType(IpodDevice));
      expect(open.center.dx, closeTo(held.center.dx, 1), reason: 'la place ne manque pas à droite : il ne bouge pas');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await settle(tester);
      expect(tester.getRect(find.byType(IpodDevice)).center, held.center, reason: 'tiroir rentré : de retour où on l\'a lâché');

      // Lâché à moitié hors de la fenêtre : ramené en entier dedans.
      final out = await tester.startGesture(held.center - const Offset(60, 0));
      await out.moveBy(const Offset(30, 10));
      await out.moveBy(const Offset(4000, 0));
      await tester.pump();
      await out.up();
      await settle(tester);
      final kept = tester.getRect(find.byType(IpodDevice));
      expect(kept.right, lessThanOrEqualTo(window.width));
      expect(kept.center.dx, greaterThan(held.center.dx));

      // Là, contre le bord droit, le tiroir n'a pas la place : l'iPod s'écarte juste assez, puis y retourne.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await settle(tester);
      final pushed = tester.getRect(find.byType(IpodDevice));
      expect(pushed.center.dx, lessThan(kept.center.dx));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await settle(tester);
      expect(tester.getRect(find.byType(IpodDevice)).center.dx, closeTo(kept.center.dx, 1));

      // Position fixe : il retourne à sa place.
      ipodFree.value = false;
      await settle(tester);
      final end = tester.getRect(find.byType(IpodDevice));
      expect(end.center.dx, closeTo(home.center.dx, 0.5));
      expect(end.center.dy, closeTo(home.center.dy, 0.5));
    });

    testWidgets('tenu, il suit le pointeur dans la fenêtre ; lâché, il revient à sa place', (tester) async {
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      IpodStage.debugDragInside = true;
      addTearDown(() => IpodStage.debugDragInside = false);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            type: MaterialType.transparency,
            child: IpodStage(player: PlayerController.preview(), initial: const ClassicModel()),
          ),
        ),
      );
      await settle(tester);
      final home = tester.getRect(find.byType(IpodDevice));

      // Attrapé par le boîtier, à côté de l'écran.
      final gesture = await tester.startGesture(Offset(home.left + 12, home.center.dy));
      await gesture.moveBy(const Offset(30, 10));
      await gesture.moveBy(const Offset(220, 70));
      await tester.pump();
      // Il a suivi, en largeur comme en hauteur, et y reste tant qu'on le tient.
      final held = tester.getRect(find.byType(IpodDevice));
      expect(held.center.dx - home.center.dx, greaterThan(200));
      expect(held.center.dy - home.center.dy, greaterThan(60));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(find.byType(IpodDevice)).center, held.center);

      await gesture.up();
      await settle(tester);
      final end = tester.getRect(find.byType(IpodDevice));
      expect(end.center.dx, closeTo(home.center.dx, 0.5));
      expect(end.center.dy, closeTo(home.center.dy, 0.5));
    });

    testWidgets('grande fenêtre : chaque modèle garde la taille qu\'il a dans sa propre fenêtre', (tester) async {
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      IpodStage.debugDragInside = true;
      addTearDown(() => IpodStage.debugDragInside = false);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            type: MaterialType.transparency,
            child: IpodStage(player: PlayerController.preview(), initial: const FirstGenModel()),
          ),
        ),
      );
      await settle(tester);
      // 680 de haut dessiné ; dans sa fenêtre de 740 (148 pour le câble, 40
      // de marge), il en fait 552. Pareil ici, malgré toute la place.
      expect(tester.getRect(find.byType(IpodDevice)).height, closeTo(552, 0.5));
    });
  });
}
