// Studio : les images des encadrés du site (tiroir ouvert, « Now Playing »
// avec pochette), sur fond transparent :
//   flutter test tool/studio/features_test.dart
// Images écrites dans site/img/features/.
// (Hors de test/, l'analyseur ne sait pas que c'est un outil de test.)
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/nanos.dart';

import 'studio.dart';

void main() {
  setUpStudio('site/img/features');

  testWidgets('tiroir ouvert', (tester) async {
    final player = PlayerController.preview(
      tracks: [const Track(id: '/x/a.mp3', title: 'Song', artist: 'Artist', album: 'Album')],
      albums: [const Album(title: 'Album', artist: 'Artist', firstIndex: 0, trackCount: 1)],
      index: 0,
    );
    final model = Nano5Model(nano5Colors.firstWhere((c) => c.name == 'bleu'));
    await showStage(tester, player, model, size: const Size(620, 760));
    await key(tester, LogicalKeyboardKey.keyT);
    await frames(tester, 120);
    await capture(tester, 'site/img/features/drawer.png');
  });

  testWidgets('en lecture', (tester) async {
    const length = Duration(seconds: 234);
    final cover = File('site/img/covers/orange.jpg').readAsBytesSync();
    await showStage(tester, playing('Sir Duke', 'Stevie Wonder', 'Songs in the Key of Life', length, cover), const ClassicModel());
    await key(tester, LogicalKeyboardKey.arrowDown, 3); // Menu › Now Playing
    await key(tester, LogicalKeyboardKey.enter);
    await decode(tester);
    await capture(tester, 'site/img/features/now_playing.png');
  });
}
