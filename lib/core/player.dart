import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'library.dart';

/// Moteur de lecture commun à toutes les skins.
///
/// Les skins lisent l'état (morceau, lecture, volume…) et appellent les
/// commandes. [smoothPosition] donne une position interpolée à chaque image,
/// pour des animations parfaitement continues.
class PlayerController extends ChangeNotifier {
  PlayerController() {
    _subs.addAll([
      _player.stream.playing.listen((playing) {
        _anchorPosition(_player.state.position);
        this.playing = playing;
        notifyListeners();
      }),
      _player.stream.position.listen(_anchorPosition),
      _player.stream.duration.listen((d) {
        duration = d;
        notifyListeners();
      }),
      _player.stream.volume.listen((v) {
        volume = v;
        notifyListeners();
      }),
      _player.stream.rate.listen((r) {
        rate = r;
        notifyListeners();
      }),
      _player.stream.playlist.listen((playlist) {
        if (playlist.index != index) {
          index = playlist.index;
          _onTrackChanged();
        }
      }),
    ]);
  }

  final Player _player = Player(configuration: const PlayerConfiguration(title: 'Lecteur'));
  final List<StreamSubscription<Object?>> _subs = [];

  List<Track> queue = const [];
  int index = -1;
  bool playing = false;
  Duration duration = Duration.zero;
  double volume = 100;
  double rate = 1;
  bool loading = true;

  /// Pochette du morceau en cours (null si absente).
  Uint8List? cover;

  Track? get current => (index >= 0 && index < queue.length) ? queue[index] : null;

  // Interpolation de la position entre deux mises à jour du moteur.
  Duration _anchor = Duration.zero;
  final Stopwatch _sinceAnchor = Stopwatch();

  void _anchorPosition(Duration position) {
    _anchor = position;
    _sinceAnchor
      ..reset()
      ..start();
  }

  Duration get smoothPosition {
    if (!playing) return _anchor;
    final elapsed = _sinceAnchor.elapsedMicroseconds * rate;
    final pos = _anchor + Duration(microseconds: elapsed.round());
    return duration > Duration.zero && pos > duration ? duration : pos;
  }

  /// Avancement dans le morceau, entre 0 et 1.
  double get progress {
    final total = duration.inMicroseconds;
    if (total <= 0) return 0;
    return (smoothPosition.inMicroseconds / total).clamp(0.0, 1.0);
  }

  Future<void> loadLibrary() async {
    loading = true;
    notifyListeners();
    final tracks = await scanLibrary(defaultMusicDirectory());
    queue = tracks;
    loading = false;
    if (tracks.isNotEmpty) {
      await _player.open(
        Playlist([for (final t in tracks) Media(t.path)], index: 0),
        play: false,
      );
    }
    notifyListeners();
  }

  int _coverRequest = 0;

  Future<void> _onTrackChanged() async {
    notifyListeners();
    final track = current;
    final request = ++_coverRequest;
    final bytes = track == null ? null : await loadCover(track);
    if (request != _coverRequest) return; // un autre morceau entre-temps
    cover = bytes;
    notifyListeners();
  }

  // --- Commandes -----------------------------------------------------------

  Future<void> playPause() => _player.playOrPause();
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> next() => _player.next();
  Future<void> previous() => _player.previous();
  Future<void> jumpTo(int i) => _player.jump(i);

  Future<void> seekProgress(double p) async {
    final target = duration * p.clamp(0.0, 1.0);
    _anchorPosition(target);
    await _player.seek(target);
  }

  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0, 100));
  Future<void> setRate(double r) => _player.setRate(r.clamp(0.25, 4));

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
