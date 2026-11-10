import 'dart:async';
import 'dart:math' as math;

import '../../core/engine.dart';
import '../../core/library.dart';
import '../../core/settings.dart';
import 'api.dart';
import 'spotify_source.dart';

/// Lecture par Spotify Connect : TinyPod est la télécommande d'un appareil
/// Spotify (appli Spotify, spotifyd, enceinte…) qui, lui, joue le son.
///
/// Spotify ne prévient de rien : l'état est demandé chaque seconde en
/// lecture, moins souvent sinon ; entre deux réponses, le lecteur fait
/// avancer la position tout seul. Les commandes changent l'état tout de
/// suite à l'écran, sans attendre Spotify.
class SpotifyConnectEngine extends PlaybackEngine {
  SpotifyConnectEngine(this.account) {
    account.warmUp();
    _unmuteLeftover().whenComplete(_poll);
  }

  final SpotifyAccount account;
  SpotifyApi get _api => account.api;

  List<Track> _queue = const [];
  bool _polling = false;
  bool _disposed = false;

  /// Spotify n'accepte qu'un nombre limité de morceaux à la fois.
  static const _window = 100;

  /// Fin (exclue) des morceaux de [_queue] déjà donnés à Spotify, quand on
  /// lui a donné une suite de morceaux : on lui donne les suivants un à un,
  /// à mesure qu'il arrive au bout.
  int _sentTo = 0;
  bool _extending = false;

  /// Ce qu'on sait de l'état, d'après la dernière réponse ou commande.
  bool _playing = false;
  bool _shuffle = false;

  /// Réglages demandés alors que rien ne jouait nulle part (Spotify les
  /// refuse) : appliqués à la prochaine lecture.
  bool? _pendingShuffle;
  RepeatMode? _pendingRepeat;

  /// Après une commande, Spotify met un moment à la refléter : on ignore
  /// les réponses d'ici là (sinon l'écran reviendrait en arrière).
  DateTime _quietUntil = DateTime(0);

  /// Commandes longues en cours (lancer l'appli Spotify, lui donner la
  /// lecture) : l'état d'ici là ne dit rien.
  int _commands = 0;

  void _emit(EngineUpdate u) {
    if (_disposed) return;
    if (u.playing != null) _playing = u.playing!;
    onUpdate?.call(u);
  }

  void _quiet([int ms = 1200]) => _quietUntil = DateTime.now().add(Duration(milliseconds: ms));

  // --- Demander l'état ---------------------------------------------------------

  Timer? _timer;

  /// Demandes ratées de suite (réseau coupé…) : on espace.
  int _failures = 0;

  /// Spotify a demandé de ralentir (429) : rien avant cette heure.
  DateTime _blockedUntil = DateTime(0);

  /// Prochaine demande : dans une seconde en lecture ; toutes les cinq
  /// secondes sinon (une lecture lancée ailleurs finit par se voir, sans
  /// interroger Spotify 86 400 fois par jour pour rien).
  void _schedule() {
    _timer?.cancel();
    if (_disposed) return;
    var wait = Duration(seconds: _playing ? 1 : 5);
    if (_failures > 0) wait = Duration(seconds: math.min(60, 2 << math.min(_failures, 5)));
    final blocked = _blockedUntil.difference(DateTime.now());
    if (blocked > wait) wait = blocked;
    _timer = Timer(wait, _poll);
  }

  Future<void> _poll({bool force = false}) async {
    if (_disposed || _polling) return;
    final now = DateTime.now();
    if (!account.connected || _commands > 0 || now.isBefore(_blockedUntil) || (!force && now.isBefore(_quietUntil))) {
      _schedule();
      return;
    }
    _polling = true;
    try {
      final st = await _api.get('/me/player', {'additional_types': 'track'});
      _failures = 0;
      if (_disposed || _commands > 0 || (!force && DateTime.now().isBefore(_quietUntil))) return;
      if (st == null) {
        // Rien sur aucun appareil.
        _emit(const EngineUpdate(playing: false));
        return;
      }
      final item = st['item'] as Map<String, Object?>?;
      final track = item != null && item['type'] == 'track' ? spotifyTrack(item) : null;
      final device = st['device'] as Map<String, Object?>?;
      final index = track == null ? null : _queue.indexWhere((t) => t.id == track.id);
      if (st['shuffle_state'] case final bool on) _shuffle = on;
      _emit(EngineUpdate(
        playing: st['is_playing'] == true,
        position: Duration(milliseconds: (st['progress_ms'] as num?)?.toInt() ?? 0),
        duration: track?.duration,
        volume: (device?['volume_percent'] as num?)?.toDouble(),
        index: index,
        track: track,
        shuffle: st['shuffle_state'] as bool?,
        repeat: switch (st['repeat_state']) {
          'track' => RepeatMode.one,
          'context' => RepeatMode.all,
          'off' => RepeatMode.off,
          _ => null,
        },
      ));
      if (index != null && _playing) _extend(index);
    } on SpotifyError catch (e) {
      if (e.status == 429) {
        _blockedUntil = DateTime.now().add(Duration(seconds: e.retryAfter ?? 30));
      } else {
        _failures++;
      }
    } catch (_) {
      // Réseau coupé, jeton expiré… on réessaie, de moins en moins souvent.
      _failures++;
    } finally {
      _polling = false;
      _schedule();
    }
  }

