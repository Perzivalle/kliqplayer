import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/cover_color.dart';
import 'package:lecteur/core/library.dart';

/// Une pochette faite de [pixels] couleurs.
Uint8List _cover(List<Color> pixels) => Uint8List.fromList([
      for (final c in pixels) ...[(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), 255],
    ]);

void main() {
  const red = Color(0xFFF4001E), blue = Color(0xFF078CCE), silver = Color(0xFFDADADB), black = Color(0xFF666466);

  test('teinte vive : la part des pixels de la même nuance', () {
    final cover = _cover([const Color(0xFFD01010), const Color(0xFFFF3040), const Color(0xFF1050D0), Colors.white]);
    expect(coverShare(cover, red), 0.5);
    expect(coverShare(cover, blue), 0.25);
  });

  test('le rouge passe par 0° : 350° et 5° sont tous deux rouges', () {
    expect(coverShare(_cover([HSVColor.fromAHSV(1, 350, 0.9, 0.8).toColor(), HSVColor.fromAHSV(1, 5, 0.9, 0.8).toColor()]), red), 1);
  });

  test('argent : blancs et gris clairs ; noir : noirs et gris sombres', () {
    final cover = _cover([Colors.white, const Color(0xFFBBBBBB), const Color(0xFF111111), const Color(0xFFE02020)]);
    expect(coverShare(cover, silver), 0.5);
    expect(coverShare(cover, black), 0.25);
  });

  test('les pochettes varient : pas deux fois de suite le même album tant qu\'il en reste d\'autres', () {
    List<Track> album(String name, int n) => [for (var i = 0; i < n; i++) Track(id: '$name$i', title: '$name$i', artist: '', album: name)];
    for (var seed = 0; seed < 50; seed++) {
      final out = spreadAlbums([album('a', 5), album('b', 2), album('c', 3)], math.Random(seed));
      expect(out.map((t) => t.id).toSet().length, 10, reason: 'chaque morceau une fois');
      // Les deux premiers tours (b s'épuise après) passent par tous les albums.
      for (var i = 1; i < 6; i++) {
        expect(out[i].album, isNot(out[i - 1].album), reason: 'graine $seed, rang $i');
      }
    }
  });

  test('seuil propre à chaque teinte : ~10 % de la bibliothèque, entre 12 et 70 % de la pochette', () {
    // 100 albums : on en vise 10.
    List<double> sorted(List<double> s) => s..sort((a, b) => b.compareTo(a));
    final common = sorted([for (var i = 0; i < 100; i++) i < 50 ? 0.6 - i * 0.008 : 0.1]); // teinte partout
    expect(coverMatchCount(common), 10, reason: 'durci : seuil au 10e album');
    final white = sorted([for (var i = 0; i < 100; i++) i < 40 ? 0.95 : 0.0]); // fonds blancs : 40 à égalité
    expect(coverMatchCount(white), 40, reason: 'plafond de 70 % : les égalités restent toutes');
    final rare = sorted([0.2, 0.14, 0.13, 0.11, for (var i = 0; i < 96; i++) 0.02]);
    expect(coverMatchCount(rare), 3, reason: 'assoupli jusqu\'à 12 %, pas en dessous');
    expect(coverMatchCount(sorted([0.09, 0.06, 0.04, for (var i = 0; i < 97; i++) 0.0])), 2, reason: 'les 3 plus proches, s\'ils ont 5 %');
  });
}
