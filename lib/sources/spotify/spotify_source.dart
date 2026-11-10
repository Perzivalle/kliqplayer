import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

import '../../core/engine.dart';
import '../../core/library.dart';
import '../../core/paths.dart';
import '../../core/player.dart' show NoticeException;
import '../../core/settings.dart';
import '../../core/source.dart';
import '../../core/strings.dart';
import 'api.dart';
import 'auth.dart';
import 'connect_engine.dart';
import 'librespot.dart';
import 'official_app.dart';

/// L'appli déclarée chez Spotify pour TinyPod (tableau de bord développeur).
/// Ce n'est pas un secret : avec PKCE, l'identifiant seul ne permet rien.
/// Réglable (« spotify.clientId » dans settings.json) pour utiliser sa
/// propre appli.
const defaultSpotifyClientId = 'REMOVED-OLD-SHARED-CLIENT-ID';

/// Un morceau Spotify ([json] : objet « track » de l'API ; [album] : son
/// album, quand l'objet n'en porte pas, dans la liste des morceaux d'un
/// album).
Track spotifyTrack(Map<String, Object?> json, {Map<String, Object?>? album, DateTime? added}) {
  final al = (json['album'] as Map<String, Object?>?) ?? album ?? const {};
  final artists = ((json['artists'] as List?) ?? const []).whereType<Map>().map((a) => a['name'] as String? ?? '');
  return Track(
    id: json['uri'] as String? ?? '',
    title: json['name'] as String? ?? '',
    artist: artists.isEmpty ? tr('Artiste inconnu') : artists.join(', '),
    album: al['name'] as String? ?? '',
    trackNumber: (json['track_number'] as num?)?.toInt(),
    discNumber: (json['disc_number'] as num?)?.toInt(),
    duration: Duration(milliseconds: (json['duration_ms'] as num?)?.toInt() ?? 0),
    added: added,
    artworkUrl: _image(al['images']),
  );
}

/// L'image la plus proche de 300 px (assez pour Cover Flow, sans
/// télécharger la grande).
String? _image(Object? images) {
  final list = ((images as List?) ?? const []).whereType<Map>().toList();
  if (list.isEmpty) return null;
  int width(Map m) => (m['width'] as num?)?.toInt() ?? 0;
  list.sort((a, b) => (width(a) - 300).abs().compareTo((width(b) - 300).abs()));
  return list.first['url'] as String?;
}

String? _albumId(Map<String, Object?> json, Map<String, Object?>? album) =>
    ((json['album'] as Map<String, Object?>?) ?? album)?['id'] as String?;

/// Un appareil Spotify Connect du compte.
typedef SpotifyDevice = ({String id, String name, String type, bool active});

/// Le compte Spotify : connexion, appareil qui joue. Partagé par la source
/// et son moteur.
class SpotifyAccount extends RemoteAccount {
  SpotifyAccount({String? clientId, http.Client? client, this.installedLibrespot, this.app})
      : auth = SpotifyAuth(clientId: clientId ?? Settings.getString('spotify.clientId') ?? defaultSpotifyClientId, client: client) {
    api = SpotifyApi(auth, client: client);
    _userName = Settings.getString('spotify.user');
  }

  final SpotifyAuth auth;
  late final SpotifyApi api;

  /// Le lecteur intégré (librespot), s'il est installé.
  final Librespot? installedLibrespot;

  /// L'appli Spotify officielle, lancée au besoin, si elle est installée.
  final SpotifyApp? app;

  /// Le lecteur intégré, s'il est installé et choisi. Désactivé par
  /// défaut : Spotify refuse les clés de déchiffrement à librespot pour
  /// certains comptes (https://github.com/librespot-org/librespot/issues/1649),
  /// qui jouent alors en silence.
  Librespot? get librespot => builtInEnabled ? installedLibrespot : null;

  bool get builtInEnabled => installedLibrespot != null && Settings.getString('spotify.builtin') == 'on';

  /// (Réglable dans settings.json : « spotify.builtin » : « on ».)
  String? _userName;
  bool _connecting = false;

  @override
  String get sourceId => 'spotify';
  @override
  String get label => 'Spotify';
  @override
  bool get connected => auth.connected;
  @override
  bool get connecting => _connecting;
  @override
  String? get userName => _userName;

