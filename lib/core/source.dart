import 'package:flutter/foundation.dart';

import 'engine.dart';
import 'library.dart';

/// D'où vient la musique : un dossier, Spotify… Chaque source donne sa
/// bibliothèque, ses pochettes et le moteur qui la joue.
abstract class MusicSource {
  /// Identifiant stable (préférences) : « local », « spotify ».
  String get id;

  /// Nom affiché (Réglages › Bibliothèque).
  String get label;

  Future<Library> load();

  /// Pochette du morceau (son album), ou null.
  Future<Uint8List?> artwork(Track track);

  PlaybackEngine createEngine();

  /// Appelé par la source quand sa bibliothèque a changé sans qu'on le lui
  /// demande (rafraîchie en arrière-plan) : il faut la recharger.
  void Function()? onChanged;

  void dispose() {}
}

/// Rien à écouter (tests, aperçu).
class EmptySource extends MusicSource {
  @override
  String get id => 'vide';
  @override
  String get label => '';
  @override
  Future<Library> load() async => Library.empty;
  @override
  Future<Uint8List?> artwork(Track track) async => null;
  @override
  PlaybackEngine createEngine() => SilentEngine();
}

/// Le compte d'une source en ligne (Spotify, plus tard Apple Music) : se
/// connecter. Existe même quand la source en service est le dossier : c'est
/// par lui qu'on y passe. Le son sort toujours de ce PC : c'est la source
/// qui s'en occupe, il n'y a pas d'appareil à choisir.
abstract class RemoteAccount extends ChangeNotifier {
  /// Identifiant de la source qu'il ouvre (« spotify »).
  String get sourceId;

  /// Nom affiché (« Spotify »).
  String get label;

  bool get connected;

  /// Connexion en cours (le navigateur est ouvert).
  bool get connecting;

  /// Nom du compte, une fois connecté.
  String? get userName;

  /// Ouvre la page de connexion du service et attend qu'on y revienne.
  Future<void> connect();

  Future<void> disconnect();

  /// Le service demande à chacun sa propre clé d'appli, et elle n'est pas
  /// encore donnée : on ne peut pas se connecter sans elle.
  bool get needsKey => false;

  /// La clé en service, abrégée (pour la montrer), ou null.
  String? get keyHint => null;

  /// Ouvre, dans le navigateur, le guide pour créer sa clé.
  Future<void> openKeyGuide() async {}

  /// Prend la clé qu'on vient de copier (presse-papiers). Lève une
  /// [Exception] au message à montrer si ce n'en est pas une.
  Future<void> pasteKey() async {}

  /// Oublie la clé (et le compte qui allait avec).
  Future<void> forgetKey() async {}

  /// L'appli se ferme : arrêter ce qui tourne en arrière-plan.
  void shutdown() {}
}
