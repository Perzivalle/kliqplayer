import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../../core/library.dart';
import '../../core/paths.dart';
import '../../core/strings.dart';

const _audioExtensions = {'.mp3', '.flac', '.ogg', '.opus', '.m4a', '.aac', '.wav'};

/// Parcourt le dossier et lit les tags, dans un isolate séparé pour ne pas
/// bloquer l'interface.
Future<Library> scanLibrary(Directory root) {
  final rootPath = root.path;
  // (Traduit ici : l'isolate ne connaît pas la langue choisie.)
  final unknown = tr('Artiste inconnu');
  return Isolate.run(() => _scan(rootPath, unknown));
}

Library _scan(String rootPath, String unknownArtist) {
  final tracks = <Track>[];
  // Album de chaque morceau : son titre, et l'artiste de l'album quand le
  // tag le donne (deux « Greatest Hits » ne font pas un seul album).
  final albumOf = <String, String>{};
  final m3u = <File>[];
  final root = Directory(rootPath);
  if (!root.existsSync()) return const Library([], []);

  // (Liens suivis : une bibliothèque rangée ailleurs et liée ici compte.)
  for (final entity in root.listSync(recursive: true)) {
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
      final album = _orElse(meta.album, _basename(entity.parent.path));
      tracks.add(Track(
        id: entity.path,
        title: _orElse(meta.title, fallbackTitle),
        artist: _orElse(meta.artist, unknownArtist),
        album: album,
        trackNumber: meta.trackNumber,
        discNumber: meta.discNumber,
        duration: meta.duration,
        added: added,
      ));
      final albumArtist = meta.albumArtist?.trim() ?? '';
      if (albumArtist.isNotEmpty) albumOf[entity.path] = '${album.toLowerCase()}\u0000${albumArtist.toLowerCase()}';
    } catch (_) {
      tracks.add(Track(
        id: entity.path,
        title: fallbackTitle,
        artist: unknownArtist,
        album: _basename(entity.parent.path),
        added: added,
      ));
    }
  }

  // Regroupement par album (tag), dans l'ordre « bibliothèque ».
  final (tracks: ordered, :albums) = groupByAlbum(tracks, albumKey: (t) => albumOf[t.id] ?? t.album.toLowerCase());
  return Library(ordered, albums, _readPlaylists(m3u, ordered));
}

/// Listes .m3u : une ligne par fichier, chemin absolu ou relatif à la liste.
List<SongList> _readPlaylists(List<File> files, List<Track> tracks) {
  final byPath = {for (final t in tracks) normalizePath(t.id): t};
  final lists = <SongList>[];
  for (final f in files) {
    try {
      final list = <Track>[];
      for (var line in f.readAsLinesSync()) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final path = normalizePath(isAbsolutePath(line) ? line : joinPath(f.parent.path, line));
        final t = byPath[normalizePath(File(path).absolute.path)] ?? byPath[path];
        if (t != null) list.add(t);
      }
      if (list.isNotEmpty) {
        lists.add(SongList(_basename(f.path), list));
      }
    } catch (_) {}
  }
  lists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return lists;
}

/// Pochette du morceau : image intégrée au fichier, sinon cover.jpg /
/// folder.jpg dans le dossier.
Future<Uint8List?> loadCover(Track track) {
  final path = track.id;
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
  final name = lastSegment(path);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
