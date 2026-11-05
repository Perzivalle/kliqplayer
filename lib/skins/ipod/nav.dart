import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/library.dart';
import '../../core/player.dart';
import '../../physics.dart';

sealed class IpodPage {
  String get title;
}

class MenuEntry {
  const MenuEntry(this.label, {this.open, this.action});

  final String label;

  /// Ouvre un sous-menu (affiche un chevron).
  final IpodPage Function()? open;

  /// Action immédiate (lancer un morceau…).
  final VoidCallback? action;
}

class MenuPage extends IpodPage {
  MenuPage(this.title, List<MenuEntry> Function() builder, {this.live = false}) : _builder = builder;

  @override
  final String title;
  final List<MenuEntry> Function() _builder;

  /// Reconstruit ses entrées à chaque affichage (menu principal).
  final bool live;
  List<MenuEntry>? _cache;

  List<MenuEntry> get entries => live ? _builder() : (_cache ??= _builder());

  int selected = 0;
  int top = 0;

  // Positions animées, en lignes.
  final selSpring = Spring(0, stiffness: 1400, damping: 1);
  final topSpring = Spring(0, stiffness: 900, damping: 1);
}

enum NowPlayingMode { progress, volume, scrub }

class NowPlayingPage extends IpodPage {
  @override
  String get title => 'En lecture';
}

/// Navigation dans les menus, pilotée par la molette et le clavier.
/// L'écran ne fait que dessiner cet état en l'animant.
class IpodNav extends ChangeNotifier {
  IpodNav(this.player, {required this.visibleRows}) {
    stack = [_root()];
  }

  final PlayerController player;

  /// Nombre de lignes visibles dans un menu (dépend de l'écran du modèle).
  final int visibleRows;
  late final List<IpodPage> stack;

  IpodPage get page => stack.last;

  /// Page qui sort pendant une transition, et sens (+1 entrée, -1 retour).
  IpodPage? leaving;
  int direction = 1;
  int transition = 0;

  NowPlayingMode mode = NowPlayingMode.progress;
  DateTime _modeUntil = DateTime(0);

  /// Retour à l'affichage de la progression après un moment d'inactivité.
  bool expireMode() {
    if (mode != NowPlayingMode.progress && DateTime.now().isAfter(_modeUntil)) {
      mode = NowPlayingMode.progress;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Recherche par appui long : montre le losange sur la barre.
  void showScrub() {
    if (page is! NowPlayingPage) return;
    _setMode(NowPlayingMode.scrub, const Duration(milliseconds: 1500));
    notifyListeners();
  }

  void _setMode(NowPlayingMode m, Duration hold) {
    mode = m;
    _modeUntil = DateTime.now().add(hold);
  }

  // --- Commandes de la molette ---------------------------------------------

  /// Renvoie false si rien n'a bougé (bout de liste) : pas de clic.
  bool scroll(int delta) {
    switch (page) {
      case final MenuPage p:
        final count = p.entries.length;
        if (count == 0) return false;
        final sel = (p.selected + delta).clamp(0, count - 1);
        if (sel == p.selected) return false;
        p.selected = sel;
        if (sel < p.top) p.top = sel;
        if (sel >= p.top + visibleRows) p.top = sel - visibleRows + 1;
      case NowPlayingPage():
        if (mode == NowPlayingMode.scrub) {
          final total = player.duration.inMilliseconds;
          if (total > 0) {
            final pos = player.smoothPosition.inMilliseconds + delta * 3000;
            player.seekProgress(pos / total);
          }
          _setMode(NowPlayingMode.scrub, const Duration(seconds: 4));
        } else {
          player.setVolume(player.volume + delta * 3);
          _setMode(NowPlayingMode.volume, const Duration(milliseconds: 1600));
        }
    }
    notifyListeners();
    return true;
  }

  void select() {
    switch (page) {
      case final MenuPage p:
        if (p.entries.isEmpty) return;
        final e = p.entries[p.selected];
        if (e.open != null) {
          _push(e.open!());
        } else {
          e.action?.call();
        }
      case NowPlayingPage():
        _setMode(
          mode == NowPlayingMode.scrub ? NowPlayingMode.progress : NowPlayingMode.scrub,
          const Duration(seconds: 4),
        );
        notifyListeners();
    }
  }

  void menu() {
    if (stack.length < 2) return;
    leaving = stack.removeLast();
    direction = -1;
    transition++;
    mode = NowPlayingMode.progress;
    notifyListeners();
  }

  void _push(IpodPage p) {
    leaving = page;
    stack.add(p);
    direction = 1;
    transition++;
    mode = NowPlayingMode.progress;
    notifyListeners();
  }

  void transitionDone() => leaving = null;

  Future<void> _play(int index) async {
    await player.jumpTo(index);
    await player.play();
    _push(NowPlayingPage());
  }

  // --- Menus ---------------------------------------------------------------

  MenuPage _root() => MenuPage('Lecteur', live: true, () => [
        MenuEntry('Musique', open: _music),
        MenuEntry('Morceau au hasard', action: () {
          if (player.queue.isEmpty) return;
          _play(math.Random().nextInt(player.queue.length));
        }),
        if (player.current != null) MenuEntry('En lecture', open: NowPlayingPage.new),
      ]);

  MenuPage _music() => MenuPage('Musique', () => [
        MenuEntry('Artistes', open: _artists),
        MenuEntry('Albums', open: () => _albumList('Albums', _sortedAlbums(null))),
        MenuEntry('Morceaux', open: _songs),
      ]);

  static int _cmp(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  MenuPage _artists() => MenuPage('Artistes', () {
        final names = <String, String>{};
        for (final a in player.albums) {
          names.putIfAbsent(a.artist.toLowerCase(), () => a.artist);
        }
        final sorted = names.values.toList()..sort(_cmp);
        return [for (final n in sorted) MenuEntry(n, open: () => _artist(n))];
      });

  /// Index (dans player.albums) triés par titre, éventuellement d'un artiste.
  List<int> _sortedAlbums(String? artist) {
    final albums = player.albums;
    final ids = [
      for (var i = 0; i < albums.length; i++)
        if (artist == null || albums[i].artist.toLowerCase() == artist.toLowerCase()) i,
    ]..sort((a, b) => _cmp(albums[a].title, albums[b].title));
    return ids;
  }

  MenuPage _artist(String artist) {
    final ids = _sortedAlbums(artist);
    return MenuPage(artist, () => [
          MenuEntry('Tous', open: () => _tracks(artist, [for (final i in ids) ..._albumTracks(player.albums[i])])),
          for (final i in ids) MenuEntry(player.albums[i].title, open: () => _album(i)),
        ]);
  }

  MenuPage _albumList(String title, List<int> ids) =>
      MenuPage(title, () => [for (final i in ids) MenuEntry(player.albums[i].title, open: () => _album(i))]);

  Iterable<int> _albumTracks(Album a) => Iterable.generate(a.trackCount, (k) => a.firstIndex + k);

  MenuPage _album(int i) => _tracks(player.albums[i].title, _albumTracks(player.albums[i]).toList());

  MenuPage _songs() => MenuPage('Morceaux', () {
        final ids = List.generate(player.queue.length, (i) => i)
          ..sort((a, b) => _cmp(player.queue[a].title, player.queue[b].title));
        return [for (final i in ids) MenuEntry(player.queue[i].title, action: () => _play(i))];
      });

  MenuPage _tracks(String title, List<int> ids) =>
      MenuPage(title, () => [for (final i in ids) MenuEntry(player.queue[i].title, action: () => _play(i))]);
}
