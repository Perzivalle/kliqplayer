import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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
import 'key_guide.dart';
import 'librespot.dart';
import 'official_app.dart';

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
      : _client = client // ignore: prefer_initializing_formals
  {
    _useKey(clientId ?? Settings.getString(_keySetting));
    _userName = Settings.getString('spotify.user');
  }

  static const _keySetting = 'spotify.clientId';

  final http.Client? _client;

  /// La clé d'appli Spotify de l'utilisateur (« Client ID »), s'il l'a
  /// donnée. Spotify limite chaque appli non validée à cinq comptes : une
  /// clé commune ne servirait qu'à cinq personnes, chacun crée donc la
  /// sienne (Réglages › Bibliothèque › Spotify).
  String? _key;

  late SpotifyAuth auth;
  late SpotifyApi api;

  void _useKey(String? key) {
    _key = key == null || key.isEmpty ? null : key;
    auth = SpotifyAuth(clientId: _key ?? '', client: _client);
    api = SpotifyApi(auth, client: _client);
  }

  @override
  bool get needsKey => _key == null;

  @override
  String? get keyHint {
    final k = _key;
    return k == null ? null : (k.length > 8 ? '${k.substring(0, 4)}…${k.substring(k.length - 4)}' : k);
  }

  /// Une clé d'appli Spotify dans [text] (32 chiffres hexadécimaux), ou
  /// null.
  static String? keyIn(String text) => RegExp(r'(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])').firstMatch(text)?.group(0)?.toLowerCase();

  @override
  Future<void> openKeyGuide() async {
    // L'adresse de retour, prête à être collée dans le formulaire de Spotify.
    await Clipboard.setData(const ClipboardData(text: SpotifyAuth.redirectUri));
    final file = File(joinPath(cacheDir(), joinPath('lecteur', 'spotify-guide.html')));
    await file.parent.create(recursive: true);
    await file.writeAsString(spotifyKeyGuide());
    if (!await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication)) {
      throw NoticeException(tr('Navigateur introuvable'));
    }
  }

  @override
  Future<void> pasteKey() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final key = keyIn(text);
    if (key == null) throw NoticeException(tr('Pas de clé copiée'));
    Settings.setString(_keySetting, key);
    _useKey(key);
    notifyListeners();
  }

  @override
  Future<void> forgetKey() async {
    await disconnect();
    Settings.setString(_keySetting, '');
    _useKey(null);
    notifyListeners();
  }

  /// Le lecteur intégré (librespot), s'il est installé.
  final Librespot? installedLibrespot;

  /// L'appli Spotify officielle, lancée au besoin, si elle est installée.
  final SpotifyApp? app;

  /// Le lecteur intégré, s'il est installé et choisi. Désactivé par
  /// défaut : Spotify refuse les clés de déchiffrement à librespot pour
  /// certains comptes (https://github.com/librespot-org/librespot/issues/1649),
  /// qui jouent alors en silence.
  Librespot? get librespot => builtInEnabled ? installedLibrespot : null;

  /// (Réglable dans settings.json : « spotify.builtin » : « on » ou « off ».
  /// Sans réglage, il sert quand l'appli Spotify n'est pas installée : sur
  /// une machine qui n'a que lui, c'est la seule façon d'avoir du son.)
  bool get builtInEnabled {
    if (installedLibrespot == null) return false;
    final choice = Settings.getString('spotify.builtin');
    return choice == 'on' || (choice != 'off' && app == null);
  }

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
    if (needsKey) throw NoticeException(tr('Clé Spotify requise'));
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
    rest();
    try {
      await SpotifySource.cacheFile?.delete();
    } catch (_) {}
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

  /// L'appareil de ce PC, qui joue toujours le son de KliqPlayer (même si le
  /// compte jouait ailleurs, sur le téléphone : la lecture revient ici).
  /// L'appli Spotify est lancée, cachée, s'il le faut.
  ///
  /// Retenu une minute : chaque lecture n'a pas à redemander la liste des
  /// appareils. [fresh] : il a disparu (commande refusée), on le recherche.
  Future<String> thisPcDevice({bool fresh = false}) {
    if (fresh) _device = null;
    if (deviceReady) return Future.value(_device!);
    // Une seule recherche à la fois : deux appuis pendant que l'appli
    // Spotify se lance attendent la même.
    return _finding ??= _findThisPc().then((id) {
      _device = id;
      _deviceAt = DateTime.now();
      return id;
    }).whenComplete(() => _finding = null);
  }

  String? _device;
  DateTime _deviceAt = DateTime(0);
  Future<String>? _finding;

  /// L'appareil de ce PC est connu : une lecture partira tout de suite.
  bool get deviceReady => _device != null && DateTime.now().difference(_deviceAt) < const Duration(minutes: 1);

  Future<String> _findThisPc() async {
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
    // Deux échecs qu'on distingue au message : l'appli n'est pas installée
    // (ou pas trouvée), ou elle a été lancée sans apparaître sur le compte.
    throw NoticeException(tr(app == null ? 'Appli Spotify introuvable' : 'Ouvrez Spotify sur un appareil'));
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
        // (Toutes les deux secondes : Spotify limite le nombre de demandes.)
        await Future<void>.delayed(const Duration(seconds: 2));
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

  /// On n'écoute plus Spotify (retour au dossier, déconnexion) : ce qu'on
  /// avait lancé pour lui s'arrête, au lieu de rester en mémoire.
  void rest() {
    _device = null;
    installedLibrespot?.stop();
    app?.stop();
  }

  @override
  void shutdown() => rest();
}