  /// Le dernier morceau donné à Spotify est en cours : on met le suivant
  /// de notre file à la suite, pour que la lecture ne s'arrête pas là.
  Future<void> _extend(int index) async {
    if (_extending || index != _sentTo - 1 || _sentTo >= _queue.length) return;
    _extending = true;
    try {
      await _api.post('/me/player/queue', query: {'uri': _queue[_sentTo].id});
      _sentTo++;
    } catch (_) {
      _sentTo = _queue.length; // refusé : on n'insiste pas
    } finally {
      _extending = false;
    }
  }

  /// Demande l'état bientôt (après une commande).
  void _soon() {
    _quiet(700);
    Timer(const Duration(milliseconds: 750), () => _poll(force: true));
  }

  // --- Commandes ---------------------------------------------------------------

  /// Lance [command] sur l'appareil de ce PC (la lecture y revient si elle
  /// était ailleurs). S'il a disparu entre-temps, on le cherche à nouveau.
  Future<void> _onThisPc(Future<void> Function(Map<String, String> query) command) async {
    _commands++;
    try {
      final device = await account.thisPcDevice();
      try {
        await command({'device_id': device});
      } on SpotifyError catch (e) {
        if (e.status != 404) rethrow;
        await command({'device_id': await account.thisPcDevice(fresh: true)});
      }
    } catch (_) {
      _emit(const EngineUpdate(playing: false));
      rethrow;
    } finally {
      _commands--;
      _quiet();
    }
  }

  /// Aléatoire et répétition demandés quand rien ne jouait : maintenant
  /// qu'un appareil joue, Spotify les accepte.
  Future<void> _applyPending() async {
    await _unmuteLeftover();
    final shuffle = _pendingShuffle, repeat = _pendingRepeat;
    _pendingShuffle = _pendingRepeat = null;
    try {
      if (shuffle != null) await _api.put('/me/player/shuffle', query: {'state': '$shuffle'});
      if (repeat != null) await _api.put('/me/player/repeat', query: {'state': _repeatName(repeat)});
    } catch (_) {}
  }

  @override
  Future<void> open(List<Track> queue, int start, {String? uri}) async {
    _queue = queue;
    _sentTo = queue.length; // (rien à compléter, sauf suite de morceaux coupée)
    final Map<String, Object?> body;
    if (uri != null) {
      // L'album ou la liste tels que Spotify les connaît, à partir du
      // morceau choisi.
      body = {
        'context_uri': uri,
        if (queue.isNotEmpty) 'offset': {'uri': queue[start].id},
      };
    } else if (queue.length > _window && (_pendingShuffle ?? _shuffle)) {
      // Trop de morceaux, en aléatoire : le morceau choisi, puis d'autres
      // tirés au hasard dans toute la file (Spotify ne mélange que ce
      // qu'on lui donne).
      final others = [for (var i = 0; i < queue.length; i++) if (i != start) i]..shuffle();
      body = {
        'uris': [queue[start].id, for (final i in others.take(_window - 1)) queue[i].id],
        'offset': {'position': 0},
      };
    } else {
      // Une suite de morceaux : ceux autour du morceau choisi ; la suite
      // sera donnée au fur et à mesure (voir [_extend]).
      final from = math.max(0, start - 20);
      final to = math.min(queue.length, from + _window);
      _sentTo = to;
      body = {
        'uris': [for (final t in queue.sublist(from, to)) t.id],
        'offset': {'position': start - from},
      };
    }
    // L'appareil est prêt : ça joue tout de suite à l'écran. Sinon (l'appli
    // Spotify doit d'abord se lancer), le morceau attend à zéro : la barre
    // n'avance pas sans le son.
    final ready = account.deviceReady;
    _quiet();
    _emit(EngineUpdate(playing: ready, position: Duration.zero, index: queue.isEmpty ? null : start));
    await _onThisPc((q) => _api.put('/me/player/play', query: q, body: body));
    if (!ready) _emit(const EngineUpdate(playing: true, position: Duration.zero));
    await _applyPending();
    _soon();
  }

