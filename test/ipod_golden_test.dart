// Captures de référence du baladeur. Elles verrouillent l'apparence
// du Classic : toute modification qui change un seul pixel fait échouer le
// test. Pour accepter volontairement un changement :
//   flutter test --update-goldens test/ipod_golden_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/ipod/classic.dart';
import 'package:lecteur/ipod/drawer.dart';
import 'package:lecteur/ipod/ipod.dart';
import 'package:lecteur/ipod/mini.dart';
import 'package:lecteur/ipod/model.dart';
import 'package:lecteur/ipod/nano.dart';
import 'package:lecteur/ipod/nanos.dart';
import 'package:lecteur/ipod/shuffle.dart';
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
      tracks.add(Track(id: '/x/$s.flac', title: s, artist: artist, album: title));
    }
  }
  return PlayerController.preview(
    tracks: tracks,
    albums: list,
    index: index,
    playing: playing,
    duration: const Duration(minutes: 4, seconds: 12),
    position: position,
  );
}

Future<void> _show(WidgetTester tester, Widget stage, {Size size = const Size(460, 760)}) async {
  tester.view
    ..physicalSize = size
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

/// Neuf albums avec de fausses pochettes (aplats de couleur dégradés).
Future<PlayerController> _coverPlayer(WidgetTester tester) async {
  const hues = [8.0, 32.0, 52.0, 140.0, 190.0, 215.0, 260.0, 300.0, 340.0];
  final tracks = <Track>[];
  final albums = <Album>[];
  final covers = <int, Uint8List?>{};
  for (var i = 0; i < hues.length; i++) {
    final title = 'Album ${String.fromCharCode(65 + i)}';
    // L'album du milieu (E) a plusieurs morceaux, pour le dos de sa pochette.
    final n = i == 4 ? 8 : 1;
    albums.add(Album(title: title, artist: 'Artiste ${i + 1}', firstIndex: tracks.length, trackCount: n));
    for (var k = 0; k < n; k++) {
      tracks.add(Track(
        id: '/x/$i-$k.flac',
        title: n == 1 ? 'Titre $i' : 'Morceau ${k + 1} de l\'album',
        artist: 'Artiste ${i + 1}',
        album: title,
        duration: Duration(seconds: 150 + 37 * k),
      ));
    }
    covers[i] = await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final a = HSVColor.fromAHSV(1, hues[i], 0.65, 0.95).toColor();
      final b = HSVColor.fromAHSV(1, (hues[i] + 40) % 360, 0.8, 0.45).toColor();
      c.drawRect(
        const Rect.fromLTWH(0, 0, 96, 96),
        Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(96, 96), [a, b]),
      );
      c.drawCircle(const Offset(48, 48), 22, Paint()..color = const Color(0x55FFFFFF));
      final img = await rec.endRecording().toImage(96, 96);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
  }
  return PlayerController.preview(tracks: tracks, albums: albums, index: 4, albumCovers: covers);
}

/// Laisse les images se décoder (en vrai temps), puis les affiche.
Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await _frames(tester, 10);
  }
}

