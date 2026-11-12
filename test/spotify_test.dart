import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/sources/spotify/api.dart';
import 'package:lecteur/sources/spotify/connect_engine.dart';
import 'package:lecteur/sources/spotify/key_guide.dart';
import 'package:lecteur/sources/spotify/spotify_source.dart';

Map<String, Object?> _track(String id, String name, int n, {Map<String, Object?>? album}) => {
      'type': 'track',
      'uri': 'spotify:track:$id',
      'name': name,
      'track_number': n,
      'disc_number': 1,
      'duration_ms': 200000,
      'artists': [
        {'name': 'Artiste'},
      ],
      'album': ?album,
    };

final _albumA = {
  'id': 'A',
  'uri': 'spotify:album:A',
  'name': 'Album A',
  'artists': [
    {'name': 'Artiste'},
  ],
  'images': [
    {'url': 'https://i/640', 'width': 640},
    {'url': 'https://i/300', 'width': 300},
    {'url': 'https://i/64', 'width': 64},
  ],
};

final _albumB = {'id': 'B', 'uri': 'spotify:album:B', 'name': 'Album B', 'images': const []};

/// Faux Spotify : répond aux chemins connus, note les commandes reçues.
class _FakeSpotify {
  final calls = <String>[];
  final bodies = <String, Object?>{};
  bool deviceActive = false;

  /// Un titre liké de plus (ajouté depuis une autre appli).
  bool extraLiked = false;

  /// Accepte une suite de morceaux (« uris ») mais ne la joue pas.
  bool refusesLists = false;

  /// Le morceau en cours (son uri), et chaque lecture demandée.
  String? current;
  final plays = <Map<String, Object?>>[];

  http.Client get client => MockClient((req) async {
        final path = req.url.path.replaceFirst('/v1', '');
        calls.add('${req.method} $path${req.url.hasQuery ? '?${req.url.query}' : ''}');
        if (req.body.isNotEmpty) bodies['${req.method} $path'] = jsonDecode(req.body);
        Object? body;
        switch ('${req.method} $path') {
          case 'GET /me/albums':
            body = {
              'items': [
                {
                  'added_at': '2026-01-02T00:00:00Z',
                  'album': {
                    ..._albumA,
                    'tracks': {
                      'items': [_track('a2', 'Deux', 2), _track('a1', 'Un', 1)],
                      'next': null,
                    },
                  },
                },
              ],
              'next': null,
            };
          case 'GET /me/tracks':
            body = {
              'items': [
                {'added_at': '2026-03-01T00:00:00Z', 'track': _track('b1', 'Liké', 4, album: _albumB)},
                {'added_at': '2026-03-02T00:00:00Z', 'track': _track('a1', 'Un', 1, album: _albumA)},
                if (extraLiked) {'added_at': '2026-04-01T00:00:00Z', 'track': _track('b2', 'Nouveau', 5, album: _albumB)},
              ],
              'next': null,
            };
          case 'GET /me/playlists':
            body = {
              'items': [
                {'id': 'P', 'uri': 'spotify:playlist:P', 'name': 'Ma liste'},
                {'id': 'Q', 'uri': 'spotify:playlist:Q', 'name': 'Suivie'},
              ],
              'next': null,
            };
          case 'GET /playlists/P/items':
            body = {
              'items': [
                {'added_at': null, 'item': _track('b1', 'Liké', 4, album: _albumB)},
                {'added_at': null, 'is_local': true, 'item': _track('x', 'Local', 1, album: _albumB)},
              ],
              'next': null,
            };
          case 'GET /playlists/Q/items':
            return http.Response('{"error":{"status":403,"message":"Forbidden"}}', 403);
          case 'GET /me/player/devices':
            body = {
              'devices': [
                {'id': 'T1', 'name': 'iPhone', 'type': 'Smartphone', 'is_active': true, 'is_restricted': false},
                // L'appli Spotify de ce PC : elle porte le nom de l'ordinateur.
                {'id': 'D1', 'name': Platform.localHostname, 'type': 'Computer', 'is_active': deviceActive, 'is_restricted': false},
              ],
            };
          case 'PUT /me/player/play':
            if (!deviceActive && req.url.queryParameters['device_id'] == null) {
              return http.Response('{"error":{"status":404,"message":"Player command failed: No active device found","reason":"NO_ACTIVE_DEVICE"}}', 404);
            }
            deviceActive = true;
            final play = (jsonDecode(req.body) as Map).cast<String, Object?>();
            plays.add(play);
            final offset = (play['offset'] as Map?) ?? const {};
            current = switch (play['uris']) {
              final List uris => refusesLists ? null : uris[offset['position'] as int? ?? 0] as String,
              _ => offset['uri'] as String?,
            };
            return http.Response('', 204);
          case 'GET /me/player':
            if (current == null) return http.Response('', 204);
            body = {
              'is_playing': true,
              'progress_ms': 0,
              'item': _track(current!.split(':').last, 'En cours', 1, album: _albumB),
            };
          case 'GET /tracks/a1' || 'GET /tracks/a2':
            body = _track(path.split('/').last, 'Titre', 1, album: _albumA);
          case 'GET /tracks/b1':
            body = _track('b1', 'Liké', 4, album: _albumB);
          default:
            return http.Response('', 204);
        }
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });
}

