import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'library.dart';

/// Moteur de lecture.
///
/// L'interface lit l'état (morceau, lecture, volume…) et appellent les
/// commandes. [smoothPosition] donne une position interpolée à chaque image,
/// pour des animations parfaitement continues.
class PlayerController extends ChangeNotifier {
  PlayerController() : _engine = Player(configuration: const PlayerConfiguration(title: 'Lecteur')) {
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
      _player.stream.playlist.listen((playlist) {
        if (playlist.index != index) {
          index = playlist.index;
          _onTrackChanged();
        }
      }),
    ]);
  }

  /// Sans moteur audio : état figé fourni à la main, commandes sans effet.
  /// Sert aux tests (captures de référence du baladeur).
  @visibleForTesting
  PlayerController.preview({
    this.queue = const [],
    this.albums = const [],
    this.index = -1,
    this.playing = false,
    this.duration = Duration.zero,
    this.volume = 100,
    Duration position = Duration.zero,
  }) : _engine = null {
    loading = false;
    _anchor = position;
  }

  final Player? _engine;

  /// Le moteur ; n'est jamais appelé en mode aperçu (voir [_run]).
  Player get _player => _engine!;

  /// Lance une commande du moteur, ou rien en mode aperçu.
  Future<void> _run(Future<void> Function(Player p) command) async {
    final e = _engine;
    if (e != null) await command(e);
  }
  final List<StreamSubscription<Object?>> _subs = [];

  List<Track> queue = const [];
  List<Album> albums = const [];

  int index = -1;
  bool playing = false;
  Duration duration = Duration.zero;
  double volume = 100;
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
    final pos = _anchor + _sinceAnchor.elapsed;
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
    final library = await scanLibrary(defaultMusicDirectory());
    final tracks = library.tracks;
    queue = tracks;
    albums = library.albums;
    loading = false;
    if (tracks.isNotEmpty) {
      await _player.open(
        Playlist([for (final t in tracks) Media(t.path)], index: 0),
        play: false,
      );
    }
    notifyListeners();
  }


  /// Album du morceau en cours (index dans [albums]), ou -1.
  int get currentAlbum => albums.lastIndexWhere((a) => a.firstIndex <= index);

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

  Future<void> playPause() => _run((p) => p.playOrPause());
  Future<void> play() => _run((p) => p.play());
  Future<void> pause() => _run((p) => p.pause());
  Future<void> next() => _run((p) => p.next());
  Future<void> previous() => _run((p) => p.previous());
  Future<void> jumpTo(int i) => _run((p) => p.jump(i));


  Future<void> seekProgress(double p) async {
    final target = duration * p.clamp(0.0, 1.0);
    _anchorPosition(target);
    await _run((p) => p.seek(target));
  }

  Future<void> setVolume(double v) => _run((p) => p.setVolume(v.clamp(0, 100)));

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _engine?.dispose();
    super.dispose();
  }
}
