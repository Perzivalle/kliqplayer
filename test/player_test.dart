import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/engine.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/core/source.dart';
import 'package:lecteur/core/version.dart';
import 'package:lecteur/ipod/nav.dart';
import 'package:lecteur/ipod/classic.dart';

/// Moteur qui note ce qu'on lui demande.
class _Engine extends SilentEngine {
  final log = <String>[];
  bool disposed = false;

  @override
  void restore({required bool shuffle, required RepeatMode repeat}) => log.add('restore $shuffle ${repeat.name}');

  @override
  Future<void> setShuffle(bool on) async => log.add('shuffle $on');

  @override
  void dispose() {
    expect(disposed, isFalse, reason: 'libéré une seule fois');
    disposed = true;
  }

  void send(EngineUpdate u) => onUpdate?.call(u);
}

/// Moteur distant (comme Spotify) : lent à obéir.
class _SlowEngine extends _Engine {
  @override
  bool get slow => true;

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> mute(bool on, double volume) async => log.add('mute $on ${volume.round()}');
}

class _Source extends MusicSource {
  _Source(this.library, {this.fail});

  Library library;
  Object? fail;
  final engines = <_Engine>[];
  bool slow = false;

  @override
  String get id => 'essai';
  @override
  String get label => 'Essai';
  @override
  Future<Library> load() async {
    if (fail case final e?) throw e;
    return library;
  }

  @override
  Future<Uint8List?> artwork(Track track) async => null;
  @override
  PlaybackEngine createEngine() {
    engines.add(slow ? _SlowEngine() : _Engine());
    return engines.last;
  }
}

Track _t(String id, {String album = 'Album', int? n, int? disc}) =>
    Track(id: id, title: id, artist: 'Artiste', album: album, trackNumber: n, discNumber: disc, duration: const Duration(minutes: 3));

Library _library(List<Track> all) {
  final (:tracks, :albums) = groupByAlbum(all);
  return Library(tracks, albums);
}