SpotifyAccount _account(_FakeSpotify fake) =>
    SpotifyAccount(clientId: 'test', client: fake.client)..auth.debugUseTokens(access: 'a', refresh: 'r');

void main() {
  test('l\'appareil de ce PC est reconnu malgré le nom réseau de macOS', () {
    expect(SpotifyAccount.sameDevice("Paul's MacBook Pro", 'Pauls-MacBook-Pro.local'), isTrue);
    expect(SpotifyAccount.sameDevice('DESKTOP-AB12', 'desktop-ab12'), isTrue);
    expect(SpotifyAccount.sameDevice('iPhone de Paul', 'Pauls-MacBook-Pro.local'), isFalse);
  });

  setUp(() => SpotifyConnectEngine.settle = const Duration(milliseconds: 5));

  test('bibliothèque : albums enregistrés et titres likés, rangés par album', () async {
    final fake = _FakeSpotify();
    final lib = await SpotifySource(_account(fake)).load();
    expect(lib.tracks.map((t) => t.title), ['Un', 'Deux', 'Liké'], reason: 'par album, puis numéro de piste, sans doublon');
    expect(lib.albums.map((a) => (a.title, a.trackCount, a.uri)), [
      ('Album A', 2, 'spotify:album:A'), // enregistré : joué tel quel
      ('Album B', 1, null), // seulement un titre liké
    ]);
    expect(lib.tracks.first.artworkUrl, 'https://i/300', reason: 'l\'image la plus proche de 300 px');
    expect(lib.tracks.first.added, DateTime.utc(2026, 3, 2), reason: 'la date la plus récente');
    expect(lib.playlists.map((l) => l.name), ['Titres likés', 'Ma liste', 'Suivie']);
    expect(lib.playlists[0].tracks?.map((t) => t.title), ['Liké', 'Un'], reason: 'dans l\'ordre de Spotify');
    expect(lib.playlists[1].tracks, isNull, reason: 'chargée à l\'ouverture');
  });

  test('listes : les siennes se parcourent, les autres se jouent entières', () async {
    final fake = _FakeSpotify();
    final lib = await SpotifySource(_account(fake)).load();
    final mine = await lib.playlists[1].load();
    expect(mine.map((t) => t.title), ['Liké'], reason: 'sans les fichiers locaux');
    await expectLater(lib.playlists[2].load(), throwsA(isA<Object>()));
    expect(lib.playlists[2].error, isNotNull);
  });

  test('lancer un album : son contexte, depuis le morceau choisi, sur ce PC', () async {
    final fake = _FakeSpotify();
    final account = _account(fake);
    final player = PlayerController(SpotifySource(account));
    addTearDown(player.dispose);
    await player.loadLibrary();
    await player.playAlbum(0, 1);
    expect(fake.calls, contains('PUT /me/player/play?device_id=D1'), reason: 'sur ce PC, même si le téléphone jouait');
    expect(fake.bodies['PUT /me/player/play'], {
      'context_uri': 'spotify:album:A',
      'offset': {'uri': 'spotify:track:a2'},
    });
    expect(player.current?.title, 'Deux');
    expect(player.playing, isTrue);
    expect(player.notice, isNull);
  });

  test('une suite de morceaux sans contexte : leurs uris', () async {
    final fake = _FakeSpotify()..deviceActive = true;
    final player = PlayerController(SpotifySource(_account(fake)));
    addTearDown(player.dispose);
    await player.loadLibrary();
    await player.playTracks(player.tracks, 2);
    expect(fake.bodies['PUT /me/player/play'], {
      'uris': ['spotify:track:a1', 'spotify:track:a2', 'spotify:track:b1'],
      'offset': {'position': 2},
    });
  });

  test('une suite de morceaux acceptée mais pas jouée : chaque morceau lancé dans son album', () async {
    final fake = _FakeSpotify()
      ..deviceActive = true
      ..refusesLists = true;
    final player = PlayerController(SpotifySource(_account(fake)));
    addTearDown(player.dispose);
    await player.loadLibrary();
    // (a1, a2, b1)
    await player.playTracks(player.tracks, 1);
    expect(fake.plays, hasLength(2), reason: 'les uris, puis le morceau dans son album');
    expect(fake.plays.last, {
      'context_uri': 'spotify:album:A',
      'offset': {'uri': 'spotify:track:a2'},
    });
    expect(player.playing, isTrue);
    expect(player.current?.title, 'Deux');

    // Suivant : le suivant de notre file (un autre album), pas de l'album.
    await player.next();
    expect(fake.plays.last, {
      'context_uri': 'spotify:album:B',
      'offset': {'uri': 'spotify:track:b1'},
    });
    expect(player.current?.title, 'Liké');

    // Précédent, au début du morceau : retour dans notre file.
    await player.previous();
    expect(fake.plays.last['offset'], {'uri': 'spotify:track:a2'});

    // Une fois le refus constaté, on n'essaie plus les uris.
    await player.playTracks(player.tracks, 0);
    expect(fake.plays.last, {
      'context_uri': 'spotify:album:A',
      'offset': {'uri': 'spotify:track:a1'},
    });
    expect(fake.plays.where((p) => p.containsKey('uris')), hasLength(1));
  });

  test('pas d\'appareil du tout : un message, pas de plantage', () async {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/devices')) return http.Response('{"devices":[]}', 200);
      if (req.url.path.endsWith('/me/player/play')) {
        return http.Response('{"error":{"status":404,"reason":"NO_ACTIVE_DEVICE"}}', 404);
      }
      return http.Response('', 204);
    });
    final account = SpotifyAccount(clientId: 'test', client: client)..auth.debugUseTokens(access: 'a', refresh: 'r');
    final p = PlayerController(SpotifySource(account));
    addTearDown(p.dispose);
    await p.playUri('spotify:playlist:Q');
    expect(p.notice, isNotNull);
  });

  cacheTests();
}

