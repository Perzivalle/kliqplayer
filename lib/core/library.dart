import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// Un morceau de la bibliothèque.
class Track {
  const Track({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    this.trackNumber,
    this.duration,
  });

  final String path;
  final String title;
  final String artist;
  final String album;
  final int? trackNumber;
  final Duration? duration;

  @override
  String toString() => '$artist — $title';
}

const _audioExtensions = {'.mp3', '.flac', '.ogg', '.opus', '.m4a', '.aac', '.wav'};

/// Dossier de musique par défaut : celui de MPD.
Directory defaultMusicDirectory() {
  final home = Platform.environment['HOME'] ?? '.';
  final override = Platform.environment['LECTEUR_MUSIC'];
  if (override != null && override.isNotEmpty) return Directory(override);
  return Directory('$home/Music/Musique Ipod');
}

/// Parcourt le dossier et lit les tags, dans un isolate séparé pour ne pas
/// bloquer l'interface.
Future<List<Track>> scanLibrary(Directory root) {
  final rootPath = root.path;
  return Isolate.run(() => _scan(rootPath));
}

List<Track> _scan(String rootPath) {
  final tracks = <Track>[];
  final root = Directory(rootPath);
  if (!root.existsSync()) return tracks;

  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final lower = entity.path.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot < 0 || !_audioExtensions.contains(lower.substring(dot))) continue;

    final fallbackTitle = _basename(entity.path);
    try {
      final meta = readMetadata(entity, getImage: false);
      tracks.add(Track(
        path: entity.path,
        title: _orElse(meta.title, fallbackTitle),
        artist: _orElse(meta.artist, 'Artiste inconnu'),
        album: _orElse(meta.album, _basename(entity.parent.path)),
        trackNumber: meta.trackNumber,
        duration: meta.duration,
      ));
    } catch (_) {
      tracks.add(Track(
        path: entity.path,
        title: fallbackTitle,
        artist: 'Artiste inconnu',
        album: _basename(entity.parent.path),
      ));
    }
  }

  // Ordre « bibliothèque » : artiste, album, numéro de piste.
  tracks.sort((a, b) {
    final byArtist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
    if (byArtist != 0) return byArtist;
    final byAlbum = a.album.toLowerCase().compareTo(b.album.toLowerCase());
    if (byAlbum != 0) return byAlbum;
    return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
  });
  return tracks;
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
