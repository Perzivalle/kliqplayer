import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'library.dart';
import 'settings.dart';

/// Répétition : rien, le morceau en cours, ou toute la file.
enum RepeatMode { off, one, all }

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
    shuffle = Settings.getString('player.shuffle') == 'on';
    repeat = RepeatMode.values.asNameMap()[Settings.getString('player.repeat')] ?? RepeatMode.off;
    _plays = _loadPlays();
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
    this.playlists = const [],
    Duration position = Duration.zero,
    Map<int, Uint8List?> albumCovers = const {},
  }) : _engine = null {
    loading = false;
    _anchor = position;
    _albumCovers.addAll(albumCovers);
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

  /// Listes .m3u trouvées dans le dossier de musique.
  List<SongList> playlists = const [];

  /// Lecture aléatoire et répétition (Réglages), retenues d'un lancement à
  /// l'autre.
  bool shuffle = false;
  RepeatMode repeat = RepeatMode.off;

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

  /// Dossier d'où vient la musique.
  String musicDir = defaultMusicDirectory().path;

  /// Réglages › Bibliothèque : lit la musique d'un autre dossier (retenu
  /// d'un lancement à l'autre).
  Future<void> setMusicDir(String path) async {
    musicDir = path;
    Settings.setString('library.folder', path);
    if (_engine == null) {
      notifyListeners();
      return;
    }
    await loadLibrary();
  }

  Future<void> loadLibrary() async {
    loading = true;
    notifyListeners();
    final library = await scanLibrary(Directory(musicDir));
    final tracks = library.tracks;
    queue = tracks;
    albums = library.albums;
    playlists = library.playlists;
    // Les pochettes d'avant ne correspondent plus aux albums.
    _albumCovers.clear();
    _coverLoads.clear();
    _coverGeneration++;
    loading = false;
    if (tracks.isEmpty) {
      await _player.stop();
      index = -1;
      cover = null;
    } else {
      await _player.open(
        Playlist([for (final t in tracks) Media(t.path)], index: 0),
        play: false,
      );
      await _player.setPlaylistMode(_modeFor(repeat));
      if (shuffle) await _player.setShuffle(true);
    }
    notifyListeners();
  }

  static PlaylistMode _modeFor(RepeatMode r) => switch (r) {
        RepeatMode.off => PlaylistMode.none,
        RepeatMode.one => PlaylistMode.single,
        RepeatMode.all => PlaylistMode.loop,
      };

  Future<void> setShuffle(bool on) async {
    shuffle = on;
    Settings.setString('player.shuffle', on ? 'on' : 'off');
    notifyListeners();
    await _run((p) => p.setShuffle(on));
  }

  Future<void> setRepeat(RepeatMode r) async {
    repeat = r;
    Settings.setString('player.repeat', r.name);
    notifyListeners();
    await _run((p) => p.setPlaylistMode(_modeFor(r)));
  }

  // --- Pochettes des albums (Cover Flow) -------------------------------------

  final Map<int, Uint8List?> _albumCovers = {};
  final Set<int> _coverLoads = {};
  int _coverGeneration = 0;

  /// Pochette de l'album [i] si elle est déjà lue ; sinon null, et elle est
  /// lue en arrière-plan (l'écran est prévenu quand elle arrive).
  Uint8List? albumCover(int i) {
    if (_albumCovers.containsKey(i)) return _albumCovers[i];
    if (_engine != null && i >= 0 && i < albums.length && _coverLoads.add(i)) {
      final generation = _coverGeneration;
      loadCover(queue[albums[i].firstIndex]).then((bytes) {
        if (generation != _coverGeneration) return; // autre bibliothèque entre-temps
        _albumCovers[i] = bytes;
        _coverLoads.remove(i);
        notifyListeners();
      });
    }
    return null;
  }

  // --- Nombre d'écoutes (liste « Les plus écoutés ») -------------------------

  Map<String, int> _plays = {};
  Timer? _savePlays;

  /// Index des morceaux les plus écoutés, du plus au moins écouté.
  List<int> mostPlayed(int count) {
    final ids = [
      for (var i = 0; i < queue.length; i++)
        if ((_plays[queue[i].path] ?? 0) > 0) i,
    ]..sort((a, b) => (_plays[queue[b].path] ?? 0).compareTo(_plays[queue[a].path] ?? 0));
    return ids.take(count).toList();
  }

  /// Index des derniers morceaux arrivés, du plus récent au plus ancien.
  List<int> recentlyAdded(int count) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final ids = List.generate(queue.length, (i) => i)
      ..sort((a, b) => (queue[b].added ?? epoch).compareTo(queue[a].added ?? epoch));
    return ids.take(count).toList();
  }

  static Map<String, int> _loadPlays() {
    final raw = Settings.getMap('plays');
    return {
      for (final e in raw.entries)
        if (e.value is int) e.key: e.value as int,
    };
  }

  void _countPlay(Track t) {
    _plays[t.path] = (_plays[t.path] ?? 0) + 1;
    _savePlays?.cancel();
    _savePlays = Timer(const Duration(seconds: 5), () => Settings.setMap('plays', _plays));
  }


  /// Album du morceau en cours (index dans [albums]), ou -1.
  int get currentAlbum => albums.lastIndexWhere((a) => a.firstIndex <= index);

  int _coverRequest = 0;

  Future<void> _onTrackChanged() async {
    notifyListeners();
    final track = current;
    if (track != null && playing) _countPlay(track);
    final request = ++_coverRequest;
    final bytes = track == null ? null : await loadCover(track);
    if (request != _coverRequest) return; // un autre morceau entre-temps
    cover = bytes;
    notifyListeners();
  }

  // --- Commandes -----------------------------------------------------------

  Future<void> playPause() => _engine == null ? _preview(!playing) : _run((p) => p.playOrPause());
  Future<void> play() async {
    if (_engine == null) return _preview(true);
    // Démarrer un morceau depuis l'arrêt compte aussi comme une écoute.
    final t = current;
    if (!playing && t != null && _player.state.position < const Duration(seconds: 1)) _countPlay(t);
    await _run((p) => p.play());
  }
  Future<void> pause() => _engine == null ? _preview(false) : _run((p) => p.pause());

  /// En mode aperçu, lecture et pause changent quand même l'état affiché.
  Future<void> _preview(bool play) async {
    playing = play;
    notifyListeners();
  }
  Future<void> next() => _run((p) => p.next());
  Future<void> previous() => _run((p) => p.previous());
  Future<void> jumpTo(int i) => _run((p) => p.jump(i));


  Future<void> seekProgress(double p) async {
    final target = duration * p.clamp(0.0, 1.0);
    _anchorPosition(target);
    await _run((p) => p.seek(target));
  }

  Future<void> setVolume(double v) => _run((p) => p.setVolume(v.clamp(0, 100)));

  /// Enregistre tout de suite les écoutes pas encore écrites (avant de
  /// quitter).
  void savePlays() {
    if (_savePlays?.isActive ?? false) {
      _savePlays!.cancel();
      Settings.setMap('plays', _plays);
    }
  }

  @override
  void dispose() {
    savePlays();
    for (final s in _subs) {
      s.cancel();
    }
    _engine?.dispose();
    super.dispose();
  }
}
