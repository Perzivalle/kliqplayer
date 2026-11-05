import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Le petit « tic » de la molette, joué par le haut-parleur de l'appareil
/// (indépendant du volume de la musique). Le son est synthétisé au
/// démarrage : un claquement bref et sec, pas d'échantillon à fournir.
class WheelClick {
  WheelClick._();

  static final WheelClick instance = WheelClick._();

  AudioSource? _source;
  Future<void>? _loading;

  /// Volume du clic, de 0 à 1.
  double volume = 0.55;

  Future<void> _load() async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      // Petit tampon : le clic doit partir sans délai perceptible.
      await soloud.init(bufferSize: 512);
    }
    _source = await soloud.loadMem('wheel-click.wav', _synthesize());
  }

  /// Joue le clic ; sans effet (et sans erreur) si l'audio n'est pas prêt.
  void play() {
    final source = _source;
    if (source == null) {
      _loading ??= _load().catchError((Object e) {
        debugPrint('Clic de la molette indisponible : $e');
      });
      return;
    }
    SoLoud.instance.play(source, volume: volume);
  }

  /// Précharge le son pour que le premier clic ne soit pas muet.
  void warmUp() => _loading ??= _load().catchError((Object e) {
        debugPrint('Clic de la molette indisponible : $e');
      });

  /// WAV mono 16 bits : souffle très bref (le contact) suivi d'une petite
  /// résonance aiguë qui s'éteint en quelques millisecondes (le boîtier).
  static Uint8List _synthesize() {
    const rate = 44100;
    const n = rate * 18 ~/ 1000; // 18 ms
    final rnd = math.Random(7);
    final samples = Int16List(n);
    var lp = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / rate;
      final noise = rnd.nextDouble() * 2 - 1;
      lp += (noise - lp) * 0.55; // adoucit un peu le souffle
      final contact = lp * math.exp(-t / 0.0006);
      final ring = math.sin(2 * math.pi * 3100 * t) * math.exp(-t / 0.0016);
      final body = math.sin(2 * math.pi * 1250 * t) * math.exp(-t / 0.0030);
      final attack = math.min(1.0, i / 6); // évite un pop au tout début
      final v = attack * (0.75 * contact + 0.45 * ring + 0.22 * body);
      samples[i] = (v.clamp(-1.0, 1.0) * 32767).round();
    }

    final data = samples.buffer.asUint8List();
    final header = ByteData(44)
      ..setUint32(0, 0x52494646) // RIFF
      ..setUint32(4, 36 + data.length, Endian.little)
      ..setUint32(8, 0x57415645) // WAVE
      ..setUint32(12, 0x666d7420) // fmt
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little) // PCM
      ..setUint16(22, 1, Endian.little) // mono
      ..setUint32(24, rate, Endian.little)
      ..setUint32(28, rate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x64617461) // data
      ..setUint32(40, data.length, Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...data]);
  }
}
