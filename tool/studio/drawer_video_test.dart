// Studio : la petite vidéo de l'encadré « A drawer of iPods » du site. Une
// souris monte au coin de l'iPod, tire la poignée, le tiroir s'ouvre, elle
// choisit le mini : l'iPod se débranche, retourne au tiroir, le mini sort et
// se branche. Images (30 par seconde) dans build/studio/drawer/, puis :
//   flutter test tool/studio/drawer_video_test.dart && tool/studio/drawer_video.sh
// shortcut: le parcours de la souris est réglé à la main pour une fenêtre de
// 620 × 760 ; à refaire si le tiroir ou les poignées changent de place.
// (Hors de test/, l'analyseur ne sait pas que c'est un outil de test.)
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/ipod/drawer.dart';
import 'package:lecteur/ipod/ipod.dart';
import 'package:lecteur/ipod/nanos.dart';

import 'studio.dart';

const _out = 'build/studio/drawer';
const _frame = Duration(microseconds: 33333); // 30 images par seconde

void main() {
  setUpStudio(_out);

  testWidgets('tiroir : ouvrir, changer d\'iPod', (tester) async {
    for (final f in Directory(_out).listSync()) {
      f.deleteSync();
    }
    final player = PlayerController.preview(
      tracks: [const Track(id: '/x/a.mp3', title: 'Song', artist: 'Artist', album: 'Album')],
      albums: [const Album(title: 'Album', artist: 'Artist', firstIndex: 0, trackCount: 1)],
      index: 0,
    );
    await showStage(tester, player, Nano5Model(nano5Colors.firstWhere((c) => c.name == 'bleu')), size: const Size(620, 760));

    var n = 0, t = Duration.zero, at = const Offset(600, 740), down = false;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    Future<void> shoot() async {
      await tester.pump(_frame);
      t += _frame;
      await captureFrame(tester, '$_out/f${(n++).toString().padLeft(4, '0')}.png', cursor: at, pressed: down);
    }

    Future<void> hold(double seconds) async {
      for (var i = 0; i < seconds * 30; i++) {
        await shoot();
      }
    }

    // Va en [to] en [seconds], en douceur (départ et arrivée lents).
    Future<void> glide(Offset to, double seconds) async {
      final from = at, steps = (seconds * 30).round();
      for (var i = 1; i <= steps; i++) {
        final k = i / steps, e = k < .5 ? 4 * k * k * k : 1 - math.pow(-2 * k + 2, 3) / 2;
        at = Offset.lerp(from, to, e.toDouble())!;
        await mouse.moveTo(at, timeStamp: t);
        await shoot();
      }
    }

    final device = tester.getRect(find.byType(IpodDevice));
    // La poignée de droite, derrière le coin du haut (comme test/ipod_drawer_test.dart).
    final handle = Offset(device.right + 6, device.top + 36 * device.width / 412 + 10 + 23);

    await hold(0.4);
    await glide(handle + const Offset(-30, 20), 1.0); // vers le coin : la poignée sort
    await glide(handle, 0.3);
    await hold(0.3);
    down = true;
    await mouse.down(at);
    await shoot();
    await glide(handle + const Offset(170, 0), 0.6); // tire : le tiroir s'ouvre
    await mouse.up();
    down = false;
    await hold(0.6);

    final mini = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'mini');
    await glide(tester.getCenter(mini), 0.9); // survol : il se soulève
    await hold(0.5);
    down = true;
    await mouse.down(at);
    await shoot();
    await mouse.up();
    down = false;
    await glide(at + const Offset(70, 160), 0.7); // la souris s'écarte, l'échange se joue
    await hold(3.4);
    await mouse.removePointer();
  });
}
