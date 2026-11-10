import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart' hide Track;

import '../../core/engine.dart';
import '../../core/library.dart';
import '../../core/source.dart';
import 'scan.dart';

export '../../core/paths.dart' show defaultMusicDirectory;

/// La musique d'un dossier : fichiers audio, tags, listes .m3u.
class LocalSource extends MusicSource {
  LocalSource(this.dir);

  final String dir;

  @override
  String get id => 'local';

  @override
  String get label => dir;

  @override
  Future<Library> load() => scanLibrary(Directory(dir));

  @override
  Future<Uint8List?> artwork(Track track) => loadCover(track);

  @override
  PlaybackEngine createEngine() => MediaKitEngine();
}

/// Lecture des fichiers par media_kit (mpv), sur tous les systèmes.
class MediaKitEngine extends PlaybackEngine {
  MediaKitEngine() {
    _subs.addAll([
      _player.stream.playing.listen((playing) => _emit(EngineUpdate(playing: playing, position: _player.state.position))),
      _player.stream.position.listen((p) => _emit(EngineUpdate(position: p))),
      _player.stream.duration.listen((d) => _emit(EngineUpdate(duration: d))),
      _player.stream.volume.listen((v) => _emit(EngineUpdate(volume: v))),
      _player.stream.playlist.listen((playlist) {
        if (playlist.index != _index) {
          _index = playlist.index;
          _emit(EngineUpdate(index: _index));
        }
      }),
    ]);
  }

  final _player = Player(configuration: const PlayerConfiguration(title: 'Lecteur'));
  final List<StreamSubscription<Object?>> _subs = [];
  int _index = -1;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;

  void _emit(EngineUpdate u) => onUpdate?.call(u);

  static PlaylistMode _modeFor(RepeatMode r) => switch (r) {
        RepeatMode.off => PlaylistMode.none,
        RepeatMode.one => PlaylistMode.single,
        RepeatMode.all => PlaylistMode.loop,
      };

  @override
  Future<void> open(List<Track> queue, int start, {String? uri}) async {
    // Le morceau choisi part en premier, même en aléatoire.
    await _player.open(Playlist([for (final t in queue) Media(t.id)], index: start), play: false);
    await _player.setPlaylistMode(_modeFor(_repeat));
    if (_shuffle) await _player.setShuffle(true);
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> next() => _player.next();
  @override
  Future<void> previous() => _player.previous();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setShuffle(bool on) {
    _shuffle = on;
    return _player.setShuffle(on);
  }

  @override
  Future<void> setRepeat(RepeatMode mode) {
    _repeat = mode;
    return _player.setPlaylistMode(_modeFor(mode));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
  }
}
