import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'library.dart';

/// Couleur au hasard (nano 4G et 5G) : chaque teinte retient à peu près
/// cette part des albums (au moins [coverMatchTarget]) : son seuil se durcit
/// quand beaucoup de pochettes ont sa couleur (argent, orange), et
/// s'assouplit quand elle est rare (violet, vert), entre [coverMatchLow] et
/// [coverMatchHigh] de la pochette.
const coverMatchPart = 0.10, coverMatchTarget = 5;
const coverMatchLow = 0.12, coverMatchHigh = 0.70;

/// Moins d'albums assortis que ça : on prend les plus proches, pourvu
/// qu'ils aient un peu de sa teinte.
const coverMatchMin = 3, coverMatchFloor = 0.05;

/// Combien des albums retenir, d'après leurs parts de la teinte [shares],
/// de la plus grande à la plus petite.
int coverMatchCount(List<double> shares) {
  if (shares.isEmpty) return 0;
  final target = math.max(coverMatchTarget, (shares.length * coverMatchPart).round());
  final threshold = shares[math.min(target, shares.length) - 1].clamp(coverMatchLow, coverMatchHigh);
  final kept = shares.where((s) => s >= threshold).length;
  return kept >= coverMatchMin ? kept : shares.take(coverMatchMin).where((s) => s >= coverMatchFloor).length;
}

/// La pochette [bytes] réduite à 16 × 16 pixels (RGBA) : assez pour juger de
/// ses couleurs, et presque rien à garder en mémoire.
Future<Uint8List?> shrinkCover(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 16, targetHeight: 16);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData();
    image.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null; // image illisible
  }
}

/// Part des pixels [rgba] de la teinte [color]. Sur une teinte vive : même
/// nuance (à 30° près), assez vive et pas trop sombre. Sur l'argent, des
/// gris clairs et des blancs ; sur le noir, des noirs et des gris sombres.
double coverShare(Uint8List rgba, Color color) {
  final target = HSVColor.fromColor(color);
  var match = 0, count = 0;
  for (var p = 0; p + 3 < rgba.length; p += 4) {
    final c = HSVColor.fromColor(Color.fromARGB(255, rgba[p], rgba[p + 1], rgba[p + 2]));
    count++;
    final gap = (c.hue - target.hue).abs() % 360;
    final ok = target.saturation < 0.25
        ? c.saturation < 0.2 && (target.value < 0.5 ? c.value < 0.3 : c.value > 0.6)
        : c.saturation > 0.3 && c.value > 0.2 && (gap > 180 ? 360 - gap : gap) < 30;
    if (ok) match++;
  }
  return count == 0 ? 0 : match / count;
}

/// Les morceaux des [albums] dans un ordre qui fait varier les pochettes,
/// plutôt qu'un vrai hasard : un morceau de chaque album à tour de rôle
/// (albums et morceaux mélangés à chaque tour), sans le même album deux fois
/// de suite tant qu'il en reste d'autres.
List<Track> spreadAlbums(List<List<Track>> albums, [math.Random? random]) {
  final r = random ?? math.Random();
  final piles = [for (final a in albums) if (a.isNotEmpty) [...a]..shuffle(r)];
  final out = <Track>[];
  List<Track>? last;
  while (piles.isNotEmpty) {
    piles.shuffle(r);
    // L'album qui a fini le tour précédent ne commence pas celui-ci.
    if (piles.length > 1 && identical(piles.first, last)) piles.add(piles.removeAt(0));
    for (final p in piles) {
      out.add(p.removeLast());
    }
    last = piles.last;
    piles.removeWhere((p) => p.isEmpty);
  }
  return out;
}
