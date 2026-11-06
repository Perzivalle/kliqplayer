import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/paths.dart';

void main() {
  test('dernier élément, avec / comme avec \\', () {
    expect(lastSegment('/home/paul/Musique'), 'Musique');
    expect(lastSegment('/home/paul/Musique/'), 'Musique');
    expect(lastSegment(r'C:\Users\Paul\Music'), 'Music');
    expect(lastSegment(r'C:\'), 'C:');
    expect(lastSegment('/'), '/');
  });

  test('chemins absolus selon le système', () {
    expect(isAbsolutePath('/musique', windows: false), isTrue);
    expect(isAbsolutePath('album/a.mp3', windows: false), isFalse);
    expect(isAbsolutePath(r'C:\Musique\a.mp3', windows: true), isTrue);
    expect(isAbsolutePath('D:/Musique/a.mp3', windows: true), isTrue);
    expect(isAbsolutePath(r'\\serveur\partage\a.mp3', windows: true), isTrue);
    expect(isAbsolutePath(r'album\a.mp3', windows: true), isFalse);
  });

  test('joindre et normaliser (listes .m3u qui mélangent / et \\)', () {
    expect(joinPath('/home/paul', 'Music', windows: false), '/home/paul/Music');
    expect(joinPath('/', 'mnt', windows: false), '/mnt');
    expect(joinPath(r'C:\Users\Paul', 'Music/Musique Ipod', windows: true), r'C:\Users\Paul\Music\Musique Ipod');
    expect(joinPath(r'C:\', 'Musique', windows: true), r'C:\Musique');
    expect(normalizePath('C:/Musique/a.mp3', windows: true), r'C:\Musique\a.mp3');
    expect(normalizePath('/musique/a.mp3', windows: false), '/musique/a.mp3');
  });
}
