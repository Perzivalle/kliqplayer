import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'click.dart';

/// Le grésillement dans les écouteurs quand on enfonce ou qu'on retire la
/// prise jack : la pointe frotte sur les lamelles, les contacts se font et
/// se défont (pops), et tant que la masse n'est pas bien prise, la
/// ronflette du secteur (50 Hz et ses harmoniques) passe dans le câble.
/// Synthétisé au démarrage, plusieurs variantes pour ne jamais entendre
/// deux fois exactement le même.
class JackStatic {
  JackStatic._();

  static final JackStatic instance = JackStatic._();

  static const _variants = 8;

  List<AudioSource>? _in, _out;
  Future<void>? _loading;
  final _rnd = math.Random();

  /// Volume du grésillement, de 0 à 1.
  double volume = 0.3;

  Future<void> _load() async {
    final soloud = SoLoud.instance;
    await ensureSoloud();
    // Graines tirées à chaque lancement : jamais la même série d'une fois
    // sur l'autre.
    _in = [
      for (var i = 0; i < _variants; i++)
        await soloud.loadMem('jack-in-$i.wav', _synthesize(seed: _rnd.nextInt(1 << 30), plugging: true)),
    ];
    _out = [
      for (var i = 0; i < _variants; i++)
        await soloud.loadMem('jack-out-$i.wav', _synthesize(seed: _rnd.nextInt(1 << 30), plugging: false)),
    ];
  }

  void warmUp() => _loading ??= _load().catchError((Object e) {
        debugPrint('Grésillement du jack indisponible : $e');
      });

  /// La pointe entre dans la prise femelle.
  void plugIn() => _play(_in);

  /// La prise est arrachée.
  void unplug() => _play(_out);

  void _play(List<AudioSource>? sources) {
    if (sources == null) {
      warmUp();
      return;
    }
    // Jamais tout à fait la même variante deux fois de suite, ni le même
    // volume ni la même hauteur.
    var i = _rnd.nextInt(sources.length);
    if (i == _last) i = (i + 1 + _rnd.nextInt(sources.length - 1)) % sources.length;
    _last = i;
    final soloud = SoLoud.instance;
    final h = soloud.play(sources[i], volume: volume * (0.65 + 0.45 * _rnd.nextDouble()), paused: true);
    soloud
      ..setRelativePlaySpeed(h, 0.85 + 0.3 * _rnd.nextDouble())
      ..setPause(h, false);
  }

  int _last = -1;

  @visibleForTesting
  static Uint8List sample({required bool plugging, int seed = 11}) => _synthesize(seed: seed, plugging: plugging);