// (Ajouts : bibliothèque gardée d'un lancement à l'autre, appareil retenu.)
void cacheTests() {
  /// Attend que [done] soit vrai (au plus 10 s).
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('bibliothèque gardée : servie tout de suite, puis remplacée si elle a changé', () async {
    final dir = Directory.systemTemp.createTempSync('lecteur-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/spotify-library.json');
    final fake = _FakeSpotify();
    // Premier lancement : rien de gardé, on demande à Spotify et on garde.
    final first = await SpotifySource(_account(fake), cache: file).load();
    await pumpEventQueue();
    expect(file.existsSync(), isTrue);

    // Deuxième lancement, la même : servie sans attendre, rien à signaler.
    // (Assez vieille pour être redemandée : ici, tout de suite.)
    final again = SpotifySource(_account(fake), cache: file, refreshAfter: Duration.zero);
    var changed = 0;
    again.onChanged = () => changed++;
    fake.calls.clear();
    final kept = await again.load();
    expect(fake.calls.where((c) => c.startsWith('GET /me/albums')), isEmpty, reason: 'servie avant toute réponse de Spotify');
    expect(kept.tracks.map((t) => t.id), first.tracks.map((t) => t.id));
    expect(kept.albums.map((a) => a.uri), first.albums.map((a) => a.uri));
    expect(kept.playlists.map((l) => l.name), ['Titres likés', 'Ma liste', 'Suivie']);
    // (Le temps que la vraie soit arrivée et comparée.)
    await until(() => fake.calls.any((c) => c.startsWith('GET /me/playlists')));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(changed, 0);

    // Troisième lancement, un titre liké en plus entre-temps.
    fake.extraLiked = true;
    final later = SpotifySource(_account(fake), cache: file, refreshAfter: Duration.zero);
    later.onChanged = () => changed++;
    expect((await later.load()).tracks, hasLength(3), reason: 'd\'abord celle d\'avant');
    await until(() => changed == 1);
    expect(changed, 1);
    expect((await later.load()).tracks, hasLength(4));
  });

  test('Spotify demande d\'attendre longtemps : on ne lui demande plus rien d\'ici là', () async {
    var sent = 0;
    final account = SpotifyAccount(
      clientId: 'test',
      client: MockClient((req) async {
        sent++;
        return http.Response('{"error":{"status":429,"message":"API rate limit exceeded"}}', 429,
            headers: {'retry-after': '600'});
      }),
    )..auth.debugUseTokens(access: 'a', refresh: 'r');

    Object? first, second;
    try {
      await account.api.get('/me');
    } catch (e) {
      first = e;
    }
    expect(sent, 1);
    expect(first, isA<SpotifyError>().having((e) => e.message, 'message', contains('10 min')));

    // Tout de suite après : refusé ici même, sans rien envoyer.
    try {
      await account.api.get('/me/player');
    } catch (e) {
      second = e;
    }
    expect(sent, 1);
    expect(second, isA<SpotifyError>().having((e) => e.status, 'status', 429));
  });

  test('bibliothèque gardée depuis peu : on ne la redemande pas à Spotify', () async {
    final dir = Directory.systemTemp.createTempSync('lecteur-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/spotify-library.json');
    final fake = _FakeSpotify();
    await SpotifySource(_account(fake), cache: file).load();
    await pumpEventQueue();

    // Relancé dans l'heure : celle qu'on a suffit, aucune demande.
    fake.calls.clear();
    final again = await SpotifySource(_account(fake), cache: file).load();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(again.tracks, hasLength(3));
    expect(fake.calls.where((c) => c.startsWith('GET /me/')), isEmpty);

    // Vieille d'un jour : on la redemande.
    file.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));
    await SpotifySource(_account(fake), cache: file).load();
    await until(() => fake.calls.any((c) => c.startsWith('GET /me/playlists')));
    // Inchangée : elle compte de nouveau comme récente.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(DateTime.now().difference(file.lastModifiedSync()), lessThan(const Duration(minutes: 1)));
  });

  test('l\'appareil de ce PC est retenu : pas de liste d\'appareils à chaque lecture', () async {
    final fake = _FakeSpotify()..deviceActive = true;
    final player = PlayerController(SpotifySource(_account(fake)));
    addTearDown(player.dispose);
    await player.loadLibrary();
    await player.playTracks(player.tracks, 0);
    await player.playTracks(player.tracks, 1);
    expect(fake.calls.where((c) => c == 'GET /me/player/devices'), hasLength(1));
  });

  group('clé personnelle', () {
    test('sans clé : il en faut une avant de se connecter', () async {
      final account = SpotifyAccount(client: _FakeSpotify().client);
      expect(account.needsKey, isTrue);
      expect(account.keyHint, isNull);
      await expectLater(account.connect(), throwsA(isA<NoticeException>()));
    });

    test('la clé se reconnaît dans ce qu\'on a copié, même entourée de texte', () {
      const key = '0123456789abcdef0123456789ABCDEF';
      expect(SpotifyAccount.keyIn(key), key.toLowerCase());
      expect(SpotifyAccount.keyIn('  Client ID: $key\n'), key.toLowerCase());
      expect(SpotifyAccount.keyIn('http://127.0.0.1:43819/callback'), isNull);
      expect(SpotifyAccount.keyIn('${key}0'), isNull, reason: 'trop longue : ce n\'est pas une clé');
      expect(SpotifyAccount.keyIn(''), isNull);
    });

    test('avec une clé : on la montre abrégée', () {
      final account = SpotifyAccount(clientId: '0123456789abcdef0123456789abcdef', client: _FakeSpotify().client);
      expect(account.needsKey, isFalse);
      expect(account.keyHint, '0123…cdef');
    });

    test('le guide donne le lien du tableau de bord et l\'adresse de retour', () {
      final page = spotifyKeyGuide();
      expect(page, contains('https://developer.spotify.com/dashboard/create'));
      expect(page, contains('http://127.0.0.1:43819/callback'));
      expect(page, contains('Client ID'));
    });
  });
}
