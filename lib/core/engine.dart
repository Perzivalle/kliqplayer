import '../core/library.dart';

/// Répétition : rien, le morceau en cours, ou toute la file.
enum RepeatMode { off, one, all }

/// Ce qui a changé dans le moteur (null : inchangé).
class EngineUpdate {
  const EngineUpdate({
    this.playing,
    this.position,
    this.duration,
    this.volume,
    this.index,
    this.track,
    this.shuffle,
    this.repeat,
  });

  final bool? playing;
  final Duration? position;
  final Duration? duration;

  /// De 0 à 100.
  final double? volume;

  /// Rang du morceau dans la file lancée ; -1 s'il n'en fait pas partie
  /// (lancé ailleurs, depuis l'appli Spotify par exemple).
  final int? index;

  /// Le morceau en cours, quand le moteur le connaît mieux que la file
  /// (lancé ailleurs) ; sinon c'est celui de la file à [index].
  final Track? track;

  /// Aléatoire et répétition changés ailleurs (appli Spotify).
  final bool? shuffle;
  final RepeatMode? repeat;
}

/// Ce qui joue le son : media_kit pour les fichiers, un appareil Spotify
/// Connect pour Spotify… L'interface ne le voit qu'au travers du
/// PlayerController.
abstract class PlaybackEngine {
  /// Appelé à chaque changement d'état.
  void Function(EngineUpdate update)? onUpdate;

  /// Joue [queue] à partir du morceau [start]. [uri] : la même file pour
  /// la source (album, liste), quand elle en a une.
  Future<void> open(List<Track> queue, int start, {String? uri});

  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);

  /// De 0 à 100.
  Future<void> setVolume(double volume);
  Future<void> setShuffle(bool on);
  Future<void> setRepeat(RepeatMode mode);

  /// Aléatoire et répétition retenus (Réglages), donnés au moteur neuf avant
  /// toute lecture. Un moteur distant a déjà les siens : il n'en fait rien.
  void restore({required bool shuffle, required RepeatMode repeat}) {}

  /// Le moteur met du temps à obéir (appareil distant) : pour un silence
  /// bref, mieux vaut couper le son que mettre en pause puis relancer, qui
  /// arriveraient en retard l'un et l'autre.
  bool get slow => false;

  /// Coupe le son sans arrêter la lecture ([on]), ou le rend, à [volume]
  /// (de 0 à 100). Seulement pour un moteur [slow].
  Future<void> mute(bool on, double volume) async {}

  /// L'appli revient au premier plan, ou l'écran En lecture s'affiche :
  /// un moteur distant peut en profiter pour se remettre à jour.
  void refresh() {}

  void dispose();
}

/// Moteur qui ne fait rien (tests, aperçu).
class SilentEngine extends PlaybackEngine {
  List<Track> _queue = const [];
  int _index = -1;

  void _emit(EngineUpdate u) => onUpdate?.call(u);

  @override
  Future<void> open(List<Track> queue, int start, {String? uri}) async {
    _queue = queue;
    _index = start;
    _emit(EngineUpdate(index: start, playing: true, position: Duration.zero, duration: queue[start].duration));
  }

  @override
  Future<void> play() async => _emit(const EngineUpdate(playing: true));
  @override
  Future<void> pause() async => _emit(const EngineUpdate(playing: false));
  @override
  Future<void> next() async {
    if (_index + 1 < _queue.length) _emit(EngineUpdate(index: ++_index));
  }

  @override
  Future<void> previous() async {
    if (_index > 0) _emit(EngineUpdate(index: --_index));
  }

  @override
  Future<void> seek(Duration position) async => _emit(EngineUpdate(position: position));
  @override
  Future<void> setVolume(double volume) async => _emit(EngineUpdate(volume: volume));
  @override
  Future<void> setShuffle(bool on) async {}
  @override
  Future<void> setRepeat(RepeatMode mode) async {}
  @override
  void dispose() {}
}