void main() {
  test('albums à plusieurs disques : disque par disque, pas piste 1, 1, 2, 2', () {
    final lib = _library([_t('d2p1', n: 1, disc: 2), _t('d1p2', n: 2, disc: 1), _t('d2p2', n: 2, disc: 2), _t('d1p1', n: 1, disc: 1)]);
    expect(lib.tracks.map((t) => t.id), ['d1p1', 'd1p2', 'd2p1', 'd2p2']);
  });

  test('un morceau lancé pendant la lecture compte pour une écoute, pas deux', () async {
    final source = _Source(_library([_t('a', n: 1), _t('b', n: 2)]));
    final p = PlayerController(source);
    addTearDown(p.dispose);
    await p.loadLibrary();
    await p.playTracks(p.tracks, 0);
    await p.playTracks(p.tracks, 1);
    await p.playTracks(p.tracks, 1);
    // « b » lancé deux fois, « a » une : b d'abord.
    expect(p.mostPlayed(5).map((t) => t.id), ['b', 'a']);
    await p.playTracks(p.tracks, 0);
    await p.playTracks(p.tracks, 0);
    expect(p.mostPlayed(5).map((t) => t.id), ['a', 'b'], reason: 'trois écoutes contre deux');
  });

  test('le moteur neuf reçoit l\'aléatoire et la répétition retenus', () async {
    final p = PlayerController(_Source(Library.empty));
    addTearDown(p.dispose);
    await p.setShuffle(true);
    final next = _Source(Library.empty);
    await p.setSource(next);
    expect(next.engines.single.log, contains('restore true off'));
    await p.setShuffle(false); // (les préférences sont communes aux tests)
  });

  test('deux changements de source rapprochés : chaque moteur libéré une fois', () async {
    final first = _Source(Library.empty);
    final p = PlayerController(first);
    final a = _Source(Library.empty), b = _Source(Library.empty);
    await Future.wait([p.setSource(a), p.setSource(b)]);
    expect(p.source, same(b));
    expect(first.engines.single.disposed, isTrue);
    expect(a.engines.single.disposed, isTrue);
    expect(b.engines.single.disposed, isFalse);
    p.dispose();
  });

  test('bibliothèque qui ne se charge pas : un message, et valider réessaie', () async {
    final source = _Source(_library([_t('a')]), fail: const NoticeException('Pas de connexion'));
    final p = PlayerController(source);
    addTearDown(p.dispose);
    await p.loadLibrary();
    expect(p.notice, 'Pas de connexion');
    expect(p.tracks, isEmpty);
    final nav = IpodNav(p, look: const ClassicModel().look);
    addTearDown(nav.dispose);
    expect((nav.page as MenuPage).entries.first.label, 'Pas de connexion', reason: 'en tête du menu principal');
    source.fail = null;
    nav.select();
    await pumpEventQueue();
    expect(p.notice, isNull);
    expect(p.tracks, hasLength(1));
  });

  test('une position seule, là où on l\'attend, ne réveille pas l\'écran', () async {
    final source = _Source(_library([_t('a')]));
    final p = PlayerController(source);
    addTearDown(p.dispose);
    await p.loadLibrary();
    await p.playTracks(p.tracks, 0);
    var woken = 0;
    p.addListener(() => woken++);
    final engine = source.engines.single;
    engine.send(EngineUpdate(position: p.smoothPosition + const Duration(milliseconds: 60)));
    expect(woken, 0);
    // Un saut (recherche faite ailleurs) : là, oui.
    engine.send(const EngineUpdate(position: Duration(seconds: 90)));
    expect(woken, 1);
    expect(p.smoothPosition.inSeconds, 90);
  });

  test('shuffle en main : l\'aléatoire de la source ne touche pas au réglage', () async {
    final source = _Source(Library.empty);
    final p = PlayerController(source);
    addTearDown(p.dispose);
    await p.setForcedShuffle(true);
    source.engines.single.send(const EngineUpdate(shuffle: true));
    expect(p.shuffle, isFalse);
    await p.setForcedShuffle(false);
    source.engines.single.send(const EngineUpdate(shuffle: true));
    expect(p.shuffle, isTrue, reason: 'sans shuffle en main, on suit la source (changé dans l\'appli Spotify)');
  });

  test('prise débranchée, moteur distant : le son est coupé, la lecture continue', () async {
    final source = _Source(_library([_t('a')]))..slow = true;
    final p = PlayerController(source);
    addTearDown(p.dispose);
    await p.loadLibrary();
    await p.playTracks(p.tracks, 0);
    await p.setVolume(70);
    final engine = source.engines.single;
    p.unplug();
    expect(engine.log, contains('mute true 70'));
    expect(engine.log, isNot(contains('pause')));
    expect(p.playing, isTrue);
    engine.send(const EngineUpdate(volume: 0, playing: true));
    expect(p.volume, 70, reason: 'le zéro de la prise débranchée n\'est pas le réglage');
    p.plug();
    expect(engine.log.last, 'mute false 70');
  });

  test('nouvelle bibliothèque : les menus ouverts sur l\'ancienne se referment', () async {
    final source = _Source(_library([_t('a'), _t('b')]));
    final p = PlayerController(source);
    addTearDown(p.dispose);
    await p.loadLibrary();
    final nav = IpodNav(p, look: const ClassicModel().look);
    addTearDown(nav.dispose);
    void go(String label) {
      final page = nav.page as MenuPage;
      nav.scroll(page.entries.indexWhere((e) => e.label == label) - page.selected);
      nav.select();
    }

    go('Musique');
    go('Albums');
    go('Album');
    expect(nav.stack, hasLength(4));
    source.library = _library([_t('c')]);
    source.onChanged!();
    await pumpEventQueue();
    expect(nav.stack.map((s) => s.title), ['Lecteur', 'Musique']);
    expect(p.tracks.single.id, 'c');
  });

  test('remplacer la suite de la file : le morceau en cours continue, puis la nouvelle suite', () async {
    final source = _Source(_library([_t('a', n: 1), _t('b', n: 2), _t('c', n: 3), _t('x', album: 'X'), _t('y', album: 'X')]));
    final p = PlayerController(source);
    addTearDown(p.dispose);
    await p.loadLibrary();
    await p.playTracks(p.tracks.sublist(0, 3), 1); // b en cours
    final x = p.tracks.firstWhere((t) => t.id == 'x'), y = p.tracks.firstWhere((t) => t.id == 'y');
    expect(await p.replaceUpcoming([y, x]), isTrue);
    expect(p.nowPlaying.map((t) => t.id), ['b', 'y', 'x']);
    expect(p.current?.id, 'b', reason: 'rien ne change pour le morceau en cours');
    await p.next();
    expect(p.current?.id, 'y', reason: 'le suivant vient de la nouvelle suite');
  });

  test('la version d\'À propos est celle du pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version: ([0-9.]+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });

  test('une version publiée plus récente se reconnaît', () {
    expect(isNewer('v0.6.6', '0.6.5'), isTrue);
    expect(isNewer('v0.10.0', '0.9.9'), isTrue);
    expect(isNewer('v1.0', '0.6.5'), isTrue);
    expect(isNewer('v0.6.5', '0.6.5'), isFalse);
    expect(isNewer('v0.6.4', '0.6.5'), isFalse);
  });

  test('Réglages propose la mise à jour quand il y en a une', () {
    final nav = IpodNav(PlayerController.preview(), look: const ClassicModel().look);
    addTearDown(() => newVersion = null);
    List<String> settings() {
      final root = nav.stack.first as MenuPage;
      final page = root.entries.firstWhere((e) => e.label == 'Réglages').open!() as MenuPage;
      return [for (final e in page.entries) e.label];
    }
    expect(settings(), isNot(contains('Mise à jour')));
    newVersion = '9.0.0';
    expect(settings().first, 'Mise à jour');
  });
}
