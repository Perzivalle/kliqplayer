import 'package:flutter/widgets.dart';

import '../core/player.dart';

/// Une interface du lecteur. Chaque skin dessine l'état de [PlayerController]
/// à sa façon et appelle ses commandes ; le moteur ne change jamais.
abstract class Skin {
  const Skin();

  /// Nom affiché (menu de choix des skins).
  String get name;

  /// Taille de la fenêtre pour cette skin, en pixels logiques.
  Size get windowSize;

  /// [onWindowDrag] : à appeler quand l'utilisateur attrape une zone « vide »
  /// de la skin, pour déplacer la fenêtre.
  Widget build(PlayerController player, VoidCallback onWindowDrag);
}
