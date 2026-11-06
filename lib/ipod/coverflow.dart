import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/library.dart';
import '../core/player.dart';
import 'nav.dart';
import '../core/strings.dart';

/// Cover Flow : les pochettes en enfilade sur fond noir, celle du milieu de
/// face, les autres pivotées de chaque côté, chacune avec son reflet. Le
/// titre et l'artiste de l'album du milieu sont écrits dessous.
class CoverFlowView extends StatelessWidget {
  const CoverFlowView({super.key, required this.page, required this.player});

  final CoverFlowPage page;
  final PlayerController player;

  /// Angle des pochettes de côté.
  static const double _tilt = 40 * math.pi / 180;

  /// Hauteur du reflet, en fraction de la pochette.
  static const double _reflection = 0.34;

  @override
  Widget build(BuildContext context) {
    final albums = player.albums;
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        if (albums.isEmpty) {
          return Center(child: Text(tr('Aucun album'), style: TextStyle(color: Colors.white70)));
        }
        // Pochette du milieu : la plus grande qui laisse la place au reflet
        // et aux deux lignes de texte.
        final s = math.min(h * 0.5, w * 0.44);
        // Centrées dans la place laissée au-dessus des deux lignes de texte.
        final cy = math.max(6.0, (h - 44 - s * (1 + _reflection)) / 2) + s / 2;
        final pos = page.pos.value;

        // Les plus éloignées d'abord : celle du milieu passe par-dessus.
        // Seulement celles qui se voient : la première de côté est à 0,95 s
        // du milieu, les suivantes tous les 0,3 s.
        final reach = (1 + (w / 2 + s / 2 - 0.95 * s) / (0.3 * s)).ceil().clamp(1, 9) + 1;
        final first = math.max(0, (pos - reach).floor());
        final last = math.min(albums.length - 1, (pos + reach).ceil());
        final order = [for (var i = first; i <= last; i++) i]
          ..sort((a, b) => (b - pos).abs().compareTo((a - pos).abs()));

        final selected = page.selected.clamp(0, albums.length - 1);
        final album = albums[selected];
        // Retournement de l'album du milieu (0 de face, 1 de dos).
        final f = page.flip.value.clamp(0.0, 1.0);
        final flipping = f > 0.001;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final i in order)
              if (!flipping || i != selected) _cover(i, i - pos, s, w / 2, cy),
            if (flipping) ...[
              // Les autres s'assombrissent derrière la pochette retournée.
              Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.6 * f))),
              _flipCard(selected, f, s, w, h, cy),
            ],
            if (f < 0.999) Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Opacity(
                opacity: 1 - f,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFA9AEB4), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  /// Pochette [i], à [d] albums du milieu (négatif : à gauche).
  Widget _cover(int i, double d, double s, double cx, double cy) {
    // Entre le milieu et la première place de côté, tout est interpolé :
    // position, angle, recul. Au-delà, elles s'empilent serrées.
    final t = d.clamp(-1.0, 1.0);
    // La première de chaque côté s'écarte de celle du milieu ; les suivantes
    // s'empilent en se chevauchant.
    final x = cx + t * s * 0.95 + (d - t) * s * 0.3;
    // Tournées vers le milieu : le bord extérieur est le plus proche.
    final angle = t * _tilt;
    // Celle du milieu avance un peu vers nous ; les autres reculent.
    final depth = t.abs() * s * 0.55 - (1 - t.abs()) * s * 0.2;

    final transform = Matrix4.identity()
      ..setEntry(3, 2, 1 / (s * 2.6))
      ..translateByDouble(0, 0, depth, 1)
      ..rotateY(angle);

    final bytes = player.albumCover(i);
    final face = _Face(bytes: bytes, size: s);
    return Positioned(
      left: x - s / 2,
      top: cy - s / 2,
      width: s,
      height: s * (1 + _reflection),
      child: Transform(
        // Pivote autour du centre de la pochette.
        alignment: const Alignment(0, -_reflection / (1 + _reflection)),
        transform: transform,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            face,
            _reflected(face, s),
          ],
        ),
      ),
    );
  }

  /// Reflet sur le sol noir, qui s'efface vers le bas : l'image retournée
  /// sous un voile noir dégradé. Le voile déborde d'un pixel sur les côtés
  /// et en bas, pour que le bord lissé de l'image ne filtre pas en liseré.
  /// (Pas de fondu en transparence : il faudrait une couche à part par
  /// pochette, trop lourd à chaque image.)
  static Widget _reflected(Widget face, double s) => SizedBox(
        width: s,
        height: s * _reflection,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: s,
                  maxHeight: s,
                  child: Transform.flip(flipY: true, child: face),
                ),
              ),
            ),
            const Positioned(
              left: -1,
              right: -1,
              top: 0,
              bottom: -1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB0000000), Colors.black],
                    stops: [0, 0.85],
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  /// L'album du milieu qui se retourne : il pivote d'un demi-tour en
  /// grandissant jusqu'au carré [big] au milieu de l'écran ; passé le
  /// quart de tour, on voit son dos (la liste des morceaux).
  Widget _flipCard(int i, double f, double s, double w, double h, double cy) {
    final big = math.min(w * 0.9, h - 12);
    final k = s / big + (1 - s / big) * f; // échelle : de s à big
    final y = cy + (h / 2 - cy) * f;
    // Au départ, exactement la pochette du milieu (un peu avancée) ; à
    // mi-course elle recule un peu pour ne pas nous foncer dessus.
    final depth = -(1 - f) * s * 0.2 + math.sin(math.pi * f) * s * 0.6;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 1 / (s * 2.6))
      ..translateByDouble(0, 0, depth, 1)
      ..rotateY(math.pi * f)
      ..scaleByDouble(k, k, 1, 1);

    final back = f > 0.5;
    final face = _Face(bytes: player.albumCover(i), size: big);
    return Positioned(
      left: w / 2 - big / 2,
      top: y - big / 2,
      width: big,
      height: big * (1 + _reflection),
      child: Transform(
        alignment: const Alignment(0, -_reflection / (1 + _reflection)),
        transform: transform,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (back)
              // Retournée : on redresse le dos, vu en miroir.
              Transform.flip(flipX: true, child: _Back(album: i, page: page, player: player, size: big))
            else
              face,
            // Le reflet s'efface dès que la pochette décolle.
            if (!back && f < 0.25)
              Opacity(opacity: 1 - f * 4, child: _reflected(face, big))
            else
              SizedBox(height: big * _reflection),
          ],
        ),
      ),
    );
  }
}