void main() {
  setUpAll(() async {
    await _loadFont('Noto Sans', [
      'assets/fonts/NotoSans-Regular.ttf',
      'assets/fonts/NotoSans-Medium.ttf',
      'assets/fonts/NotoSans-Bold.ttf',
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
      await _key(tester, LogicalKeyboardKey.arrowDown, 4);
      await _key(tester, LogicalKeyboardKey.enter); // Morceaux
      await _key(tester, LogicalKeyboardKey.arrowDown, 9);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_songs.png'));
    });

    testWidgets('en lecture', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 5, playing: false, position: const Duration(minutes: 1, seconds: 23)), initial: model));
      await _key(tester, LogicalKeyboardKey.arrowDown, 3);
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
      await _key(tester, LogicalKeyboardKey.arrowDown, 3);
      await _key(tester, LogicalKeyboardKey.enter); // Morceaux
      await _key(tester, LogicalKeyboardKey.arrowDown, 9);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/mini_songs.png'));
    });

    testWidgets('en lecture', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 5, position: const Duration(minutes: 1, seconds: 23)), initial: model));
      await _key(tester, LogicalKeyboardKey.arrowDown, 3);
      await _key(tester, LogicalKeyboardKey.enter); // En lecture
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/mini_now_playing.png'));
      await _key(tester, LogicalKeyboardKey.arrowDown); // volume
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/mini_volume.png'));
    });
  });

  group('Réglages, Cover Flow, rétroéclairage', () {
    testWidgets('Réglages (Classic)', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: const ClassicModel()));
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.enter); // Réglages
      await _key(tester, LogicalKeyboardKey.arrowDown, 3);
      await _key(tester, LogicalKeyboardKey.enter); // Répéter : Non → Un
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_settings.png'));
    });

    testWidgets('Réglages (Mini)', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: const MiniModel()));
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.enter); // Réglages
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/mini_settings.png'));
    });

    testWidgets('Cover Flow (Classic)', (tester) async {
      final player = await _coverPlayer(tester);
      await _show(tester, IpodStage(player: player, initial: const ClassicModel()));
      await _key(tester, LogicalKeyboardKey.enter); // Musique
      await _key(tester, LogicalKeyboardKey.enter); // Cover Flow
      await _decode(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_coverflow.png'));
      await _key(tester, LogicalKeyboardKey.arrowDown, 2);
      await _frames(tester, 3); // en plein glissement
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_coverflow_moving.png'));
    });

    testWidgets('Cover Flow retourné (Classic)', (tester) async {
      final player = await _coverPlayer(tester);
      await _show(tester, IpodStage(player: player, initial: const ClassicModel()));
      await _key(tester, LogicalKeyboardKey.enter); // Musique
      await _key(tester, LogicalKeyboardKey.enter); // Cover Flow
      await _decode(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter); // retourne
      await _frames(tester, 9); // en plein demi-tour
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_coverflow_flipping.png'));
      await _frames(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown, 2);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_coverflow_flipped.png'));
    });

    testWidgets('Cover Flow retourné (nano 4G)', (tester) async {
      final player = await _coverPlayer(tester);
      await _show(tester, IpodStage(player: player, initial: Nano4Model(nano4Colors[3])));
      await _key(tester, LogicalKeyboardKey.enter); // Musique
      await _key(tester, LogicalKeyboardKey.enter); // Cover Flow
      await _decode(tester);
      await _key(tester, LogicalKeyboardKey.enter); // retourne
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/nano4_coverflow_flipped.png'));
    });

    testWidgets('Cover Flow (nano 4G, écran vertical)', (tester) async {
      final player = await _coverPlayer(tester);
      await _show(tester, IpodStage(player: player, initial: Nano4Model(nano4Colors[3])));
      await _key(tester, LogicalKeyboardKey.enter); // Musique
      await _key(tester, LogicalKeyboardKey.enter); // Cover Flow
      await _decode(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/nano4_coverflow.png'));
    });

    testWidgets('écran éteint après 10 s', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: const ClassicModel()));
      await tester.pump(const Duration(seconds: 11));
      await _frames(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_backlight_off.png'));
      await _key(tester, LogicalKeyboardKey.arrowDown); // il se rallume
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/classic_backlight_on.png'));
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

    testWidgets('ouvert à gauche (nano 4G en main)', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: Nano4Model(nano4Colors[4])));
      final d = tester.getRect(find.byType(IpodDevice));
      await tester.tapAt(Offset(d.left - 6, d.top + 30));
      await _frames(tester, 120);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/drawer_open_left.png'));
    });

    testWidgets('ouvert à gauche après avoir été ouvert à droite : façade à gauche', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: Nano4Model(nano4Colors[4])));
      final d = tester.getRect(find.byType(IpodDevice));
      await tester.tapAt(Offset(d.right + 6, d.top + 30));
      await _frames(tester, 120);
      await _key(tester, LogicalKeyboardKey.escape);
      await _frames(tester, 120);
      await tester.tapAt(Offset(d.left - 6, d.top + 30));
      await _frames(tester, 120);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/drawer_open_left_after_right.png'));
    });

    testWidgets('poignée survolée', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: const MiniModel(MiniColor.bleu)));
      final d = tester.getRect(find.byType(IpodDevice));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(Offset(d.right + 6, d.top + 50));
      await _frames(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/drawer_handle_hover.png'));
    });

    // Survol : l'éventail des teintes du nano 4G s'ouvre, la carte survolée
    // monte.
    testWidgets('survol d\'une pastille', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: const ClassicModel()));
      await _key(tester, LogicalKeyboardKey.keyT);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      final nano4 = find.byWidgetPredicate((w) => w is IpodPreview && w.model.family == 'nano4');
      await tester.ensureVisible(nano4); // le tiroir défile jusqu'à lui
      await _frames(tester);
      await mouse.moveTo(tester.getCenter(nano4));
      await tester.pumpAndSettle();
      final violet = _swatch('Violet').last;
      await mouse.moveTo(tester.renderObject<RenderBox>(violet).localToGlobal(const Offset(8, 10)));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/drawer_swatch_preview.png'));
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
    });

    // Fenêtre basse : les emplacements s'étalent sur plus de colonnes au
    // lieu de rapetisser.
    testWidgets('fenêtre large et basse', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: const ClassicModel()), size: const Size(1100, 420));
      await _key(tester, LogicalKeyboardKey.keyT);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/drawer_low_window.png'));
      await _key(tester, LogicalKeyboardKey.escape);
    });

    // Fenêtre minuscule : les appareils gardent une taille où on les vise,
    // et les emplacements défilent.
    testWidgets('fenêtre minuscule', (tester) async {
      await _show(tester, IpodStage(player: _player(index: 0), initial: const ClassicModel()), size: const Size(520, 300));
      await _key(tester, LogicalKeyboardKey.keyT);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/drawer_tiny_window.png'));
      await _key(tester, LogicalKeyboardKey.escape);
    });
  });

  group('Autres modèles', () {
    final models = <String, IpodModel>{
      'classic_noir': const ClassicModel(ClassicColor.noir),
      for (final c in NanoColor.values) 'nano_${c.name}': NanoModel(c),
      'gen3': const ThirdGenModel(),
      'gen1': const FirstGenModel(),
      for (final c in FourthGenColor.values) c == FourthGenColor.blanc ? 'gen4' : 'gen4_${c.name}': FourthGenModel(c),
      for (final c in nano2Colors) 'nano2_${c.name}': Nano2Model(c),
      for (final c in nano4Colors) 'nano4_${c.name}': Nano4Model(c),
      'gen2': const SecondGenModel(),
      'photo': const PhotoModel(),
      'gen5': const VideoModel(),
      'gen5_noir': const VideoModel(ClassicColor.noir),
      for (final c in Nano1Color.values) c == Nano1Color.blanc ? 'nano1' : 'nano1_${c.name}': Nano1Model(c),
      'shuffle1': const Shuffle1Model(),
      for (final c in shuffle2Colors) 'shuffle2_${c.name}': Shuffle2Model(c),
      for (final c in shuffle4Colors) 'shuffle4_${c.name}': Shuffle4Model(c),
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
      'gen4': const FourthGenModel(),
      'nano2': Nano2Model(nano2Colors.first),
      'nano4': Nano4Model(nano4Colors.first),
      'photo': const PhotoModel(),
      'gen5': const VideoModel(ClassicColor.noir),
      'nano1': const Nano1Model(),
    }.entries) {
      testWidgets('en lecture ($name)', (tester) async {
        await _show(
          tester,
          IpodStage(player: _player(index: 5, position: const Duration(minutes: 1, seconds: 23)), initial: model),
        );
        await _key(tester, LogicalKeyboardKey.arrowDown, 3);
        await _key(tester, LogicalKeyboardKey.enter);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_now_playing.png'));
      });
    }
  });
}

/// Une pastille de l'éventail, par le nom de sa teinte.
Finder _swatch(String name) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == name);
