import 'dart:async';

import 'package:flutter/foundation.dart';

import 'engine.dart';
import 'library.dart';
import 'paths.dart';
import 'settings.dart';
import 'source.dart';

export 'engine.dart' show RepeatMode;

/// Ce que l'interface voit du lecteur, quelle que soit la source.
///
/// La source ([MusicSource]) donne la bibliothèque et les pochettes ; son
/// moteur ([PlaybackEngine]) joue. L'interface lit l'état (morceau, lecture,
/// volume…) et appelle les commandes. [smoothPosition] donne une position
/// interpolée à chaque image, pour des animations parfaitement continues,
/// même quand le moteur ne donne la position que de temps en temps
/// (Spotify).
class PlayerController extends ChangeNotifier {
  PlayerController(MusicSource source, {this.sourceFor, this.accounts = const []}) {
    shuffle = Settings.getString('player.shuffle') == 'on';
    repeat = RepeatMode.values.asNameMap()[Settings.getString('player.repeat')] ?? RepeatMode.off;
    _plays = _loadPlays();
    _attach(source);
  }

  /// Sans moteur audio : état figé fourni à la main, commandes sans effet
  /// sur le son. Sert aux tests (captures de référence du baladeur).
  @visibleForTesting
  PlayerController.preview({
    this.tracks = const [],
    this.albums = const [],
    int index = -1,
    this.playing = false,
    this.duration = Duration.zero,
    this.volume = 100,
    this.playlists = const [],
    Duration position = Duration.zero,
    Map<int, Uint8List?> albumCovers = const {},
    this.accounts = const [],
  }) : _preview = true,
       sourceFor = null {
    _source = EmptySource();
    _engine = SilentEngine()..onUpdate = _onEngine;
    loading = false;
    _indexTracks();
    if (index >= 0 && index < tracks.length) {
      // Comme si on avait lancé l'album du morceau.
      final album = albums.lastIndexWhere((a) => a.firstIndex <= index);
      if (album >= 0 && index < albums[album].firstIndex + albums[album].trackCount) {
        final a = albums[album];
        nowPlaying = tracks.sublist(a.firstIndex, a.firstIndex + a.trackCount);
        queueIndex = index - a.firstIndex;
      } else {
        nowPlaying = tracks;
        queueIndex = index;
      }
      current = tracks[index];
    }
    _anchor = position;
    _albumCovers.addAll(albumCovers);
  }

  bool _preview = false;

  /// Fabrique les sources par identifiant (« local », « spotify ») : c'est
  /// main.dart qui les connaît, pas le lecteur.
  final MusicSource Function(String id)? sourceFor;

  /// Les services en ligne auxquels on peut se connecter.
  final List<RemoteAccount> accounts;
  late MusicSource _source;
  late PlaybackEngine _engine;

  MusicSource get source => _source;

  void _attach(MusicSource source) {
    _source = source;
    _engine = source.createEngine()..onUpdate = _onEngine;
  }

