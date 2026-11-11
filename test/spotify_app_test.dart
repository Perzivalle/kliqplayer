import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/sources/spotify/official_app.dart';

/// Comment KliqPlayer lance l'appli Spotify sous Windows, selon la façon dont
/// elle est installée.
void main() {
  const appData = r'C:\Users\moi\AppData\Roaming';
  const local = r'C:\Users\moi\AppData\Local';
  const classic = '$appData\\Spotify\\Spotify.exe';
  const alias = '$local\\Microsoft\\WindowsApps\\Spotify.exe';

  List<String>? command(Set<String> files, {bool protocol = false}) => SpotifyApp.windowsCommand(
        appData: appData,
        localAppData: local,
        exists: files.contains,
        protocolRegistered: () => protocol,
      );

  test('installeur classique de spotify.com : son exécutable, réduit', () {
    expect(command({classic, alias}, protocol: true), [classic, '--minimized']);
  });

  test('version empaquetée (Microsoft Store) : par son raccourci, fenêtre réduite', () {
    expect(command({alias}, protocol: true), ['cmd', '/c', 'start', '', '/min', alias, '--minimized']);
  });

  test('ni l\'un ni l\'autre, mais le lien spotify: est enregistré : on passe par lui', () {
    expect(command({}, protocol: true), ['cmd', '/c', 'start', '', '/min', 'spotify:']);
  });

  test('Spotify n\'est pas installé : rien à lancer', () {
    expect(command({}), isNull);
  });

  test('sans variables d\'environnement : seul le lien reste', () {
    expect(
      SpotifyApp.windowsCommand(appData: null, localAppData: null, exists: (_) => true, protocolRegistered: () => true),
      ['cmd', '/c', 'start', '', '/min', 'spotify:'],
    );
  });
}
