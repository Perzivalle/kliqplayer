import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/ipod/ipod.dart';

void main() {
  const classic = Size(440, 740);

  test('grand écran : la fenêtre garde sa taille', () {
    expect(fitWindowSize(classic, const Rect.fromLTWH(0, 0, 1920, 1050)), classic);
  });

  test('écran de 800 px de haut : elle rétrécit, mêmes proportions, avec du jeu', () {
    final fit = fitWindowSize(classic, const Rect.fromLTWH(0, 30, 1280, 770));
    expect(fit.height, lessThanOrEqualTo(770 - 48));
    expect(fit.width / fit.height, closeTo(classic.width / classic.height, 1e-9));
  });

  test('zone de travail inconnue : taille demandée', () {
    expect(fitWindowSize(classic, null), classic);
    expect(fitWindowSize(classic, Rect.zero), classic);
  });
}
