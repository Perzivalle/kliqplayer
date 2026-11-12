import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/core/source.dart';
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
      tracks.add(Track(id: '/x/$i-$k.flac', title: 'Titre $i-$k', artist: 'Artiste', album: 'Album $i'));
    }
  }
  return PlayerController.preview(tracks: tracks, albums: albums, index: 4);
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
  test('une ligne disparaît d\'un menu : la sélection y reste', () {
    final player = _player()..notice = 'Erreur';
    final nav = IpodNav(player, look: const ClassicLook());
    final root = nav.page as MenuPage;
    nav.scroll(10); // la dernière ligne
    player.notice = null; // (une commande a réussi : le message s'efface)
    final count = root.entries.length;
    expect(root.selected, count - 1);
    nav.select(); // En lecture, sans erreur
    expect(nav.page, isA<NowPlayingPage>());
  });

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

  test('Listes de lecture en Cover Flow : la liste se charge en se retournant, son morceau se joue', () async {
    final tracks = [const Track(id: '/x/a.flac', title: 'A', artist: 'Artiste', album: 'Album')];
    final player = PlayerController.preview(playlists: [
      SongList('Prête', tracks),
      SongList.lazy('À charger', () async => tracks, uri: 'spotify:playlist:x'),
    ]);
    final nav = IpodNav(player, look: const ClassicLook());
    _open(nav, 'Musique');
    _open(nav, 'Listes de lecture');
    final cf = nav.page as CoverFlowPage;
    expect(cf.count(player), 4, reason: 'Ajouts récents, Les plus écoutés et les deux listes');
    nav.scroll(10);
    expect(cf.label(player, cf.selected), ('À charger', ''));
    nav.select(); // se retourne et charge
    expect(cf.flipped, isTrue);
    expect(nav.scroll(1), isFalse, reason: 'pas encore de morceaux');
    await Future<void>.delayed(Duration.zero);
    expect(cf.label(player, cf.selected), ('À charger', '1 morceau'));
    nav.select();
    expect(player.current?.id, '/x/a.flac');
    nav.menu();
    expect(cf.flipped, isFalse);

    // Sans Cover Flow (écran monochrome) : le menu d'avant.
    final mini = IpodNav(player, look: const MiniLook());
    _open(mini, 'Musique');
    _open(mini, 'Listes de lecture');
    expect(mini.page, isA<MenuPage>());
  });

  test('Cover Flow : à force de tourner, la molette saute de lettre en lettre, puis redevient normale', () {
    // Des albums rangés par artiste : trente en A, trente en B, trente en C.
    final tracks = <Track>[], albums = <Album>[];
    for (var i = 0; i < 90; i++) {
      final artist = '${'ABC'[i ~/ 30]} artiste $i';
      albums.add(Album(title: 'Album $i', artist: artist, firstIndex: i, trackCount: 1));
      tracks.add(Track(id: '/x/$i.flac', title: 'Titre $i', artist: artist, album: 'Album $i'));
    }
    final player = PlayerController.preview(tracks: tracks, albums: albums);
    var now = DateTime(2026);
    withClock(Clock(() => now), () {
      final nav = IpodNav(player, look: const ClassicLook());
      _open(nav, 'Musique');
      _open(nav, 'Cover Flow');
      final cf = nav.page as CoverFlowPage;
      void turn(int sign, int times) {
        for (var i = 0; i < times; i++) {
          now = now.add(const Duration(milliseconds: 50));
          nav.scroll(sign);
        }
      }

      turn(1, CoverFlowPage.lettersAfter);
      expect(cf.selected, CoverFlowPage.lettersAfter, reason: 'un album par cran');
      expect(cf.letters, isFalse);
      turn(1, 1);
      expect(cf.letters, isTrue);
      expect(cf.selected, 60, reason: 'le premier en C');
      expect(cf.letter(player, cf.selected), 'C');
      expect(nav.scroll(1), isFalse, reason: 'dernière lettre');
      turn(-1, 1);
      expect(cf.selected, 30, reason: 'en arrière : le premier en B');
      turn(-1, 1);
      expect(cf.selected, 0);

      now = now.add(const Duration(seconds: 2)); // la main s'arrête
      expect(cf.letters, isFalse);
      turn(1, 1);
      expect(cf.selected, 1, reason: 'de nouveau un album par cran');
    });
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

  test('Bibliothèque : depuis Spotify, choisir le même dossier revient aux fichiers', () async {
    final root = Directory.systemTemp.createTempSync('lecteur');
    addTearDown(() => root.deleteSync(recursive: true));
    final made = <String>[];
    final player = PlayerController(_NamedSource('spotify'), sourceFor: (id) {
      made.add(id);
      return _NamedSource(id);
    })
      ..musicDir = root.path;
    addTearDown(player.dispose);
    final nav = IpodNav(player, look: const ClassicLook());
    _open(nav, 'Réglages');
    _open(nav, 'Bibliothèque');
    _open(nav, 'Dossier actuel');
    final use = (nav.page as MenuPage).entries.first;
    expect(use.checked!(), isFalse, reason: 'on écoute Spotify, pas ce dossier');
    _open(nav, 'Utiliser ce dossier');
    await pumpEventQueue();
    expect(made, ['local']);
    expect(player.source.id, 'local');
  });

  test('Bibliothèque : les services en ligne en haut, sans /mnt', () {
    final player = PlayerController.preview(accounts: [_FakeAccount()]);
    final nav = IpodNav(player, look: const ClassicLook());
    _open(nav, 'Réglages');
    _open(nav, 'Bibliothèque');
    final labels = (nav.page as MenuPage).entries.map((e) => e.label).toList();
    expect(labels.take(3), ['Spotify', 'Dossier actuel', 'Dossier personnel']);
    expect(labels, isNot(contains('/mnt')));
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

/// Source sans musique, d'identifiant choisi.
class _NamedSource extends EmptySource {
  _NamedSource(this.name);

  final String name;

  @override
  String get id => name;
}

class _FakeAccount extends RemoteAccount {
  @override
  String get sourceId => 'spotify';
  @override
  String get label => 'Spotify';
  @override
  bool get connected => false;
  @override
  bool get connecting => false;
  @override
  String? get userName => null;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
}