  @override
  Future<void> play() async {
    final ready = account.deviceReady;
    _quiet();
    if (ready) _emit(const EngineUpdate(playing: true));
    await _onThisPc((q) => _api.put('/me/player/play', query: q));
    if (!ready) _emit(const EngineUpdate(playing: true));
    await _applyPending();
    _soon();
  }

  @override
  Future<void> pause() async {
    _quiet();
    _emit(const EngineUpdate(playing: false));
    try {
      await _api.put('/me/player/pause');
    } on SpotifyError catch (e) {
      // Déjà en pause, ou plus rien nulle part : c'est ce qu'on voulait.
      if (e.status != 403 && e.status != 404) rethrow;
    }
    _soon();
  }

  @override
  Future<void> next() async {
    _quiet();
    await _api.post('/me/player/next');
    _soon();
  }

  @override
  Future<void> previous() async {
    _quiet();
    await _api.post('/me/player/previous');
    _soon();
  }

  Timer? _seekTimer;

  @override
  Future<void> seek(Duration position) async {
    // La molette avance par petits pas : on n'envoie que le dernier.
    _quiet(1500);
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 250), () {
      _api.put('/me/player/seek', query: {'position_ms': '${position.inMilliseconds}'}).then((_) => _soon(), onError: (_) {});
    });
  }

  Timer? _volumeTimer;

  @override
  Future<void> setVolume(double volume) async {
    _quiet(1500);
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 200), () {
      _api.put('/me/player/volume', query: {'volume_percent': '${volume.round()}'}).then((_) => _soon(), onError: (_) {});
    });
  }

  @override
  bool get slow => true;

  /// (Noté dans les préférences : si l'appli se ferme prise débranchée, le
  /// volume est rendu au lancement suivant au lieu de rester à zéro.)
  static const _mutedKey = 'spotify.mutedFrom';

  @override
  Future<void> mute(bool on, double volume) async {
    _volumeTimer?.cancel();
    _quiet(1500);
    if (on) Settings.setString(_mutedKey, '${volume.round()}');
    try {
      await _api.put('/me/player/volume', query: {'volume_percent': on ? '0' : '${volume.round()}'});
    } finally {
      if (!on) Settings.remove(const [_mutedKey]);
      _soon();
    }
  }

  /// Un volume coupé par la prise et jamais rendu (appli fermée pendant un
  /// changement d'iPod) : on le rend.
  Future<void> _unmuteLeftover() async {
    final from = int.tryParse(Settings.getString(_mutedKey) ?? '');
    if (from == null) return;
    try {
      await _api.put('/me/player/volume', query: {'volume_percent': '$from'});
      Settings.remove(const [_mutedKey]);
    } catch (_) {
      // Aucun appareil pour l'instant : à la prochaine lecture.
    }
  }

  @override
  Future<void> setShuffle(bool on) async {
    _shuffle = on;
    _quiet();
    try {
      await _api.put('/me/player/shuffle', query: {'state': '$on'});
      _pendingShuffle = null;
    } on SpotifyError catch (e) {
      if (e.status != 404) rethrow;
      _pendingShuffle = on; // rien ne joue encore : à la prochaine lecture
    }
    _soon();
  }

  static String _repeatName(RepeatMode mode) => switch (mode) {
        RepeatMode.off => 'off',
        RepeatMode.one => 'track',
        RepeatMode.all => 'context',
      };

  @override
  Future<void> setRepeat(RepeatMode mode) async {
    _quiet();
    try {
      await _api.put('/me/player/repeat', query: {'state': _repeatName(mode)});
      _pendingRepeat = null;
    } on SpotifyError catch (e) {
      if (e.status != 404) rethrow;
      _pendingRepeat = mode;
    }
    _soon();
  }

  @override
  void refresh() => _poll(force: true);

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _seekTimer?.cancel();
    _volumeTimer?.cancel();
  }
}
