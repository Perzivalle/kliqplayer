import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/player.dart';
import 'nav.dart';

/// Cover Flow : les pochettes en enfilade sur fond noir, celle du milieu de
/// face, les autres pivotées de chaque côté, chacune avec son reflet. Le
/// titre et l'artiste de l'album du milieu sont écrits dessous.
class CoverFlowView extends StatelessWidget {
  const CoverFlowView({super.key, required this.page, required this.player});

  final CoverFlowPage page;
  final PlayerController player;

  /// Angle des pochettes de côté.
  static const double _tilt = 72 * math.pi / 180;

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
          return const Center(child: Text('Aucun album', style: TextStyle(color: Colors.white70)));
        }
        // Pochette du milieu : la plus grande qui laisse la place au reflet
        // et aux deux lignes de texte.
        final s = math.min(h * 0.5, w * 0.44);
        // Centrées dans la place laissée au-dessus des deux lignes de texte.
        final cy = math.max(6.0, (h - 44 - s * (1 + _reflection)) / 2) + s / 2;
        final pos = page.pos.value;

        // Les plus éloignées d'abord : celle du milieu passe par-dessus.
        final first = math.max(0, (pos - 6).floor());
        final last = math.min(albums.length - 1, (pos + 6).ceil());
        final order = [for (var i = first; i <= last; i++) i]
          ..sort((a, b) => (b - pos).abs().compareTo((a - pos).abs()));

        final album = albums[page.selected.clamp(0, albums.length - 1)];
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final i in order) _cover(i, i - pos, s, w / 2, cy),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
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
    final x = cx + t * s * 0.70 + (d - t) * s * 0.26;
    final angle = -t * _tilt;
    final depth = t.abs() * s * 0.55;

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
            // Reflet sur le sol noir, qui s'efface vers le bas.
            SizedBox(
              width: s,
              height: s * _reflection,
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      width: s,
                      height: s,
                      child: Transform.flip(flipY: true, child: face),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xB0000000), Colors.black],
                            stops: [0, 0.9],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
