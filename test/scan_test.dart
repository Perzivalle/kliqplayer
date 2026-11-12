import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/sources/local/scan.dart';

void main() {
  test('un sous-dossier illisible ou un lien en boucle ne vide pas la bibliothèque', () async {
    final root = Directory.systemTemp.createTempSync('scan');
    addTearDown(() {
      Process.runSync('chmod', ['-R', '755', root.path]);
      root.deleteSync(recursive: true);
    });
    for (final f in ['a/1.mp3', 'b/2.flac', 'ferme/3.mp3']) {
      File('${root.path}/$f').createSync(recursive: true);
    }
    Link('${root.path}/a/boucle').createSync(root.path);
    Link('${root.path}/a/casse.mp3').createSync('/nulle/part');
    Process.runSync('chmod', ['000', '${root.path}/ferme']);

    final library = await scanLibrary(root);
    expect([for (final t in library.tracks) t.title]..sort(), ['1', '2']);
    expect(library.albums.length, 2);
  }, skip: Platform.isWindows ? 'chmod' : null);
}
