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
    _migratePlays();
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
    _engine = source.createEngine()
      ..onUpdate = _onEngine
      // Le moteur neuf ne sait rien des réglages retenus.
      ..restore(shuffle: shuffling, repeat: repeat);
    // La source a du nouveau (bibliothèque rafraîchie en arrière-plan).
    source.onChanged = () {
      if (identical(source, _source)) loadLibrary();
    };
  }

  /// Change de source (dossier → Spotify…) : l'ancienne s'arrête, la
  /// nouvelle est chargée.
  Future<void> setSource(MusicSource source) {
    // L'un après l'autre : deux changements rapprochés libéreraient sinon
    // deux fois le même moteur.
    return _switching = _switching.then((_) => _setSource(source), onError: (_) => _setSource(source));
  }

  Future<void> _switching = Future.value();

  Future<void> _setSource(MusicSource source) async {
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
    _source
      ..onChanged = null
      ..dispose();
    _attach(source);
    // Rien de l'ancienne source ne reste, même si la nouvelle ne se charge pas.
    tracks = const [];
    albums = const [];
    playlists = const [];
    _indexTracks();
    libraryVersion++;
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

  /// Change à chaque nouvelle bibliothèque : les menus ouverts sur
  /// l'ancienne (albums, morceaux) ne valent plus.
  int libraryVersion = 0;

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
      // On garde ce qu'on avait (rafraîchissement raté) ; le menu principal
      // montre l'erreur, la valider réessaie.
      library = Library(tracks, albums, playlists);
      loadError = e;
      notice = _message(e);
    }
    if (!identical(source, _source)) return; // une autre source entre-temps
    if (loadError == null && !identical(library.tracks, tracks)) libraryVersion++;
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

  static String _message(Object e) => e is NoticeException ? e.message : '$e';

  void _fail(Object e) {
    notice = _message(e);
    notifyListeners();
  }

  /// Le message a été vu (validé dans le menu) : il s'efface ; si c'était
  /// la bibliothèque qui n'avait pas pu se charger, on réessaie.
  void dismissNotice() {
    notice = null;
    if (loadError != null) {
      loadLibrary();
    } else {
      notifyListeners();
    }
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
    // Une position seule, là où on l'attendait : on se recale sans prévenir
    // personne. L'écran avance déjà tout seul ([smoothPosition]) ; mpv en
    // envoie une quinzaine par seconde, qui le reconstruiraient autant de
    // fois, même dans les menus.
    final onlyPosition = u.position != null &&
        u.playing == null &&
        u.duration == null &&
        u.volume == null &&
        u.index == null &&
        u.track == null &&
        u.shuffle == null &&
        u.repeat == null;
    if (onlyPosition && (u.position! - smoothPosition).abs() < const Duration(milliseconds: 400)) {
      _anchorPosition(u.position!);
      return;
    }
    if (u.position != null) _anchorPosition(u.position!);
    if (u.playing != null) {
      // La position repart de là où elle est, pas de la dernière reçue.
      if (u.position == null) _anchorPosition(smoothPosition);
      playing = u.playing!;
    }
    if (u.duration != null) duration = u.duration!;
    // (Son coupé par la prise débranchée : ce zéro-là n'est pas le réglage.)
    if (u.volume != null && _mutedFrom == null) volume = u.volume!;
    // (Un shuffle en main impose l'aléatoire : celui de la source ne dit
    // alors rien du réglage.)
    if (u.shuffle != null && !forcedShuffle && u.shuffle != shuffle) {
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

  /// Les dernières pochettes servies seulement : gardées toutes, celles
  /// d'une grande bibliothèque (souvent plus d'un Mo chacune, dans les
  /// fichiers) finiraient par peser des centaines de Mo.
  final Map<int, Uint8List?> _albumCovers = {};
  static const _coversKept = 60;
  final Set<int> _coverLoads = {};
  int _coverGeneration = 0;

  /// Pochette de l'album [i] si elle est déjà lue ; sinon null, et elle est
  /// lue en arrière-plan (l'écran est prévenu quand elle arrive).
  Uint8List? albumCover(int i) {
    if (_albumCovers.containsKey(i)) {
      final bytes = _albumCovers[i];
      // Servie à l'instant : elle repasse en fin de file, la dernière à partir.
      if (!_preview && _albumCovers.keys.last != i) {
        _albumCovers
          ..remove(i)
          ..[i] = bytes;
      }
      return bytes;
    }
    if (!_preview && i >= 0 && i < albums.length && _coverLoads.add(i)) {
      final generation = _coverGeneration;
      _source.artwork(tracks[albums[i].firstIndex]).then((bytes) {
        if (generation != _coverGeneration) return; // autre bibliothèque entre-temps
        _albumCovers[i] = bytes;
        while (_albumCovers.length > _coversKept) {
          _albumCovers.remove(_albumCovers.keys.first);
        }
        _coverLoads.remove(i);
        notifyListeners();
      }, onError: (_) {
        _coverLoads.remove(i);
      });
    }
    return null;
  }

  // --- Nombre d'écoutes (liste « Les plus écoutés ») -------------------------

  /// Dans plays.json, à part des préférences : il grossit avec la
  /// bibliothèque et change à chaque morceau.
  static final _playsStore = JsonStore('plays.json');

  /// (Sous `flutter test`, chaque lecteur a les siennes.)
  late final Map<String, Object?> _plays = JsonStore.inTest ? {} : _playsStore.values;

  int _playsOf(Track t) => switch (_plays[t.id]) { final int n => n, _ => 0 };

  /// Les écoutes étaient rangées dans les préférences (jusqu'à la 0.5.0).
  static void _migratePlays() {
    final old = Settings.getMap('plays');
    if (old.isEmpty) return;
    if (_playsStore.values.isEmpty) {
      _playsStore.values.addAll(old);
      _playsStore.changed();
    }
    Settings.remove(const ['plays']);
  }

  /// Les morceaux les plus écoutés, du plus au moins écouté.
  List<Track> mostPlayed(int count) {
    final list = [
      for (final t in tracks)
        if (_playsOf(t) > 0) t,
    ]..sort((a, b) => _playsOf(b).compareTo(_playsOf(a)));
    return list.take(count).toList();
  }

  /// Les derniers morceaux arrivés, du plus récent au plus ancien.
  List<Track> recentlyAdded(int count) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final list = [...tracks]..sort((a, b) => (b.added ?? epoch).compareTo(a.added ?? epoch));
    return list.take(count).toList();
  }

  // --- Notes en étoiles (écran « En lecture ») ---------------------------------

  static final _ratingsStore = JsonStore('ratings.json');

  /// (Sous `flutter test`, chaque lecteur a les siennes.)
  late final Map<String, Object?> _ratings = JsonStore.inTest ? {} : _ratingsStore.values;

  /// La note de [t], de 0 (aucune) à 5 étoiles.
  int rating(Track t) => switch (_ratings[t.id]) { final int n => n.clamp(0, 5), _ => 0 };

  void setRating(Track t, int stars) {
    if (stars <= 0) {
      _ratings.remove(t.id);
    } else {
      _ratings[t.id] = stars.clamp(1, 5);
    }
    _ratingsStore.changed();
    notifyListeners();
  }

  void _countPlay(Track t) {
    _plays[t.id] = _playsOf(t) + 1;
    _playsStore.changed();
  }

  int _coverRequest = 0;

  /// [count] : c'est une écoute de plus (le morceau suivant qui démarre) ;
  /// faux quand on vient de le lancer soi-même, déjà compté.
  Future<void> _onTrackChanged({bool count = true}) async {
    final track = current;
    if (count && track != null && playing) _countPlay(track);
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
      _onTrackChanged(count: false);
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

  // --- Prise casque ----------------------------------------------------------

  bool _resumeOnPlug = false;

  /// Volume d'avant, tant que le son est coupé par la prise débranchée.
  double? _mutedFrom;

  /// La prise est arrachée : plus de son, comme avec de vrais écouteurs.
  /// Un fichier se met en pause sur-le-champ. Un appareil distant (Spotify)
  /// obéit avec du retard, la pause et la reprise tomberaient à côté du
  /// geste : on lui coupe seulement le son, la musique continue sans nous.
  void unplug() {
    if (!playing || _mutedFrom != null) return;
    if (_engine.slow) {
      _mutedFrom = volume;
      _engine.mute(true, volume).catchError((_) {});
    } else {
      _resumeOnPlug = true;
      pause();
    }
  }

  /// Rebranchée : le son revient (la musique reprend là où elle s'était
  /// arrêtée, ou là où elle en est).
  void plug() {
    if (_mutedFrom case final v?) {
      _mutedFrom = null;
      _engine.mute(false, v).catchError((_) {});
    } else if (_resumeOnPlug) {
      play();
    }
    _resumeOnPlug = false;
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

  @override
  void dispose() {
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