  @override
  Future<void> connect() async {
    _connecting = true;
    notifyListeners();
    try {
      await auth.login((url) async {
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw NoticeException(tr('Navigateur introuvable'));
        }
      });
      final me = await api.get('/me');
      _userName = me?['display_name'] as String? ?? me?['id'] as String?;
      if (_userName != null) Settings.setString('spotify.user', _userName!);
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  @override
  Future<void> disconnect() async {
    await auth.logout();
    _userName = null;
    Settings.setString('spotify.user', '');
    notifyListeners();
  }

  /// Les appareils Spotify Connect du compte, en ligne en ce moment.
  Future<List<SpotifyDevice>> _online() async {
    final data = await api.get('/me/player/devices');
    return [
      for (final d in ((data?['devices'] as List?) ?? const []).whereType<Map<String, Object?>>())
        if (d['id'] != null && d['is_restricted'] != true)
          (
            id: d['id'] as String,
            name: d['name'] as String? ?? '',
            type: d['type'] as String? ?? '',
            active: d['is_active'] == true,
          ),
    ];
  }

  /// Lance le lecteur intégré en avance, ou l'appli Spotify cachée (la
  /// source Spotify est en service) : le premier morceau partira sans
  /// attendre.
  void warmUp() {
    if (!connected) return;
    final l = librespot;
    if (l != null) {
      if (l.hasCredentials) l.start();
      return;
    }
    final a = app;
    if (a == null || !a.hidden || a.running) return;
    _online().then((list) {
      if (_thisPc(list) == null) a.launch().catchError((_) {});
    }, onError: (_) {});
  }

  /// L'appli Spotify de ce PC parmi [list] : elle porte le nom de
  /// l'ordinateur. (Ou le lecteur intégré, s'il est choisi.)
  SpotifyDevice? _thisPc(List<SpotifyDevice> list) {
    final name = librespot != null ? Librespot.deviceName : Platform.localHostname;
    for (final d in list) {
      if (d.name.toLowerCase() == name.toLowerCase()) return d;
    }
    return null;
  }

  /// Le lecteur intégré, lancé s'il le faut, une fois apparu parmi les
  /// appareils du compte (null s'il n'a pas pu se connecter).
  Future<SpotifyDevice?> _builtIn() async {
    final l = librespot;
    if (l == null) return null;
    // Première fois : il attend qu'on se connecte dans le navigateur.
    final patience = l.hasCredentials ? const Duration(seconds: 15) : const Duration(minutes: 3);
    await l.start();
    final until = DateTime.now().add(patience);
    while (DateTime.now().isBefore(until)) {
      final found = _thisPc(await _online());
      if (found != null) return found;
      if (!l.running) return null; // il s'est arrêté (connexion refusée…)
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  /// L'appareil de ce PC, qui joue toujours le son de TinyPod (même si le
  /// compte jouait ailleurs, sur le téléphone : la lecture revient ici).
  /// L'appli Spotify est lancée, cachée, s'il le faut.
  Future<String> thisPcDevice() async {
    if (librespot != null) {
      final built = await _builtIn();
      if (built != null) return built.id;
      throw NoticeException(tr('Lecteur intégré : échec'));
    }
    final list = await _online();
    final here = _thisPc(list);
    if (here != null) return here.id;
    final launched = await _launchApp(list);
    if (launched != null) return launched.id;
    throw NoticeException(tr('Ouvrez Spotify sur un appareil'));
  }

  /// Lance l'appli officielle et attend qu'elle apparaisse sur le compte
  /// (null si elle n'est pas installée, ou trop lente). [before] : les
  /// appareils d'avant, pour la reconnaître si elle ne porte pas le nom de
  /// l'ordinateur.
  Future<SpotifyDevice?> _launchApp(List<SpotifyDevice> before) async {
    final a = app;
    if (a == null) return null;
    try {
      await a.launch();
      final until = DateTime.now().add(const Duration(seconds: 40));
      while (DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final list = await _online();
        final here = _thisPc(list) ??
            list.where((d) => d.type == 'Computer' && !before.any((b) => b.id == d.id)).firstOrNull;
        if (here != null) return here;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  void shutdown() {
    installedLibrespot?.stop();
    app?.stop();
  }
}

/// La musique du compte Spotify : albums enregistrés, titres likés (rangés
/// par album), listes de lecture.
class SpotifySource extends MusicSource {
  SpotifySource(this.account);

  final SpotifyAccount account;
  SpotifyApi get _api => account.api;

  @override
  String get id => 'spotify';
  @override
  String get label => 'Spotify';

  @override
  Future<Library> load() async {
    if (!account.connected) throw NoticeException(tr('Spotify : non connecté'));
    final byId = <String, Track>{};
    final albumOf = <String, String>{}; // morceau → album
    final savedAlbums = <String, String>{}; // album → son uri

    void add(Track t, String? albumId) {
      if (t.id.isEmpty) return;
      final had = byId[t.id];
      // Ajouté deux fois (album enregistré et titre liké) : la date la plus
      // récente compte.
      if (had != null && (had.added?.isAfter(t.added ?? DateTime(0)) ?? false)) return;
      byId[t.id] = t;
      if (albumId != null) albumOf[t.id] = albumId;
    }

    final (albums, liked, lists) = await (
      _api.pages('/me/albums'),
      _api.pages('/me/tracks'),
      _api.pages('/me/playlists'),
    ).wait;

    for (final item in albums) {
      final album = item['album'] as Map<String, Object?>?;
      if (album == null) continue;
      final added = DateTime.tryParse(item['added_at'] as String? ?? '');
      final id = album['id'] as String?;
      if (id != null && album['uri'] is String) savedAlbums[id] = album['uri'] as String;
      final page = album['tracks'] as Map<String, Object?>?;
      final tracks = [...((page?['items'] as List?) ?? const []).whereType<Map<String, Object?>>()];
      // Plus de 50 morceaux : la suite, page par page.
      if (page?['next'] case final String next) tracks.addAll(await _api.pages(next));
      for (final t in tracks) {
        add(spotifyTrack(t, album: album, added: added), id);
      }
    }
    for (final item in liked) {
      final t = item['track'] as Map<String, Object?>?;
      if (t == null) continue;
      add(spotifyTrack(t, added: DateTime.tryParse(item['added_at'] as String? ?? '')), _albumId(t, null));
    }

    final (:tracks, albums: grouped) = groupByAlbum(
      byId.values,
      albumKey: (t) => albumOf[t.id] ?? t.album.toLowerCase(),
      // Album enregistré : on le joue tel que Spotify le connaît. Album dont
      // on n'a que des titres likés : seulement ceux-là.
      albumUri: (key) => savedAlbums[key],
    );

    final playlists = [
      for (final p in lists)
        if (p['id'] is String)
          SongList.lazy(p['name'] as String? ?? '', () => _playlistTracks(p['id'] as String), uri: p['uri'] as String?),
    ];
    return Library(tracks, grouped, playlists);
  }

  /// Les morceaux d'une liste (seulement les siennes ou celles où l'on
  /// collabore : Spotify refuse les autres, qui se jouent alors entières).
  Future<List<Track>> _playlistTracks(String id) async {
    final items = await _api.pages('/playlists/$id/items');
    return [
      for (final item in items)
        if ((item['item'] ?? item['track']) case final Map<String, Object?> t)
          if (t['type'] == 'track' && item['is_local'] != true && t['is_local'] != true)
            spotifyTrack(t, added: DateTime.tryParse(item['added_at'] as String? ?? '')),
    ];
  }

  static final _covers = <String, Future<Uint8List?>>{};

  /// Pochette téléchargée une fois, gardée dans ~/.cache/lecteur/covers.
  @override
  Future<Uint8List?> artwork(Track track) {
    final url = track.artworkUrl;
    if (url == null) return Future.value();
    return _covers[url] ??= _download(url);
  }

  static Future<Uint8List?> _download(String url) async {
    final name = sha1.convert(utf8.encode(url)).toString();
    final file = File(joinPath(cacheDir(), joinPath('lecteur', joinPath('covers', '$name.jpg'))));
    try {
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {}
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(res.bodyBytes);
      } catch (_) {}
      return res.bodyBytes;
    } catch (_) {
      _covers.remove(url); // on réessaiera
      return null;
    }
  }

  @override
  PlaybackEngine createEngine() => SpotifyConnectEngine(account);
}