  /// [plugging] : les contacts crépitent puis la masse se fait et tout se
  /// tait d'un coup (prise au fond). Sinon : un gros pop, la ronflette qui
  /// monte pendant que la pointe glisse, et un dernier claquement à la
  /// sortie.
  static Uint8List _synthesize({required int seed, required bool plugging}) {
    const rate = 44100;
    final rnd = math.Random(seed);
    // Chaque prise a son caractère : plus ou moins longue, plus ou moins
    // de ronflette, de crépitements, de contacts.
    final length = plugging ? 0.05 + 0.07 * rnd.nextDouble() : 0.07 + 0.10 * rnd.nextDouble();
    final humAmount = math.pow(rnd.nextDouble(), 1.6) * 0.16;
    final gritAmount = 0.10 + 0.14 * rnd.nextDouble();
    final sparks = 0.4 + 1.2 * rnd.nextDouble();
    final spacing = 0.6 + 0.9 * rnd.nextDouble();
    final n = (rate * length).round();
    final out = Float64List(n);

    // Les contacts : une suite de fermetures/ouvertures de plus en plus
    // espacées (plugging) ou serrées (unplug), de 2 à 25 ms.
    final edges = <int>[];
    var t = plugging ? 0.0 : 0.004;
    final end = length * (plugging ? 0.78 : 0.85);
    while (t < end) {
      edges.add((t * rate).round());
      final progress = t / end;
      final span = plugging ? 0.003 + 0.022 * progress : 0.022 - 0.016 * progress;
      t += span * spacing * (0.3 + rnd.nextDouble() * 1.6);
    }
    // Branchée : le dernier contact reste établi un instant (la ronflette
    // meurt quand la masse se fait). Débranchée : tout s'ouvre à la fin.
    if (plugging && edges.length.isOdd) edges.add((end * rate).round());

    bool contactAt(int i) {
      var on = false;
      for (final e in edges) {
        if (e > i) break;
        on = !on;
      }
      return on;
    }

    // Ronflette : 50 Hz riche en harmoniques impaires (transfo du secteur),
    // un peu de 100 Hz, légèrement saturée.
    double hum(double s) {
      var v = 0.0;
      for (var k = 1; k <= 15; k++) {
        final a = (k.isOdd ? 1.0 : 0.45) / k;
        v += a * math.sin(2 * math.pi * 50 * k * s + k * 0.7);
      }
      return v;
    }

    var lp = 0.0;
    var hp = 0.0;
    var gate = 0.0;
    for (var i = 0; i < n; i++) {
      final s = i / rate;
      final on = contactAt(i);
      // Le contact ne s'établit pas net : petite rampe de 1 ms.
      gate += ((on ? 1.0 : 0.0) - gate) * 0.02;
      // Branchée, la ronflette s'efface en se calant au fond.
      final fade = plugging ? math.max(0.0, 1 - s / end) : math.min(1.0, 0.35 + s / end);
      final noise = rnd.nextDouble() * 2 - 1;
      lp += (noise - lp) * 0.35;
      // Grésillement : souffle granuleux tant que la pointe frotte.
      final grit = lp * (0.25 + 0.75 * math.pow(rnd.nextDouble(), 6)) * gate;
      out[i] += gate * fade * humAmount * hum(s) + gritAmount * grit;
      // Crépitements isolés : de minuscules étincelles.
      if (rnd.nextDouble() < (plugging ? 0.0018 : 0.0012) * sparks * (0.3 + gate)) {
        _impulse(out, i, (rnd.nextBool() ? 1 : -1) * (0.15 + 0.35 * rnd.nextDouble()), 0.00025, rate);
      }
    }

    // Les pops : un claquement à chaque fermeture/ouverture, le premier et
    // le dernier plus gros, avec un « boum » grave (la membrane qui saute).
    for (var j = 0; j < edges.length; j++) {
      final big = j == 0 || j == edges.length - 1;
      final amp = (big ? 0.45 + 0.3 * rnd.nextDouble() : 0.12 + 0.3 * rnd.nextDouble()) * (rnd.nextBool() ? 1 : -1);
      _impulse(out, edges[j], amp, big ? 0.0012 : 0.0005, rate);
      if (big) _thump(out, edges[j], amp * 0.8, rate);
    }

    final samples = Int16List(n);
    for (var i = 0; i < n; i++) {
      // Coupe le continu (les « boum » ne doivent pas laisser de décalage),
      // puis saturation douce.
      final x = out[i];
      hp += (x - hp) * 0.004;
      var v = _tanh((x - hp) * 1.2) * 0.9;
      // Pas de clic numérique aux bouts.
      v *= math.min(1.0, i / 30) * math.min(1.0, (n - 1 - i) / 200);
      samples[i] = (v * 32767).round();
    }
    return wav(samples, rate);
  }

  /// Claquement sec : bruit qui s'éteint en [tau] secondes.
  static void _impulse(Float64List out, int at, double amp, double tau, int rate) {
    final rnd = math.Random(at);
    final len = math.min(out.length - at, (tau * 8 * rate).round());
    for (var i = 0; i < len; i++) {
      final e = math.exp(-i / (tau * rate));
      out[at + i] += amp * e * (i == 0 ? 1 : rnd.nextDouble() * 2 - 1);
    }
  }

  /// Boum grave : la membrane de l'écouteur poussée d'un coup.
  static void _thump(Float64List out, int at, double amp, int rate) {
    final len = math.min(out.length - at, (0.04 * rate).round());
    for (var i = 0; i < len; i++) {
      final s = i / rate;
      out[at + i] += amp * math.sin(2 * math.pi * 65 * s) * math.exp(-s / 0.012);
    }
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x.clamp(-10.0, 10.0));
    return (e - 1) / (e + 1);
  }
}
