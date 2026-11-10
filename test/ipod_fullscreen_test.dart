import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/ipod.dart';

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
  });
}
