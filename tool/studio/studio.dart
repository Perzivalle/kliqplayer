// Outils communs du studio (images du site rendues par le code de l'appli).
// (Hors de test/, l'analyseur ne sait pas que c'est un outil de test.)
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecteur/core/library.dart';
import 'package:lecteur/core/player.dart';
import 'package:lecteur/core/strings.dart';
import 'package:lecteur/ipod/ipod.dart';
import 'package:lecteur/ipod/model.dart';

/// Résolution des images (× la taille à l'écran dans l'appli).
const studioScale = 4.0;

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(File(f).readAsBytes().then((b) => ByteData.sublistView(b)));
  }
  await loader.load();
}

/// Polices de l'appli, interface en anglais (le site est en anglais).
void setUpStudio(String outDir) {
  setUpAll(() async {
    await _loadFont('Noto Sans', [
      'assets/fonts/NotoSans-Regular.ttf',
      'assets/fonts/NotoSans-Medium.ttf',
      'assets/fonts/NotoSans-Bold.ttf',
    ]);
    await _loadFont('ChicagoFLF', ['assets/fonts/ChicagoFLF.ttf']);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/development/flutter';
    await _loadFont('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    Lang.current = Lang.en;
    Directory(outDir).createSync(recursive: true);
  });
}

Future<void> frames(WidgetTester tester, [int n = 60]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey k, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(k);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await frames(tester);
}

/// Laisse les pochettes se décoder (en vrai temps), puis les affiche.
Future<void> decode(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await frames(tester, 20);
  }
  await frames(tester);
}

/// Un lecteur qui joue [title] depuis 62 % du morceau, avec sa pochette.
PlayerController playing(String title, String artist, String album, Duration length, Uint8List cover) =>
    PlayerController.preview(
      tracks: [Track(id: '/x/$title.mp3', title: title, artist: artist, album: album, duration: length)],
      albums: [Album(title: album, artist: artist, firstIndex: 0, trackCount: 1)],
      index: 0,
      playing: true,
      duration: length,
      position: length * 0.62,
      albumCovers: {0: cover},
    )..cover = cover; // l'aperçu ne lit pas de pochette pour « En lecture »

final _boundary = GlobalKey();

/// Le baladeur seul sur fond transparent, dans une fenêtre de [size]
/// (par défaut celle du modèle).
Future<void> showStage(WidgetTester tester, PlayerController player, IpodModel model, {Size? size}) async {
  tester.view
    ..physicalSize = size ?? model.windowSize
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    color: Colors.transparent,
    home: RepaintBoundary(
      key: _boundary,
      child: Material(type: MaterialType.transparency, child: IpodStage(player: player, initial: model)),
    ),
  ));
  await frames(tester, 90);
}

/// Écrit l'image en PNG : la zone [crop] (coordonnées d'écran), ou tout ce
/// qui n'est pas transparent.
Future<void> capture(WidgetTester tester, String path, {Rect? crop, double scale = studioScale}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  final bytes = await tester.runAsync(() async {
    final full = await boundary.toImage(pixelRatio: scale);
    final src = crop != null
        ? Rect.fromLTRB(crop.left * scale, crop.top * scale, crop.right * scale, crop.bottom * scale)
        : await _opaqueBounds(full);
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(full, src, Offset.zero & src.size, Paint());
    final image = await rec.endRecording().toImage(src.width.round(), src.height.round());
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  File(path).writeAsBytesSync(bytes!);
}

/// Une image d'une vidéo : toute la fenêtre à l'échelle [scale], avec une
/// flèche de souris dessinée en [cursor] (plus petite quand on appuie).
Future<void> captureFrame(WidgetTester tester, String path, {Offset? cursor, bool pressed = false, double scale = 2}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  final bytes = await tester.runAsync(() async {
    final full = await boundary.toImage(pixelRatio: scale);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..drawImage(full, Offset.zero, Paint());
    if (cursor != null) {
      // La flèche classique, pointe sur [cursor], 19 px de haut à l'échelle de l'appli.
      final arrow = Path()
        ..moveTo(0, 0)
        ..lineTo(0, 16)
        ..lineTo(4, 12.4)
        ..lineTo(6.8, 18.6)
        ..lineTo(9.6, 17.4)
        ..lineTo(6.9, 11.3)
        ..lineTo(11.6, 11.3)
        ..close();
      canvas
        ..save()
        ..translate(cursor.dx * scale, cursor.dy * scale)
        ..scale(scale * (pressed ? 0.88 : 1))
        ..drawPath(arrow.shift(const Offset(0.6, 1.2)), Paint()..color = const Color(0x40000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1))
        ..drawPath(arrow, Paint()..color = const Color(0xFF000000))
        ..drawPath(arrow, Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.stroke..strokeWidth = 1.2..strokeJoin = StrokeJoin.round)
        ..restore();
    }
    final image = await rec.endRecording().toImage(full.width, full.height);
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  File(path).writeAsBytesSync(bytes!);
}

/// Le plus petit rectangle qui contient tout ce qui n'est pas transparent.
Future<Rect> _opaqueBounds(ui.Image image) async {
  final px = (await image.toByteData())!.buffer.asUint8List();
  var (l, t, r, b) = (image.width, image.height, -1, -1);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (px[(y * image.width + x) * 4 + 3] == 0) continue;
      if (x < l) l = x;
      if (x > r) r = x;
      if (y < t) t = y;
      if (y > b) b = y;
    }
  }
  assert(r >= l && b >= t, 'image entièrement transparente');
  return Rect.fromLTRB(l.toDouble(), t.toDouble(), r + 1.0, b + 1.0);
}
