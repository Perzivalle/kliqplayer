// Studio : images du site, rendues par le vrai code de l'appli mais hors de
// l'appli (rien ici n'est livré). Chaque nano 5G joue « son » album, sur
// fond transparent, en haute définition :
//   flutter test tool/studio/nano5_lineup_test.dart
// Pochettes lues dans site/img/covers/<couleur>.jpg ; images écrites dans
// site/img/nano5/<couleur>.png. Une couleur sans pochette est sautée.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/ipod/nanos.dart';

import 'studio.dart';

/// Couleur du site (anglais) → teinte de l'appli, et ce qu'elle joue.
const _pairs = [
  ('silver', 'argent', 'Shelter from the Storm', 'Bob Dylan', 'Hard Rain', Duration(seconds: 326)),
  ('black', 'noir', 'Starless', 'King Crimson', 'Red', Duration(seconds: 738)),
  ('purple', 'violet', 'Northern Sky', 'Nick Drake', 'Bryter Layter', Duration(seconds: 227)),
  ('blue', 'bleu', 'Opening Move', 'Gryphon', 'Red Queen to Gryphon Three', Duration(seconds: 588)),
  ('green', 'vert', 'Close to the Edge', 'Yes', 'Close to the Edge', Duration(seconds: 1123)),
  ('yellow', 'jaune', 'I Am the Walrus', 'The Beatles', 'Magical Mystery Tour', Duration(seconds: 276)),
  ('orange', 'orange', 'Sir Duke', 'Stevie Wonder', 'Songs in the Key of Life', Duration(seconds: 234)),
  ('pink', 'rose', '10:15 Saturday Night', 'The Cure', 'Three Imaginary Boys', Duration(seconds: 222)),
  ('red', 'rouge', 'Birds Dont Sing', 'TV Girl', 'French Exit', Duration(seconds: 209)),
];

void main() {
  setUpStudio('site/img/nano5');

  for (final (name, tint, title, artist, album, length) in _pairs) {
    testWidgets('nano 5G $name', (tester) async {
      final cover = File('site/img/covers/$name.jpg');
      if (!cover.existsSync()) {
        markTestSkipped('pas de pochette : ${cover.path}');
        return;
      }
      final model = Nano5Model(nano5Colors.firstWhere((c) => c.name == tint));
      await showStage(tester, playing(title, artist, album, length, cover.readAsBytesSync()), model);
      await key(tester, LogicalKeyboardKey.arrowDown, 3); // Menu › Now Playing
      await key(tester, LogicalKeyboardKey.enter);
      await decode(tester);
      await capture(tester, 'site/img/nano5/$name.png');
    });
  }
}