/// La bibliothèque telle qu'on la garde d'un lancement à l'autre.
class _Snapshot {
  _Snapshot(this.tracks, this.albums, this.lists);

  final List<Track> tracks;
  final List<Album> albums;

  /// Les listes de lecture (leurs morceaux sont chargés à l'ouverture).
  final List<({String id, String name, String? uri})> lists;

  Map<String, Object?> toJson(String? user) => {
        'user': user,
        'tracks': [
          for (final t in tracks)
            {
              'id': t.id,
              'title': t.title,
              'artist': t.artist,
              'album': t.album,
              'n': t.trackNumber,
              'disc': t.discNumber,
              'ms': t.duration?.inMilliseconds,
              'added': t.added?.toIso8601String(),
              'art': t.artworkUrl,
            },
        ],
        'albums': [
          for (final a in albums)
            {'title': a.title, 'artist': a.artist, 'first': a.firstIndex, 'count': a.trackCount, 'uri': a.uri},
        ],
        'lists': [
          for (final l in lists) {'id': l.id, 'name': l.name, 'uri': l.uri},
        ],
      };

  /// Null si [json] n'est pas la bibliothèque de [user] (autre compte,
  /// ancien format).
  static _Snapshot? fromJson(Object? json, String? user) {
    try {
      final map = json as Map<String, Object?>;
      if (map['user'] != user) return null;
      final tracks = [
        for (final t in (map['tracks'] as List).cast<Map<String, Object?>>())
          Track(
            id: t['id'] as String,
            title: t['title'] as String,
            artist: t['artist'] as String,
            album: t['album'] as String,
            trackNumber: t['n'] as int?,
            discNumber: t['disc'] as int?,
            duration: switch (t['ms']) { final int ms => Duration(milliseconds: ms), _ => null },
            added: DateTime.tryParse(t['added'] as String? ?? ''),
            artworkUrl: t['art'] as String?,
          ),
      ];
      final albums = [
        for (final a in (map['albums'] as List).cast<Map<String, Object?>>())
          Album(
            title: a['title'] as String,
            artist: a['artist'] as String,
            firstIndex: a['first'] as int,
            trackCount: a['count'] as int,
            uri: a['uri'] as String?,
          ),
      ];
      // (Un fichier abîmé ne doit pas faire planter les menus.)
      if (albums.any((a) => a.firstIndex < 0 || a.firstIndex + a.trackCount > tracks.length)) return null;
      final lists = [
        for (final l in (map['lists'] as List).cast<Map<String, Object?>>())
          (id: l['id'] as String, name: l['name'] as String, uri: l['uri'] as String?),
      ];
      return _Snapshot(tracks, albums, lists);
    } catch (_) {
      return null;
    }
  }
}

