// Studio : le tiroir du site. Chaque modèle de l'appli, dans chacune de ses
// teintes, seul (ni câble ni ombre : le site met la sienne), pour la scène et
// pour son empreinte dans le tiroir. Plus site/img/drawer/models.js, la liste
// lue par la page.
//   flutter test tool/studio/drawer_models_test.dart
// (Hors de test/, l'analyseur ne sait pas que c'est un outil de test.)
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/core/strings.dart';
import 'package:lecteur/ipod/ipod.dart';

import 'studio.dart';

const _out = 'site/img/drawer';

/// Année de sortie de chaque famille (ipodModels suit cet ordre).
const _years = {
  'gen1': 2001, 'gen2': 2002, 'gen3': 2003, 'mini': 2004, 'gen4': 2004, 'photo': 2004, 'shuffle1': 2005,
  'mini2': 2005, 'nano1': 2005, 'gen5': 2005, 'nano2': 2006, 'shuffle2': 2006, 'classic': 2007, 'nano': 2007,
  'nano4': 2008, 'nano5': 2009, 'shuffle4': 2010,
};

void main() {
  setUpStudio(_out);
  final list = <Map<String, Object>>[];

  for (final model in ipodModels) {
    testWidgets(model.id, (tester) async {
      final player = PlayerController.preview(
        tracks: [const Track(id: '/x/a.mp3', title: 'Song', artist: 'Artist', album: 'Album')],
        albums: [const Album(title: 'Album', artist: 'Artist', firstIndex: 0, trackCount: 1)],
        index: 0,
      );
      await showStage(tester, player, model);
      final device = tester.getRect(find.byType(IpodDevice));
      // Ses coins arrondis, à l'échelle où il est dessiné (le tiroir rangé dépasse derrière).
      final corner = model.cornerRadius * device.width / model.size.width;
      await capture(tester, '$_out/${model.id}.png', crop: device, corner: corner, scale: 2.5);
      list.add({
        'id': model.id,
        'family': model.family,
        'name': tr(model.label),
        'year': _years[model.family] ?? 0,
        'colour': tr(model.variantName),
        'swatch': '#${(model.swatch.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      });
    });
  }

  tearDownAll(() {
    // Rendu partiel (--plain-name) : la liste resterait incomplète, on garde l'ancienne.
    if (list.length != ipodModels.length) return;
    File('$_out/models.js').writeAsStringSync(
        '// Écrit par tool/studio/drawer_models_test.dart : ne pas modifier à la main.\n'
        'window.KLIQ_MODELS = ${const JsonEncoder.withIndent('  ').convert(list)};\n');
  });
}
