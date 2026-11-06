import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/mini.dart';
import 'package:lecteur/ipod/nav.dart';

PlayerController _player() {
  final tracks = <Track>[];
  final albums = <Album>[];
  for (var i = 0; i < 5; i++) {
    albums.add(Album(title: 'Album $i', artist: 'Artiste', firstIndex: tracks.length, trackCount: 2));
    for (var k = 0; k < 2; k++) {
      tracks.add(Track(path: '/x/$i-$k.flac', title: 'Titre $i-$k', artist: 'Artiste', album: 'Album $i'));
    }
  }
  return PlayerController.preview(queue: tracks, albums: albums, index: 4);
}

/// Ouvre l'entrée [label] de la page en cours.
void _open(IpodNav nav, String label) {
  final p = nav.page as MenuPage;
  final i = p.entries.indexWhere((e) => e.label == label);
  expect(i, isNot(-1), reason: '« $label » dans ${p.title}');
  nav.scroll(i - p.selected);
  nav.select();
}

void main() {
  test('Cover Flow : part de l\'album en cours, la molette fait défiler, le bouton ouvre l\'album', () {
    final nav = IpodNav(_player(), look: const ClassicLook());
    _open(nav, 'Musique');
    _open(nav, 'Cover Flow');
    final cf = nav.page as CoverFlowPage;
    expect(cf.selected, 2, reason: 'le morceau 4 est dans le 3e album');
    expect(nav.scroll(1), isTrue);
    expect(cf.selected, 3);
    nav.scroll(10);
    expect(cf.selected, 4, reason: 'bute sur le dernier');
    expect(nav.scroll(1), isFalse);
    nav.select();
    expect(nav.page.title, 'Album 4');
  });

  test('pas de Cover Flow sur un écran monochrome ; on en ressort en changeant d\'appareil', () {
    final mono = IpodNav(_player(), look: const MiniLook());
    _open(mono, 'Musique');
    expect((mono.page as MenuPage).entries.map((e) => e.label), isNot(contains('Cover Flow')));

    final nav = IpodNav(_player(), look: const ClassicLook());
    _open(nav, 'Musique');
    _open(nav, 'Cover Flow');
    nav.fitLook(const MiniLook());
    expect(nav.page.title, 'Musique');
  });

  test('Réglages : aléatoire et répétition changent à chaque appui', () {
    final player = _player();
    final nav = IpodNav(player, look: const ClassicLook());
    _open(nav, 'Réglages');
    _open(nav, 'Lecture aléatoire');
    expect(player.shuffle, isTrue);
    _open(nav, 'Répéter');
    expect(player.repeat, RepeatMode.one);
    nav.select();
    expect(player.repeat, RepeatMode.all);
    nav.select();
    expect(player.repeat, RepeatMode.off);
  });

  test('rétroéclairage : s\'éteint après le délai, se rallume au toucher', () {
    var now = DateTime(2026);
    withClock(Clock(() => now), () {
      final nav = IpodNav(_player(), look: const ClassicLook())..backlight = 5;
      expect(nav.lit, isTrue);
      now = now.add(const Duration(seconds: 6));
      expect(nav.lit, isFalse);
      nav.touch();
      expect(nav.lit, isTrue);
      nav.backlight = 0;
      now = now.add(const Duration(hours: 1));
      expect(nav.lit, isTrue, reason: 'toujours allumé');
    });
  });

  test('Bibliothèque : on parcourt les dossiers et on en choisit un', () {
    final root = Directory.systemTemp.createTempSync('lecteur');
    addTearDown(() => root.deleteSync(recursive: true));
    for (final d in ['Rock', 'Jazz', '.cache']) {
      Directory('${root.path}/$d').createSync();
    }
    final player = _player()..musicDir = root.path;
    final nav = IpodNav(player, look: const ClassicLook());
    _open(nav, 'Réglages');
    _open(nav, 'Bibliothèque');
    _open(nav, 'Dossier actuel');
    final labels = (nav.page as MenuPage).entries.map((e) => e.label).toList();
    expect(labels, ['Utiliser ce dossier', 'Jazz', 'Rock'], reason: 'triés, sans les dossiers cachés');
    _open(nav, 'Rock');
    _open(nav, 'Utiliser ce dossier');
    expect(player.musicDir, '${root.path}/Rock');
    expect(nav.page.title, 'Réglages', reason: 'choisi : retour aux Réglages');
  });
}
