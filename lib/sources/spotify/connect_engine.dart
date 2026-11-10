import 'dart:async';
import 'dart:math' as math;

import '../../core/engine.dart';
import '../../core/library.dart';
import 'api.dart';
import 'spotify_source.dart';

/// Lecture par Spotify Connect : TinyPod est la télécommande d'un appareil
/// Spotify (appli Spotify, spotifyd, enceinte…) qui, lui, joue le son.
///
/// L'état est demandé toutes les secondes (Spotify ne prévient de rien) ;
/// entre deux réponses, le lecteur fait avancer la position tout seul. Les
/// commandes changent l'état tout de suite à l'écran, sans attendre
/// Spotify.
class SpotifyConnectEngine extends PlaybackEngine {
  SpotifyConnectEngine(this.account) {
    account.warmUp();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    _poll();
  }

  final SpotifyAccount account;
  SpotifyApi get _api => account.api;
  late final Timer _timer;

  List<Track> _queue = const [];
  bool _polling = false;
  bool _disposed = false;

  /// Après une commande, Spotify met un moment à la refléter : on ignore
  /// les réponses d'ici là (sinon l'écran reviendrait en arrière).
  DateTime _quietUntil = DateTime(0);


  void _emit(EngineUpdate u) {
    if (!_disposed) onUpdate?.call(u);
  }

  void _quiet([int ms = 1200]) => _quietUntil = DateTime.now().add(Duration(milliseconds: ms));

  Future<void> _poll({bool force = false}) async {
    if (_polling || _disposed || !account.connected) return;
    if (!force && DateTime.now().isBefore(_quietUntil)) return;
    _polling = true;
    try {
      final st = await _api.get('/me/player', {'additional_types': 'track'});
      if (_disposed || (!force && DateTime.now().isBefore(_quietUntil))) return;
      if (st == null) {
        // Rien sur aucun appareil.
        _emit(const EngineUpdate(playing: false));
        return;
      }
      final item = st['item'] as Map<String, Object?>?;
      final track = item != null && item['type'] == 'track' ? spotifyTrack(item) : null;
      final device = st['device'] as Map<String, Object?>?;
      _emit(EngineUpdate(
        playing: st['is_playing'] == true,
        position: Duration(milliseconds: (st['progress_ms'] as num?)?.toInt() ?? 0),
        duration: track?.duration,
        volume: (device?['volume_percent'] as num?)?.toDouble(),
        index: track == null ? null : _queue.indexWhere((t) => t.id == track.id),
        track: track,
        shuffle: st['shuffle_state'] as bool?,
        repeat: switch (st['repeat_state']) {
          'track' => RepeatMode.one,
          'context' => RepeatMode.all,
          'off' => RepeatMode.off,
          _ => null,
        },
      ));
    } catch (_) {
      // Réseau coupé, jeton expiré… on réessaie à la prochaine seconde.
    } finally {
      _polling = false;
    }
  }

  /// Demande l'état bientôt (après une commande).
  void _soon() {
    _quiet(700);
    Timer(const Duration(milliseconds: 750), () => _poll(force: true));
  }

  /// Lance [command] sur l'appareil de ce PC (la lecture y revient si elle
  /// était ailleurs). S'il a disparu entre-temps, on le cherche à nouveau.
  Future<void> _onThisPc(Future<void> Function(Map<String, String> query) command) async {
    final device = await account.thisPcDevice();
    try {
      await command({'device_id': device});
    } on SpotifyError catch (e) {
      if (e.status != 404) rethrow;
      await command({'device_id': await account.thisPcDevice()});
    }
  }

  @override
  Future<void> open(List<Track> queue, int start, {String? uri}) async {
    _queue = queue;
    final Map<String, Object?> body;
    if (uri != null) {
      // L'album ou la liste tels que Spotify les connaît, à partir du
      // morceau choisi.
      body = {
        'context_uri': uri,
        if (queue.isNotEmpty) 'offset': {'uri': queue[start].id},
      };
    } else {
      // Une suite de morceaux : Spotify n'en prend qu'un nombre limité, on
      // envoie ceux autour du morceau choisi.
      final from = math.max(0, start - 20);
      final to = math.min(queue.length, from + 100);
      body = {
        'uris': [for (final t in queue.sublist(from, to)) t.id],
        'offset': {'position': start - from},
      };
    }
    _quiet();
    _emit(EngineUpdate(playing: true, position: Duration.zero, index: queue.isEmpty ? null : start));
    await _onThisPc((q) => _api.put('/me/player/play', query: q, body: body));
    _soon();
  }

  @override
  Future<void> play() async {
    _quiet();
    _emit(const EngineUpdate(playing: true));
    await _onThisPc((q) => _api.put('/me/player/play', query: q));
    _soon();
  }

  @override
  Future<void> pause() async {
    _quiet();
    _emit(const EngineUpdate(playing: false));
    await _api.put('/me/player/pause');
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
  Future<void> setShuffle(bool on) async {
    _quiet();
    await _api.put('/me/player/shuffle', query: {'state': '$on'});
    _soon();
  }

  @override
  Future<void> setRepeat(RepeatMode mode) async {
    _quiet();
    final state = switch (mode) {
      RepeatMode.off => 'off',
      RepeatMode.one => 'track',
      RepeatMode.all => 'context',
    };
    await _api.put('/me/player/repeat', query: {'state': state});
    _soon();
  }

  @override
  void refresh() => _poll(force: true);

  @override
  void dispose() {
    _disposed = true;
    _timer.cancel();
    _seekTimer?.cancel();
    _volumeTimer?.cancel();
  }
}