/// Le dos d'une pochette : titre et artiste, puis les morceaux de l'album,
/// celui sélectionné surligné, celui en cours marqué d'un haut-parleur.
class _Back extends StatelessWidget {
  const _Back({required this.album, required this.page, required this.player, required this.size});

  final int album;
  final CoverFlowPage page;
  final PlayerController player;
  final double size;

  static String _time(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final a = player.albums[album];
    final header = size * 0.2;
    final rowH = (size - header) / CoverFlowPage.backRows;
    final fs = rowH * 0.42;
    final top = page.trackTopSpring.value;
    final first = top.floor().clamp(0, a.trackCount);
    final last = (first + CoverFlowPage.backRows + 1).clamp(0, a.trackCount);
    final current = player.index - a.firstIndex;

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFE4E7EA)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Titre de l'album et artiste, sur un bandeau gris clair.
          Container(
            height: header,
            padding: EdgeInsets.symmetric(horizontal: size * 0.05),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF3F4F6), Color(0xFFCDD1D6)],
              ),
              border: Border(bottom: BorderSide(color: Color(0xFF9EA4AB))),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.black, fontSize: fs * 1.05, fontWeight: FontWeight.w700, height: 1.2),
                ),
                Text(
                  a.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: const Color(0xFF555B62), fontSize: fs * 0.9, height: 1.2),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    top: (page.trackSpring.value - top) * rowH,
                    left: 0,
                    right: 0,
                    height: rowH,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF7DBBF5), Color(0xFF3A8BE6), Color(0xFF1F6BD3)],
                          stops: [0, 0.5, 1],
                        ),
                      ),
                    ),
                  ),
                  for (var t = first; t < last; t++)
                    Positioned(
                      top: (t - top) * rowH,
                      left: 0,
                      right: 0,
                      height: rowH,
                      child: _row(t, a, rowH, fs, selected: t == page.track, playing: t == current),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(int t, Album a, double rowH, double fs, {required bool selected, required bool playing}) {
    final track = player.queue[a.firstIndex + t];
    final ink = selected ? Colors.white : Colors.black;
    final dim = selected ? Colors.white : const Color(0xFF6B7178);
    final d = track.duration;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.04),
      decoration: selected
          ? null
          : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x1A000000)))),
      child: Row(
        children: [
          SizedBox(
            width: fs * 1.5,
            child: playing && player.playing
                ? Icon(Icons.volume_up_rounded, size: fs * 1.1, color: selected ? Colors.white : const Color(0xFF2F7FE0))
                : Text('${t + 1}', style: TextStyle(color: dim, fontSize: fs * 0.85)),
          ),
          Expanded(
            child: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink, fontSize: fs, fontWeight: FontWeight.w600),
            ),
          ),
          if (d != null) ...[
            SizedBox(width: fs * 0.5),
            Text(_time(d), style: TextStyle(color: dim, fontSize: fs * 0.85)),
          ],
        ],
      ),
    );
  }
}

/// Une pochette carrée ; sans image, un carré gris avec une note.
class _Face extends StatelessWidget {
  const _Face({required this.bytes, required this.size});

  final Uint8List? bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = bytes;
    return SizedBox(
      width: size,
      height: size,
      child: b == null
          ? const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF5B6168), Color(0xFF2E3237)],
                ),
              ),
              child: Center(child: Icon(Icons.music_note_rounded, size: 34, color: Color(0xFF9CA2A9))),
            )
          : Image.memory(
              b,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              // Décodée petite : l'écran fait 320 px de large.
              cacheWidth: 256,
            ),
    );
  }
}
