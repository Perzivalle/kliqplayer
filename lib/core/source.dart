
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

  /// L'appli se ferme : arrêter ce qui tourne en arrière-plan.
  void shutdown() {}
}
