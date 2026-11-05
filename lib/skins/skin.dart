import 'package:flutter/widgets.dart';

import '../core/player.dart';

/// Une interface du lecteur. Chaque skin dessine l'état de [PlayerController]
/// à sa façon et appelle ses commandes ; le moteur ne change jamais.
abstract class Skin {
  const Skin();

  /// Nom affiché (menu de choix des skins).
  String get name;

  /// Taille initiale de la fenêtre (quand elle n'est pas en mosaïque).
  Size get windowSize;

  /// Remplit toute la fenêtre, quelle que soit sa taille.
  Widget build(PlayerController player);
}