  /// Change de source (dossier → Spotify…) : l'ancienne s'arrête, la
  /// nouvelle est chargée.
  Future<void> setSource(MusicSource source) async {
    // Ce qui joue s'arrête : un appareil Spotify continuerait sinon à côté
    // de la nouvelle source.
    if (playing) {
      try {
        await _engine.pause().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _engine
      ..onUpdate = null
      ..dispose();
    _source.dispose();
    _attach(source);
    nowPlaying = const [];
    queueIndex = -1;
    current = null;
    cover = null;
    playing = false;
    duration = Duration.zero;
    _anchorPosition(Duration.zero);
    await loadLibrary();
  }

  // --- Bibliothèque ------------------------------------------------------------

  /// Dossier de la musique sur le disque (source « local »).
  String musicDir = defaultMusicDirectory().path;

  /// Réglages › Bibliothèque : la musique de ce dossier (retenu d'un
  /// lancement à l'autre).
  Future<void> setMusicDir(String path) async {
    musicDir = path;
    Settings.setString('library.folder', path);
    await useSource('local');
  }

  /// Passe à la source [id] (« local », « spotify »), retenue d'un lancement
  /// à l'autre.
  Future<void> useSource(String id) async {
    Settings.setString('library.source', id);
    final make = sourceFor;
    if (_preview || make == null) {
      notifyListeners();
      return;
    }
    await setSource(make(id));
  }

  /// Tous les morceaux de la source, rangés album par album.
  List<Track> tracks = const [];
  List<Album> albums = const [];
  List<SongList> playlists = const [];
  bool loading = true;

  /// Le chargement de la bibliothèque a échoué (réseau, compte…).
  Object? loadError;

  /// Rang de chaque morceau dans [tracks], par identifiant.
  Map<String, int> _byId = const {};

  void _indexTracks() => _byId = {for (var i = 0; i < tracks.length; i++) tracks[i].id: i};

  Future<void> loadLibrary() async {
    loading = true;
    loadError = null;
    notifyListeners();
    final source = _source;
    Library library;
    try {
      library = await source.load();
    } catch (e) {
      if (!identical(source, _source)) return;
      library = Library.empty;
      loadError = e;
    }
    if (!identical(source, _source)) return; // une autre source entre-temps
    tracks = library.tracks;
    albums = library.albums;
    playlists = library.playlists;
    _indexTracks();
    // Les pochettes d'avant ne correspondent plus aux albums.
    _albumCovers.clear();
    _coverLoads.clear();
    _coverGeneration++;
    loading = false;
    notifyListeners();
  }

  /// Message à montrer (pas d'appareil Spotify, pas de connexion…), ou
  /// null.
  String? notice;

  void _fail(Object e) {
    notice = e is NoticeException ? e.message : '$e';
    notifyListeners();
  }

  /// Lance une commande du moteur ; une erreur devient un [notice].
  Future<void> _run(Future<void> Function(PlaybackEngine e) command) async {
    try {
      await command(_engine);
      if (notice != null) {
        notice = null;
        notifyListeners();
      }
    } catch (e) {
      _fail(e);
    }
  }

  // --- File en cours -------------------------------------------------------------

  /// Les morceaux lancés (un album, une liste, tous les morceaux…).
  List<Track> nowPlaying = const [];

  /// Rang du morceau en cours dans [nowPlaying] (-1 : hors de la file).
  int queueIndex = -1;

  Track? current;

  bool playing = false;
  Duration duration = Duration.zero;
  double volume = 100;

  /// Pochette du morceau en cours (null si absente).
  Uint8List? cover;

  /// Rang du morceau en cours dans [tracks] (-1 s'il n'y est pas).
  int get currentIndex => current == null ? -1 : (_byId[current!.id] ?? -1);

  /// Album du morceau en cours (index dans [albums]), ou -1.
  int get currentAlbum {
    final i = currentIndex;
    if (i < 0) return -1;
    return albums.lastIndexWhere((a) => a.firstIndex <= i);
  }

  void _onEngine(EngineUpdate u) {
    if (u.position != null) _anchorPosition(u.position!);
    if (u.playing != null) {
      // La position repart de là où elle est, pas de la dernière reçue.
      if (u.position == null) _anchorPosition(smoothPosition);
      playing = u.playing!;
    }
    if (u.duration != null) duration = u.duration!;
    if (u.volume != null) volume = u.volume!;
    if (u.shuffle != null && u.shuffle != shuffling) {
      shuffle = u.shuffle!;
      Settings.setString('player.shuffle', shuffle ? 'on' : 'off');
    }
    if (u.repeat != null && u.repeat != repeat) {
      repeat = u.repeat!;
      Settings.setString('player.repeat', repeat.name);
    }
    Track? next = current;
    if (u.index != null) {
      queueIndex = u.index!;
      next = queueIndex >= 0 && queueIndex < nowPlaying.length ? nowPlaying[queueIndex] : u.track;
    } else if (u.track != null) {
      next = u.track;
    }
    if (next?.id != current?.id) {
      current = next;
      if (next?.duration != null && u.duration == null) duration = next!.duration!;
      _onTrackChanged();
    }
    notifyListeners();
  }

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

  // --- Aléatoire et répétition -------------------------------------------------

  /// Lecture aléatoire et répétition (Réglages), retenues d'un lancement à
  /// l'autre.
  bool shuffle = false;
  RepeatMode repeat = RepeatMode.off;

  /// Aléatoire imposé par l'appareil (les shuffle n'ont pas d'écran, ils
  /// jouent toujours au hasard), sans toucher au réglage [shuffle].
  bool forcedShuffle = false;

  /// Lecture aléatoire en vigueur : le réglage, ou l'appareil qui l'impose.
  bool get shuffling => shuffle || forcedShuffle;

  Future<void> setForcedShuffle(bool on) async {
    if (on == forcedShuffle) return;
    final was = shuffling;
    forcedShuffle = on;
    if (shuffling != was) await _run((e) => e.setShuffle(shuffling));
  }

  Future<void> setShuffle(bool on) async {
    final was = shuffling;
    shuffle = on;
    Settings.setString('player.shuffle', on ? 'on' : 'off');
    notifyListeners();
    if (shuffling != was) await _run((e) => e.setShuffle(shuffling));
  }

  Future<void> setRepeat(RepeatMode r) async {
    repeat = r;
    Settings.setString('player.repeat', r.name);
    notifyListeners();
    await _run((e) => e.setRepeat(r));
  }

  // --- Pochettes des albums (Cover Flow) -------------------------------------

  final Map<int, Uint8List?> _albumCovers = {};
  final Set<int> _coverLoads = {};
  int _coverGeneration = 0;

  /// Pochette de l'album [i] si elle est déjà lue ; sinon null, et elle est
  /// lue en arrière-plan (l'écran est prévenu quand elle arrive).
  Uint8List? albumCover(int i) {
    if (_albumCovers.containsKey(i)) return _albumCovers[i];
    if (!_preview && i >= 0 && i < albums.length && _coverLoads.add(i)) {
      final generation = _coverGeneration;
      _source.artwork(tracks[albums[i].firstIndex]).then((bytes) {
        if (generation != _coverGeneration) return; // autre bibliothèque entre-temps
        _albumCovers[i] = bytes;
        _coverLoads.remove(i);
        notifyListeners();
      }, onError: (_) {
        _coverLoads.remove(i);
      });
    }
    return null;
  }

  // --- Nombre d'écoutes (liste « Les plus écoutés ») -------------------------

  Map<String, int> _plays = {};
  Timer? _savePlays;

  /// Les morceaux les plus écoutés, du plus au moins écouté.
  List<Track> mostPlayed(int count) {
    final list = [
      for (final t in tracks)
        if ((_plays[t.id] ?? 0) > 0) t,
    ]..sort((a, b) => (_plays[b.id] ?? 0).compareTo(_plays[a.id] ?? 0));
    return list.take(count).toList();
  }

  /// Les derniers morceaux arrivés, du plus récent au plus ancien.
  List<Track> recentlyAdded(int count) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final list = [...tracks]..sort((a, b) => (b.added ?? epoch).compareTo(a.added ?? epoch));
    return list.take(count).toList();
  }

  static Map<String, int> _loadPlays() {
    final raw = Settings.getMap('plays');
    return {
      for (final e in raw.entries)
        if (e.value is int) e.key: e.value as int,
    };
  }

  void _countPlay(Track t) {
    _plays[t.id] = (_plays[t.id] ?? 0) + 1;
    _savePlays?.cancel();
    _savePlays = Timer(const Duration(seconds: 5), () => Settings.setMap('plays', _plays));
  }

  int _coverRequest = 0;

  Future<void> _onTrackChanged() async {
    final track = current;
    if (track != null && playing) _countPlay(track);
    final request = ++_coverRequest;
    Uint8List? bytes;
    try {
      bytes = track == null || _preview ? null : await _source.artwork(track);
    } catch (_) {}
    if (request != _coverRequest) return; // un autre morceau entre-temps
    cover = bytes;
    notifyListeners();
  }

  // --- Commandes -----------------------------------------------------------

  /// Joue [list] à partir du morceau [start]. [uri] : la même liste pour la
  /// source (album ou liste Spotify), quand elle en a une.
  Future<void> playTracks(List<Track> list, int start, {String? uri}) async {
    if (list.isEmpty) return;
    start = start.clamp(0, list.length - 1);
    nowPlaying = list;
    queueIndex = start;
    if (current?.id != list[start].id) {
      current = list[start];
      duration = current!.duration ?? Duration.zero;
      _anchorPosition(Duration.zero);
      _onTrackChanged();
    }
    _countPlay(list[start]);
    notifyListeners();
    await _run((e) => e.open(list, start, uri: uri));
  }

  /// Joue une liste dont on ne connaît que l'identifiant chez la source
  /// (liste Spotify qu'on ne peut pas parcourir).
  Future<void> playUri(String uri) async {
    nowPlaying = const [];
    queueIndex = -1;
    notifyListeners();
    await _run((e) => e.open(const [], 0, uri: uri));
  }

  /// Joue l'album [i] à partir de son morceau [track].
  Future<void> playAlbum(int i, [int track = 0]) {
    final a = albums[i];
    return playTracks(tracks.sublist(a.firstIndex, a.firstIndex + a.trackCount), track, uri: a.uri);
  }

  Future<void> playPause() => playing ? pause() : play();

  Future<void> play() async {
    if (_preview) return _previewPlaying(true);
    // Rien de lancé encore (ni ici, ni ailleurs sur le compte) : toute la
    // bibliothèque, depuis le début.
    if (nowPlaying.isEmpty && current == null) return playTracks(tracks, 0);
    final t = current;
    if (!playing && t != null && smoothPosition < const Duration(seconds: 1)) _countPlay(t);
    await _run((e) => e.play());
  }

  Future<void> pause() => _preview ? _previewPlaying(false) : _run((e) => e.pause());

  /// En mode aperçu, lecture et pause changent quand même l'état affiché.
  Future<void> _previewPlaying(bool play) async {
    playing = play;
    notifyListeners();
  }

  Future<void> next() => _run((e) => e.next());
  Future<void> previous() => _run((e) => e.previous());

  Future<void> seekProgress(double p) async {
    final target = duration * p.clamp(0.0, 1.0);
    _anchorPosition(target);
    await _run((e) => e.seek(target));
  }

  Future<void> setVolume(double v) {
    // Tout de suite à l'écran : un moteur distant répond plus tard.
    volume = v.clamp(0, 100);
    notifyListeners();
    return _run((e) => e.setVolume(volume));
  }

  /// L'écran En lecture s'affiche : un moteur distant se remet à jour.
  void refresh() => _engine.refresh();

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
    _engine
      ..onUpdate = null
      ..dispose();
    _source.dispose();
    super.dispose();
  }
}

/// Erreur à montrer telle quelle à l'utilisateur.
class NoticeException implements Exception {
  const NoticeException(this.message);

  final String message;

  @override
  String toString() => message;
}
