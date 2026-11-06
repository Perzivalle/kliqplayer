import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import 'settings.dart';

/// Un morceau de la bibliothèque.
class Track {
  const Track({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    this.trackNumber,
    this.duration,
    this.added,
  });

  final String path;
  final String title;
  final String artist;
  final String album;
  final int? trackNumber;
  final Duration? duration;

  /// Date d'arrivée du fichier dans la bibliothèque (liste « Ajouts récents »).
  final DateTime? added;

  @override
  String toString() => '$artist — $title';
}

/// Un album : une suite de morceaux consécutifs de la file de lecture.
class Album {
  const Album({required this.title, required this.artist, required this.firstIndex, required this.trackCount});

  final String title;
  final String artist;

  /// Position du premier morceau dans [Library.tracks].
  final int firstIndex;
  final int trackCount;
}

/// Liste de lecture : un nom et des morceaux (index dans la file).
class SongList {
  const SongList(this.name, this.tracks);

  final String name;
  final List<int> tracks;
}

/// Résultat du parcours : les morceaux, rangés album par album, et les
/// listes .m3u trouvées dans le dossier.
class Library {
  const Library(this.tracks, this.albums, [this.playlists = const []]);

  final List<Track> tracks;
  final List<Album> albums;
  final List<SongList> playlists;
}

const _audioExtensions = {'.mp3', '.flac', '.ogg', '.opus', '.m4a', '.aac', '.wav'};

/// Dossier de musique : $LECTEUR_MUSIC s'il est donné, sinon celui choisi
/// dans Réglages › Bibliothèque, sinon celui de MPD.
Directory defaultMusicDirectory() {
  final home = Platform.environment['HOME'] ?? '.';
  final override = Platform.environment['LECTEUR_MUSIC'];
  if (override != null && override.isNotEmpty) return Directory(override);
  final chosen = Settings.getString('library.folder');
  if (chosen != null && chosen.isNotEmpty) return Directory(chosen);
  return Directory('$home/Music/Musique Ipod');
}

/// Parcourt le dossier et lit les tags, dans un isolate séparé pour ne pas
/// bloquer l'interface.
Future<Library> scanLibrary(Directory root) {
  final rootPath = root.path;
  return Isolate.run(() => _scan(rootPath));
}

Library _scan(String rootPath) {
  final tracks = <Track>[];
  final m3u = <File>[];
  final root = Directory(rootPath);
  if (!root.existsSync()) return const Library([], []);

  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final lower = entity.path.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot < 0) continue;
    final ext = lower.substring(dot);
    if (ext == '.m3u' || ext == '.m3u8') m3u.add(entity);
    if (!_audioExtensions.contains(ext)) continue;

    final fallbackTitle = _basename(entity.path);
    DateTime? added;
    try {
      added = entity.statSync().modified;
    } catch (_) {}
    try {
      final meta = readMetadata(entity, getImage: false);
      tracks.add(Track(
        path: entity.path,
        title: _orElse(meta.title, fallbackTitle),
        artist: _orElse(meta.artist, 'Artiste inconnu'),
        album: _orElse(meta.album, _basename(entity.parent.path)),
        trackNumber: meta.trackNumber,
        duration: meta.duration,
        added: added,
      ));
    } catch (_) {
      tracks.add(Track(
        path: entity.path,
        title: fallbackTitle,
        artist: 'Artiste inconnu',
        album: _basename(entity.parent.path),
        added: added,
      ));
    }
  }

  // Regroupement par album (tag), puis ordre « bibliothèque » :
  // artiste de l'album, titre de l'album, numéro de piste.
  final groups = <String, List<Track>>{};
  for (final t in tracks) {
    groups.putIfAbsent(t.album.toLowerCase(), () => []).add(t);
  }
  final sorted = [
    for (final group in groups.values)
      (
        artist: _mostCommon(group.map((t) => t.artist)),
        tracks: group
          ..sort((a, b) {
            final byNumber = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
            return byNumber != 0 ? byNumber : a.path.compareTo(b.path);
          }),
      ),
  ]..sort((a, b) {
      final byArtist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      if (byArtist != 0) return byArtist;
      return a.tracks.first.album.toLowerCase().compareTo(b.tracks.first.album.toLowerCase());
    });

  final ordered = <Track>[];
  final albums = <Album>[];
  for (final g in sorted) {
    albums.add(Album(
      title: g.tracks.first.album,
      artist: g.artist,
      firstIndex: ordered.length,
      trackCount: g.tracks.length,
    ));
    ordered.addAll(g.tracks);
  }
  return Library(ordered, albums, _readPlaylists(m3u, ordered));
}

/// Listes .m3u : une ligne par fichier, chemin absolu ou relatif à la liste.
List<SongList> _readPlaylists(List<File> files, List<Track> tracks) {
  final byPath = {for (var i = 0; i < tracks.length; i++) tracks[i].path: i};
  final lists = <SongList>[];
  for (final f in files) {
    try {
      final ids = <int>[];
      for (var line in f.readAsLinesSync()) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final path = line.startsWith('/') ? line : '${f.parent.path}/$line';
        final i = byPath[File(path).absolute.path] ?? byPath[path];
        if (i != null) ids.add(i);
      }
      if (ids.isNotEmpty) {
        lists.add(SongList(_basename(f.path), ids));
      }
    } catch (_) {}
  }
  lists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return lists;
}

String _mostCommon(Iterable<String> values) {
  final counts = <String, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// Pochette du morceau : image intégrée au fichier, sinon cover.jpg /
/// folder.jpg dans le dossier.
Future<Uint8List?> loadCover(Track track) {
  final path = track.path;
  return Isolate.run(() {
    try {
      final meta = readMetadata(File(path), getImage: true);
      if (meta.pictures.isNotEmpty) return meta.pictures.first.bytes;
    } catch (_) {}
    final dir = File(path).parent;
    for (final name in const ['cover', 'folder', 'front', 'album', 'Cover', 'Folder', 'Front']) {
      for (final ext in const ['jpg', 'jpeg', 'png']) {
        final f = File('${dir.path}/$name.$ext');
        if (f.existsSync()) return f.readAsBytesSync();
      }
    }
    return null;
  });
}

String _orElse(String? value, String fallback) =>
    (value == null || value.trim().isEmpty) ? fallback : value.trim();

String _basename(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
