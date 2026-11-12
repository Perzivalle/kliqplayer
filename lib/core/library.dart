import 'dart:async';

/// Ce que les menus parcourent, d'où que vienne la musique (dossier,
/// Spotify…) : des morceaux, rangés album par album, et des listes.

/// Un morceau.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.trackNumber,
    this.discNumber,
    this.duration,
    this.added,
    this.artworkUrl,
    this.genre,
  });

  /// Identifiant pour la source : chemin du fichier, ou « spotify:track:… ».
  /// Sert aussi de clé aux écoutes (« Les plus écoutés »).
  final String id;
  final String title;
  final String artist;
  final String album;
  final int? trackNumber;
  final int? discNumber;
  final Duration? duration;

  /// Date d'arrivée dans la bibliothèque (liste « Ajouts récents »).
  final DateTime? added;

  /// Pochette en ligne (les fichiers, eux, ont la leur dedans ou à côté).
  final String? artworkUrl;

  /// Genre, quand le fichier en donne un (menu Musique › Genres).
  final String? genre;

  @override
  String toString() => '$artist — $title';
}

/// Un album : une suite de morceaux consécutifs de [Library.tracks].
class Album {
  const Album({
    required this.title,
    required this.artist,
    required this.firstIndex,
    required this.trackCount,
    this.uri,
  });

  final String title;
  final String artist;

  /// Position du premier morceau dans [Library.tracks].
  final int firstIndex;
  final int trackCount;

  /// L'album entier pour la source, s'il en a un (« spotify:album:… ») : le
  /// lancer joue l'album tel que la source le connaît.
  final String? uri;
}

/// Liste de lecture. Ses morceaux sont là tout de suite (fichier .m3u), ou
/// chargés à la première ouverture (Spotify).
class SongList {
  SongList(this.name, List<Track> tracks, {this.uri, this.artworkUrl})
      : _tracks = tracks,
        _loader = null;

  SongList.lazy(this.name, Future<List<Track>> Function() loader, {this.uri, this.artworkUrl}) : _loader = loader;

  final String name;

  /// La liste entière pour la source (« spotify:playlist:… »).
  final String? uri;

  /// Son image chez la source (Spotify), pour Cover Flow.
  final String? artworkUrl;

  final Future<List<Track>> Function()? _loader;
  List<Track>? _tracks;
  Future<List<Track>>? _loading;

  /// Ses morceaux, s'ils sont déjà là.
  List<Track>? get tracks => _tracks;

  /// Le chargement a échoué (liste qu'on ne peut pas parcourir, réseau…).
  Object? error;

  /// Charge les morceaux (une seule fois) ; [onDone] est appelé à
  /// l'arrivée, ou en cas d'échec.
  Future<List<Track>> load({void Function()? onDone}) {
    if (_tracks case final t?) return Future.value(t);
    return _loading ??= _loader!().then((t) {
      _tracks = t;
      return t;
    }, onError: (Object e) {
      error = e;
      _loading = null;
      throw e;
    }).whenComplete(() => onDone?.call());
  }
}

/// Toute la musique d'une source.
class Library {
  const Library(this.tracks, this.albums, [this.playlists = const []]);

  final List<Track> tracks;
  final List<Album> albums;
  final List<SongList> playlists;

  static const empty = Library([], []);
}

int _cmp(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Range des morceaux album par album, dans l'ordre « bibliothèque » :
/// artiste de l'album, titre de l'album, disque, numéro de piste. [albumKey]
/// regroupe (le tag, ou l'identifiant de l'album chez la source) ;
/// [albumUri] donne l'album entier pour la source, s'il en a un.
({List<Track> tracks, List<Album> albums}) groupByAlbum(
  Iterable<Track> all, {
  String Function(Track t)? albumKey,
  String? Function(String key)? albumUri,
}) {
  final key = albumKey ?? (t) => t.album.toLowerCase();
  final groups = <String, List<Track>>{};
  for (final t in all) {
    groups.putIfAbsent(key(t), () => []).add(t);
  }
  final sorted = [
    for (final MapEntry(key: k, value: group) in groups.entries)
      (
        key: k,
        artist: _mostCommon(group.map((t) => t.artist)),
        tracks: group
          ..sort((a, b) {
            final byDisc = (a.discNumber ?? 0).compareTo(b.discNumber ?? 0);
            if (byDisc != 0) return byDisc;
            final byNumber = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
            return byNumber != 0 ? byNumber : a.id.compareTo(b.id);
          }),
      ),
  ]..sort((a, b) {
      final byArtist = _cmp(a.artist, b.artist);
      return byArtist != 0 ? byArtist : _cmp(a.tracks.first.album, b.tracks.first.album);
    });

  final ordered = <Track>[];
  final albums = <Album>[];
  for (final g in sorted) {
    albums.add(Album(
      title: g.tracks.first.album,
      artist: g.artist,
      firstIndex: ordered.length,
      trackCount: g.tracks.length,
      uri: albumUri?.call(g.key),
    ));
    ordered.addAll(g.tracks);
  }
  return (tracks: ordered, albums: albums);
}

String _mostCommon(Iterable<String> values) {
  final counts = <String, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
