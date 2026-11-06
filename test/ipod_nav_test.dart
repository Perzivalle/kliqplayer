import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/core/strings.dart';
import 'package:lecteur/ipod/click.dart';
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
  test('Cover Flow : part de l\'album en cours, la molette fait défiler, bute aux bouts', () {
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
  });

  test('Cover Flow : valider retourne la pochette, la molette parcourt ses morceaux, MENU la remet', () async {
    final player = _player();
    final nav = IpodNav(player, look: const ClassicLook());
    _open(nav, 'Musique');
    _open(nav, 'Cover Flow');
    final cf = nav.page as CoverFlowPage;
    nav.select();
    expect(cf.flipped, isTrue);
    expect(nav.page, same(cf), reason: 'on reste dans Cover Flow');
    expect(cf.track, 0, reason: 'le morceau 4 est le 1er du 3e album');
    expect(nav.scroll(1), isTrue);
    expect(cf.track, 1);
    expect(cf.selected, 2, reason: "la molette ne change plus d'album");
    expect(nav.scroll(1), isFalse, reason: 'deux morceaux par album');
    nav.select();
    await pumpEventQueue();
    expect(player.playing, isTrue, reason: 'valider joue le morceau');
    expect(cf.flipped, isTrue, reason: 'on reste au dos de la pochette');
    nav.menu();
    expect(cf.flipped, isFalse);
    expect(nav.page, same(cf), reason: 'MENU remet la pochette, sans quitter Cover Flow');
    nav.menu();
    expect(nav.page.title, 'Musique');
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

  test('Tonalité du clic : on entend chaque tonalité en parcourant, valider la garde', () {
    final click = WheelClick.instance;
    final nav = IpodNav(_player(), look: const ClassicLook());
    _open(nav, 'Réglages');
    _open(nav, 'Tonalité du clic');
    expect(click.preview, 2, reason: 'arrive sur la tonalité en cours');
    nav.scroll(2);
    expect(click.preview, 4);
    expect(click.pitch, 2, reason: 'parcourir ne change rien');
    nav.select();
    expect(click.pitch, 4);
    expect(nav.page.title, 'Tonalité du clic', reason: 'on reste pour comparer');
    nav.menu();
    expect(click.preview, isNull, reason: 'hors du menu, la tonalité choisie');
    click.pitch = 2;
  });

  test('Langue : les menus ouverts se traduisent sur place', () {
    addTearDown(() => Lang.set(Lang.fr));
    final nav = IpodNav(_player(), look: const ClassicLook());
    _open(nav, 'Réglages');
    _open(nav, 'Langue');
    _open(nav, 'English');
    expect(nav.page.title, 'Language');
    nav.menu();
    expect(nav.page.title, 'Settings');
    expect((nav.page as MenuPage).entries.map((e) => e.label), contains('Click Tone'));
    nav.menu();
    expect((nav.page as MenuPage).entries.first.label, 'Music');
  });
}