/// La musique du compte Spotify : albums enregistrés, titres likés (rangés
/// par album), listes de lecture.
class SpotifySource extends MusicSource {
  /// [cache] : où garder la bibliothèque d'un lancement à l'autre (par
  /// défaut dans ~/.cache/lecteur ; nulle part sous `flutter test`).
  SpotifySource(this.account, {File? cache, this.refreshAfter = const Duration(hours: 1)}) : _cache = cache ?? cacheFile;

  /// Âge à partir duquel la bibliothèque gardée est redemandée à Spotify au
  /// lancement. Elle représente des dizaines de demandes : la reprendre à
  /// chaque lancement suffit, à force, à dépasser la limite de Spotify.
  /// (« Actualiser » la redemande quand on veut.)
  final Duration refreshAfter;

  final SpotifyAccount account;
  SpotifyApi get _api => account.api;

  static File? get cacheFile =>
      JsonStore.inTest ? null : File(joinPath(cacheDir(), joinPath('lecteur', 'spotify-library.json')));

  final File? _cache;
  bool _served = false;
  bool _disposed = false;

  /// Rafraîchie en arrière-plan, pas encore servie.
  _Snapshot? _fresh;

  @override
  String get id => 'spotify';
  @override
  String get label => 'Spotify';

  /// Au lancement, la bibliothèque gardée la dernière fois est servie tout
  /// de suite, et la vraie demandée derrière : si elle a changé, la source
  /// prévient ([onChanged]) et la sert au chargement suivant. Ensuite
  /// (« Actualiser », nouvel essai), elle est demandée à Spotify.
  @override
  Future<Library> load() async {
    if (!account.connected) throw NoticeException(tr('Spotify : non connecté'));
    if (_fresh case final fresh?) {
      _fresh = null;
      return _library(fresh);
    }
    if (!_served) {
      _served = true;
      final text = await _readCache();
      final kept = text == null ? null : _decode(text);
      if (kept != null) {
        if (await _stale()) _refresh(text!);
        return _library(kept);
      }
    }
    final snapshot = await _fetch();
    _writeCache(_encode(snapshot));
    return _library(snapshot);
  }

  String _encode(_Snapshot s) => jsonEncode(s.toJson(account.userName));

  _Snapshot? _decode(String text) {
    try {
      return _Snapshot.fromJson(jsonDecode(text), account.userName);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readCache() async {
    try {
      return await _cache?.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// La bibliothèque gardée est assez vieille pour être redemandée.
  Future<bool> _stale() async {
    try {
      final file = _cache;
      if (file == null) return true;
      return DateTime.now().difference(await file.lastModified()) >= refreshAfter;
    } catch (_) {
      return true;
    }
  }

  Future<void> _writeCache(String text) async {
    final file = _cache;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text);
      await tmp.rename(file.path);
    } catch (_) {}
  }

  /// Demande la vraie bibliothèque pendant qu'on montre celle gardée
  /// ([kept], son texte) ; prévient si elle a changé.
  Future<void> _refresh(String kept) async {
    try {
      final snapshot = await _fetch();
      final text = _encode(snapshot);
      if (_disposed) return;
      if (text == kept) {
        // Rien de neuf : elle est à jour, on ne la redemandera pas de sitôt.
        try {
          await _cache?.setLastModified(DateTime.now());
        } catch (_) {}
        return;
      }
      await _writeCache(text);
      _fresh = snapshot;
      onChanged?.call();
    } catch (_) {
      // Hors ligne : on reste sur celle d'avant.
    }
  }

  Library _library(_Snapshot s) => Library(s.tracks, s.albums, [
        for (final l in s.lists) SongList.lazy(l.name, () => _playlistTracks(l.id), uri: l.uri),
      ]);

  @override
  void dispose() {
    _disposed = true;
    account.rest();
  }

  Future<_Snapshot> _fetch() async {
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

    // (Future.wait : au premier échec, son erreur telle quelle, à montrer.)
    final [albums, liked, lists] = await Future.wait([
      _api.pages('/me/albums'),
      _api.pages('/me/tracks'),
      _api.pages('/me/playlists'),
    ], eagerError: true);

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

    return _Snapshot(tracks, grouped, [
      for (final p in lists)
        if (p['id'] case final String id) (id: id, name: p['name'] as String? ?? '', uri: p['uri'] as String?),
    ]);
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
