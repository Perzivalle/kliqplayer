// Captures de référence du baladeur. Elles verrouillent l'apparence
// du Classic : toute modification qui change un seul pixel fait échouer le
// test. Pour accepter volontairement un changement :
//   flutter test --update-goldens test/ipod_golden_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/ipod.dart';
import 'package:lecteur/ipod/mini.dart';
import 'package:lecteur/ipod/model.dart';
import 'package:lecteur/ipod/nano.dart';
import 'package:lecteur/ipod/vintage.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(File(f).readAsBytes().then((b) => ByteData.sublistView(b)));
  }
  await loader.load();
}

/// Petite bibliothèque fictive : 3 albums, dont des titres trop longs.
PlayerController _player({int index = -1, bool playing = false, Duration position = Duration.zero}) {
  const albums = [
    ('Les Saisons qui passent et ne reviennent jamais tout à fait', 'Ana Lune', ['Printemps', 'Été indien', 'Automne', 'Hiver']),
    ('Bleu nuit', 'Les Fréquences', ['Ouverture', 'Un titre beaucoup trop long pour tenir sur une ligne', 'Néons', 'Retour']),
    ('Zéro', 'Marc Ohm', ['Silence', 'Bruit blanc', 'Fin']),
  ];
  final tracks = <Track>[];
  final list = <Album>[];
  for (final (title, artist, songs) in albums) {
    list.add(Album(title: title, artist: artist, firstIndex: tracks.length, trackCount: songs.length));
    for (final s in songs) {
      tracks.add(Track(path: '/x/$s.flac', title: s, artist: artist, album: title));
    }
  }
  return PlayerController.preview(
    queue: tracks,
    albums: list,
    index: index,
    playing: playing,
    duration: const Duration(minutes: 4, seconds: 12),
    position: position,
  );
}

Future<void> _show(WidgetTester tester, Widget stage) async {
  tester.view
    ..physicalSize = const Size(460, 760)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: ColoredBox(
        color: const Color(0xFF203040),
        // Comme dans l'appli (main.dart) : fond Material transparent.
        child: Material(type: MaterialType.transparency, child: stage),
      ),
    ),
  );
  await _frames(tester);
}

/// Avance le temps de façon déterministe (les animations ne s'arrêtent
/// jamais complètement à cause des textes défilants).
Future<void> _frames(WidgetTester tester, [int n = 60]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await _frames(tester);
}

void main() {
  setUpAll(() async {
    await _loadFont('Noto Sans', [
      '/usr/share/fonts/noto/NotoSans-Regular.ttf',
      '/usr/share/fonts/noto/NotoSans-Medium.ttf',
      '/usr/share/fonts/noto/NotoSans-Bold.ttf',
    ]);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/development/flutter';
    await _loadFont('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  group('Classic', () {
    const model = ClassicModel();

    testWidgets('menu principal', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: model));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_menu.png'));
    });

    testWidgets('liste longue, titre défilant', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: model));
      await _key(tester, LogicalKeyboardKey.enter); // Musique
      await _key(tester, LogicalKeyboardKey.arrowDown, 2);
      await _key(tester, LogicalKeyboardKey.enter); // Morceaux
      await _key(tester, LogicalKeyboardKey.arrowDown, 9);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_songs.png'));
    });

    testWidgets('en lecture', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 5, playing: false, position: const Duration(minutes: 1, seconds: 23)), initial: model));
      await _key(tester, LogicalKeyboardKey.arrowDown, 2);
      await _key(tester, LogicalKeyboardKey.enter); // En lecture
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_now_playing.png'));
      await _key(tester, LogicalKeyboardKey.arrowDown); // volume
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_volume.png'));
      await _key(tester, LogicalKeyboardKey.enter); // avance rapide
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_scrub.png'));
    });

    testWidgets('bouton enfoncé', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: model));
      final wheel = tester.getCenter(find.byType(IpodWheel));
      final scale = tester.getSize(find.byType(IpodWheel)).width / 264;
      final g = await tester.startGesture(wheel + Offset(100 * scale, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_pressed.png'));
      await g.cancel();
      await _frames(tester);
    });
  });

  group('Mini', () {
    for (final color in MiniColor.values) {
      testWidgets('menu principal (${color.name})', (tester) async {
        await _show(tester, IpodStage(player: _player(index: 0), initial: MiniModel(color)));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/mini_${color.name}_menu.png'));
      });
    }

    const model = MiniModel();

    testWidgets('liste longue, titre défilant', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: model));
      await _key(tester, LogicalKeyboardKey.enter); // Musique
      await _key(tester, LogicalKeyboardKey.arrowDown, 2);
      await _key(tester, LogicalKeyboardKey.enter); // Morceaux
      await _key(tester, LogicalKeyboardKey.arrowDown, 9);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/mini_songs.png'));
    });

    testWidgets('en lecture', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 5, position: const Duration(minutes: 1, seconds: 23)), initial: model));
      await _key(tester, LogicalKeyboardKey.arrowDown, 2);
      await _key(tester, LogicalKeyboardKey.enter); // En lecture
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/mini_now_playing.png'));
      await _key(tester, LogicalKeyboardKey.arrowDown); // volume
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/mini_volume.png'));
    });
  });

  group('Tiroir', () {
    testWidgets('ouvert (touche T), Mini rose en main', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: const MiniModel(MiniColor.rose)));
      await _key(tester, LogicalKeyboardKey.keyT);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/drawer_open.png'));
      await _key(tester, LogicalKeyboardKey.escape);
    });

    testWidgets('ouvert, Classic en main : le Mini et ses teintes', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: const ClassicModel()));
      await _key(tester, LogicalKeyboardKey.keyT);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/drawer_open_classic.png'));
      await _key(tester, LogicalKeyboardKey.escape);
    });
  });

  group('Autres modèles', () {
    final models = <String, IpodModel>{
      'classic_noir': const ClassicModel(ClassicColor.noir),
      for (final c in NanoColor.values) 'nano_${c.name}': NanoModel(c),
      'gen3': const ThirdGenModel(),
      'gen1': const FirstGenModel(),
    };
    for (final MapEntry(key: name, value: model) in models.entries) {
      testWidgets('menu ($name)', (tester) async {
        await _show(tester, IpodStage(player: _player(index: 0), initial: model));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_menu.png'));
      });
    }
    for (final MapEntry(key: name, value: model) in {
      'nano': const NanoModel(),
      'gen3': const ThirdGenModel(),
    }.entries) {
      testWidgets('en lecture ($name)', (tester) async {
        await _show(
          tester,
          IpodStage(player: _player(index: 5, position: const Duration(minutes: 1, seconds: 23)), initial: model),
        );
        await _key(tester, LogicalKeyboardKey.arrowDown, 2);
        await _key(tester, LogicalKeyboardKey.enter);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_now_playing.png'));
      });
    }
  });
}
