import 'dart:io';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/library.dart';
import '../core/player.dart';
import '../core/settings.dart';
import '../core/source.dart';
import '../core/paths.dart';
import '../core/strings.dart';
import '../core/version.dart';
import '../physics.dart';
import 'click.dart';
import 'look.dart';

sealed class IpodPage {
  String get title;
}

/// Ce que montre la moitié « image » d'un menu scindé (Classic, nano 3G
/// et 4G) quand la ligne est sélectionnée.
/// La fenêtre reste par-dessus les autres (Réglages › Premier plan, sous
/// Windows) ; la scène l'applique.
final windowOnTop = ValueNotifier(Settings.getString('window.top') == 'on');

enum MenuPreview { covers, settings, nowPlaying }

/// Mise en page d'un menu : lignes simples ; scindé (le menu d'un côté,
/// une image de l'autre, sur les écrans qui le font) ; ou lignes hautes
/// (albums avec leur vignette et l'artiste dessous).
enum MenuKind { normal, split, tall }

class MenuEntry {
  const MenuEntry(this.label,
      {this.open, this.action, this.value, this.checked, this.subtitle, this.art, this.preview = MenuPreview.covers});

  final String label;

  /// Seconde ligne (l'artiste d'un album), sur les lignes hautes.
  final String? subtitle;

  /// Vignette (la pochette d'un album), sur les lignes hautes : null tant
  /// qu'elle n'est pas lue.
  final Uint8List? Function()? art;

  /// Image d'un menu scindé pour cette ligne.
  final MenuPreview preview;

  /// Valeur affichée à droite (Réglages : « Non », « Tous »…), relue à
  /// chaque affichage.
  final String Function()? value;

  /// Coche à droite (choix en cours dans une liste d'options).
  final bool Function()? checked;

  /// Ouvre un sous-menu (affiche un chevron).
  final IpodPage Function()? open;

  /// Action immédiate (lancer un morceau…).
  final VoidCallback? action;
}

class MenuPage extends IpodPage {
  MenuPage(this.title, List<MenuEntry> Function() builder,
      {this.live = false, this.music = false, this.kind = MenuKind.normal})
      : _builder = builder;

  final MenuKind kind;

  @override
  final String title;
  final List<MenuEntry> Function() _builder;

  /// Reconstruit ses entrées à chaque affichage (menu principal).
  final bool live;

  /// Montre des albums ou des morceaux de la bibliothèque : ne vaut plus
  /// rien quand elle change.
  final bool music;
  List<MenuEntry>? _cache;

  List<MenuEntry> get entries => live ? _builder() : (_cache ??= _builder());

  int selected = 0;
  int top = 0;

  // Positions animées, en lignes.
  final selSpring = Spring(0, stiffness: 1400, damping: 1);
  final topSpring = Spring(0, stiffness: 900, damping: 1);
}

/// Les pochettes des albums en enfilade : celle du milieu de face, les
/// autres de biais de chaque côté (Classic, nano 3G et 4G).
class CoverFlowPage extends IpodPage {
  CoverFlowPage(this.selected) : pos = Spring(selected.toDouble(), stiffness: 210, damping: 0.92);

  @override
  String get title => 'Cover Flow';

  /// Album au centre (index dans la liste des albums).
  int selected;

  /// Position animée, en albums.
  final Spring pos;

  // --- Pochette retournée : la liste des morceaux de l'album au dos -----------

  /// Lignes de morceaux visibles au dos.
  static const backRows = 6;

  /// L'album du milieu est retourné (valider le retourne, MENU le remet).
  bool flipped = false;

  /// Retournement animé : 0 de face, 1 de dos.
  final flip = Spring(0, stiffness: 120, damping: 0.86);

  /// Morceau sélectionné au dos (rang dans l'album) et première ligne
  /// visible.
  int track = 0;
  int trackTop = 0;
  final trackSpring = Spring(0, stiffness: 1400, damping: 1);
  final trackTopSpring = Spring(0, stiffness: 900, damping: 1);
}

/// Ce que montre le bas de l'écran « En lecture ». Le bouton central fait
/// passer de l'un à l'autre, selon le modèle ([ScreenLook.centerCycle]) :
/// recherche dans le morceau, note en étoiles, pochette en grand, lecture
/// aléatoire.
enum NowPlayingMode { progress, volume, scrub, rating, art, shuffle }

/// La recherche (Musique › Recherche) : une réglette de lettres parcourue
/// à la molette, le bouton central ajoute la lettre ; les morceaux trouvés
/// s'affichent au-dessus, « OK » ouvre leur liste.
class SearchPage extends IpodPage {
  @override
  String get title => tr('Recherche');

  static const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// Cases après les lettres : espace, effacer, terminer.
  static const space = 36, delete = 37, done = 38, cells = 39;

  static String cellLabel(int i) => switch (i) {
        space => '␣',
        delete => '⌫',
        done => 'OK',
        _ => letters[i],
      };

  String query = '';
  int cell = 0;
  final cellSpring = Spring(0, stiffness: 1400, damping: 1);

  /// Les morceaux trouvés pour [query].
  List<Track> results = const [];
}

/// Durées possibles du rétroéclairage, en secondes (0 : toujours allumé).
const backlightChoices = [0, 2, 5, 10, 15, 20, 30];

String backlightLabel(int seconds) => seconds == 0 ? tr('Toujours allumé') : trSeconds(seconds);

/// Les lettres qui pilotent le baladeur, en plus des flèches : monter,
/// descendre, entrer (valider) et revenir (MENU).
enum KeyLayout {
  hjkl('H J K L', up: LogicalKeyboardKey.keyK, down: LogicalKeyboardKey.keyJ, enter: LogicalKeyboardKey.keyL, back: LogicalKeyboardKey.keyH),
  wasd('W A S D', up: LogicalKeyboardKey.keyW, down: LogicalKeyboardKey.keyS, enter: LogicalKeyboardKey.keyD, back: LogicalKeyboardKey.keyA),
  zqsd('Z Q S D', up: LogicalKeyboardKey.keyZ, down: LogicalKeyboardKey.keyS, enter: LogicalKeyboardKey.keyD, back: LogicalKeyboardKey.keyQ);

  const KeyLayout(this.label, {required this.up, required this.down, required this.enter, required this.back});

  final String label;
  final LogicalKeyboardKey up, down, enter, back;
}

class NowPlayingPage extends IpodPage {
  @override
  String get title => tr('En lecture');
}

/// Navigation dans les menus, pilotée par la molette et le clavier.
/// L'écran ne fait que dessiner cet état en l'animant.
class IpodNav extends ChangeNotifier {
  IpodNav(this.player, {required this.look}) : coverFlow = look.coverFlow {
    stack = [_root()];
    backlight = int.tryParse(Settings.getString('ipod.backlight') ?? '') ?? 10;
    keys = KeyLayout.values.asNameMap()[Settings.getString('ipod.keys')] ?? KeyLayout.hjkl;
    WheelClick.instance.enabled = Settings.getString('ipod.clicker') != 'off';
    WheelClick.instance.pitch =
        (int.tryParse(Settings.getString('ipod.clickPitch') ?? '') ?? 2).clamp(0, WheelClick.pitches.length - 1);
    _libraryVersion = player.libraryVersion;
    player.addListener(_onPlayer);
  }

  @override
  void dispose() {
    player.removeListener(_onPlayer);
    super.dispose();
  }

  int _libraryVersion = 0;

  /// La bibliothèque a changé (autre source, rafraîchie) : les pages qui
  /// montraient l'ancienne (albums, morceaux, Cover Flow) se referment. On
  /// reste sur En lecture si on y était.
  void _onPlayer() {
    if (player.libraryVersion == _libraryVersion) return;
    _libraryVersion = player.libraryVersion;
    final at = stack.indexWhere((p) => p is CoverFlowPage || p is SearchPage || (p is MenuPage && p.music));
    if (at < 1) return;
    final top = stack.last;
    stack.removeRange(at, stack.length);
    if (top is NowPlayingPage) stack.add(top);
    leaving = null;
    notifyListeners();
  }

  final PlayerController player;

  /// L'écran du modèle en main : il décide du nombre de lignes, des menus
  /// scindés, de ce que fait le bouton central sur « En lecture »…
  ScreenLook look;

  /// Nombre de lignes visibles dans un menu simple.
  int get visibleRows => look.visibleRows;

  /// Nombre de lignes visibles de [p] (moins dans un menu scindé à la
  /// verticale ou à lignes hautes).
  int rowsOf(MenuPage p) => look.rowsFor(p.kind);

  // --- Verrou (Hold) -------------------------------------------------------------

  /// Le verrou est mis : molette et boutons ne font plus rien, un cadenas
  /// s'affiche dans la barre de titre.
  bool locked = false;

  void toggleLock() {
    locked = !locked;
    notifyListeners();
  }

  /// L'écran sait afficher Cover Flow (écran couleur).
  bool coverFlow;

  // --- Rétroéclairage ----------------------------------------------------------

  /// Secondes avant que l'écran s'éteigne (0 : toujours allumé).
  int backlight = 10;

  DateTime lastInput = clock.now();

  bool get lit => !_dark && (backlight == 0 || clock.now().difference(lastInput) < Duration(seconds: backlight));

  /// Éteint à la main (entrée « Rétroéclairage » du menu principal des
  /// écrans monochromes), jusqu'au prochain geste.
  bool _dark = false;

  void darken() {
    _dark = true;
    notifyListeners();
  }

  /// Une main sur l'appareil : l'écran se rallume.
  void touch() {
    final wasLit = lit;
    _dark = false;
    lastInput = clock.now();
    if (!wasLit) notifyListeners();
  }

  /// Un autre appareil prend la navigation : même écran, même sélection,
  /// recadrée pour son nombre de lignes. Sans Cover Flow (écran
  /// monochrome), on en ressort.
  void fitLook(ScreenLook look) {
    this.look = look;
    coverFlow = look.coverFlow;
    if (!coverFlow) {
      final at = stack.indexWhere((p) => p is CoverFlowPage);
      if (at > 0) {
        stack.removeRange(at, stack.length);
        leaving = null;
      }
    }
    if (!look.centerCycle.contains(mode) && mode != NowPlayingMode.volume) mode = NowPlayingMode.progress;
    for (final p in stack.whereType<MenuPage>()) {
      final rows = rowsOf(p);
      if (p.selected >= p.top + rows) p.top = p.selected - rows + 1;
      p.top = p.top.clamp(0, math.max(0, p.entries.length - rows));
      p.topSpring
        ..value = p.top.toDouble()
        ..velocity = 0;
    }
    notifyListeners();
  }
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
    if (mode != NowPlayingMode.progress && clock.now().isAfter(_modeUntil)) {
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
    _modeUntil = clock.now().add(hold);
  }

  // --- Commandes de la molette ---------------------------------------------

  /// Renvoie false si rien n'a bougé (bout de liste) : pas de clic.
  bool scroll(int delta) {
    switch (page) {
      case final CoverFlowPage p when p.flipped:
        final count = player.albums[p.selected].trackCount;
        final t = (p.track + delta).clamp(0, count - 1);
        if (t == p.track) return false;
        p.track = t;
        if (t < p.trackTop) p.trackTop = t;
        if (t >= p.trackTop + CoverFlowPage.backRows) p.trackTop = t - CoverFlowPage.backRows + 1;
      case final CoverFlowPage p:
        final sel = (p.selected + delta).clamp(0, math.max(0, player.albums.length - 1)).toInt();
        if (sel == p.selected) return false;
        p.selected = sel;
      case final MenuPage p:
        final count = p.entries.length;
        if (count == 0) return false;
        final sel = (p.selected + delta).clamp(0, count - 1);
        if (sel == p.selected) return false;
        p.selected = sel;
        if (sel < p.top) p.top = sel;
        final rows = rowsOf(p);
        if (sel >= p.top + rows) p.top = sel - rows + 1;
      case final SearchPage p:
        final cell = (p.cell + delta).clamp(0, SearchPage.cells - 1);
        if (cell == p.cell) return false;
        p.cell = cell;
      case NowPlayingPage() when mode == NowPlayingMode.rating:
        final track = player.current;
        if (track == null) return false;
        final stars = (player.rating(track) + delta.sign).clamp(0, 5);
        _setMode(NowPlayingMode.rating, const Duration(seconds: 4));
        if (stars == player.rating(track)) return false;
        player.setRating(track, stars);
      case NowPlayingPage() when mode == NowPlayingMode.shuffle:
        _setMode(NowPlayingMode.shuffle, const Duration(seconds: 4));
        if (player.shuffle == delta > 0) return false;
        player.setShuffle(delta > 0);
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
    _syncPreview();
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
          notifyListeners(); // une valeur a pu changer (Réglages)
        }
      case final CoverFlowPage p when p.flipped:
        // On joue le morceau sans quitter le dos de la pochette.
        player.playAlbum(p.selected, p.track);
        notifyListeners();
      case final CoverFlowPage p:
        if (player.albums.isEmpty) return;
        // La pochette se retourne, sur le morceau en cours s'il est de cet
        // album.
        final album = player.albums[p.selected];
        final playing = player.currentIndex - album.firstIndex;
        p
          ..flipped = true
          ..track = playing >= 0 && playing < album.trackCount ? playing : 0
          ..trackTop = math.max(0, p.track - CoverFlowPage.backRows + 1);
        p.trackSpring
          ..value = p.track.toDouble()
          ..velocity = 0;
        p.trackTopSpring
          ..value = p.trackTop.toDouble()
          ..velocity = 0;
        notifyListeners();
      case final SearchPage p:
        switch (p.cell) {
          case SearchPage.done:
            if (p.results.isNotEmpty) _push(_tracks(p.query.trim(), p.results));
            return;
          case SearchPage.delete:
            if (p.query.isNotEmpty) p.query = p.query.substring(0, p.query.length - 1);
          case SearchPage.space:
            if (p.query.isNotEmpty && !p.query.endsWith(' ')) p.query += ' ';
          default:
            if (p.query.length < 24) p.query += SearchPage.letters[p.cell];
        }
        p.results = _search(p.query);
        notifyListeners();
      case NowPlayingPage():
        // Le bouton central passe d'un affichage au suivant, puis revient
        // à la progression.
        final cycle = look.centerCycle;
        final at = cycle.indexOf(mode) + 1;
        if (at < cycle.length) {
          _setMode(cycle[at], Duration(seconds: cycle[at] == NowPlayingMode.art ? 3600 : 4));
        } else {
          mode = NowPlayingMode.progress;
        }
        notifyListeners();
    }
  }

  /// Les morceaux dont le titre, l'artiste ou l'album contient [query].
  List<Track> _search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    bool has(String s) => s.toLowerCase().contains(q);
    return [
      for (final t in player.tracks)
        if (has(t.title) || has(t.artist) || has(t.album)) t,
    ]..sort((a, b) => _cmp(a.title, b.title));
  }

  void menu() {
    if (page case final CoverFlowPage p when p.flipped) {
      p.flipped = false; // la pochette se remet de face
      notifyListeners();
      return;
    }
    if (stack.length < 2) return;
    leaving = stack.removeLast();
    direction = -1;
    transition++;
    mode = NowPlayingMode.progress;
    _syncPreview();
    notifyListeners();
  }

  void _push(IpodPage p) {
    leaving = page;
    stack.add(p);
    direction = 1;
    transition++;
    mode = NowPlayingMode.progress;
    _syncPreview();
    notifyListeners();
  }

  void transitionDone() => leaving = null;

  /// Joue [list] depuis le morceau [index] et passe à En lecture.
  void _play(List<Track> list, int index, {String? uri}) {
    player.playTracks(list, index, uri: uri);
    _push(NowPlayingPage());
  }

  // --- Menus ---------------------------------------------------------------

  MenuPage _root() => MenuPage(tr('Lecteur'), live: true, kind: MenuKind.split, () => [
        // Ce qui n'a pas marché (pas d'appareil Spotify…) ; valider l'efface.
        if (player.notice case final notice?)
          MenuEntry(notice, action: player.dismissNotice),
        MenuEntry(tr('Musique'), open: _music),
        MenuEntry(tr('Réglages'), open: _settings, preview: MenuPreview.settings),
        MenuEntry(tr('Morceau au hasard'), action: () {
          if (player.tracks.isEmpty) return;
          _play(player.tracks, math.Random().nextInt(player.tracks.length));
        }),
        // Sur les écrans monochromes, le rétroéclairage s'éteint d'ici.
        if (look.mono) MenuEntry(tr('Rétroéclairage'), action: darken),
        if (player.current != null)
          MenuEntry(tr('En lecture'), open: NowPlayingPage.new, preview: MenuPreview.nowPlaying),
      ]);

  MenuPage _music() => MenuPage(tr('Musique'), live: true, kind: MenuKind.split, () => [
        if (coverFlow && player.albums.isNotEmpty)
          MenuEntry('Cover Flow', open: () => CoverFlowPage(math.max(0, player.currentAlbum))),
        MenuEntry(tr('Listes de lecture'), open: _playlists),
        MenuEntry(tr('Artistes'), open: _artists),
        MenuEntry(tr('Albums'), open: () => _albumList(tr('Albums'), _sortedAlbums(null))),
        MenuEntry(tr('Morceaux'), open: _songs),
        // (Seulement si les fichiers en donnent : Spotify n'en a pas par morceau.)
        if (player.tracks.any((t) => t.genre != null)) MenuEntry(tr('Genres'), open: _genres),
        MenuEntry(tr('Recherche'), open: SearchPage.new),
      ]);

  MenuPage _genres() => MenuPage(tr('Genres'), music: true, () {
        final names = <String, String>{};
        for (final t in player.tracks) {
          if (t.genre case final g?) names.putIfAbsent(g.toLowerCase(), () => g);
        }
        final sorted = names.values.toList()..sort(_cmp);
        return [
          for (final g in sorted)
            MenuEntry(g, open: () => _tracks(g, [for (final t in player.tracks) if (t.genre?.toLowerCase() == g.toLowerCase()) t])),
        ];
      });

  MenuPage _playlists() => MenuPage(tr('Listes de lecture'), music: true, () => [
        MenuEntry(tr('Ajouts récents'), open: () => _tracks(tr('Ajouts récents'), player.recentlyAdded(25))),
        MenuEntry(tr('Les plus écoutés'), open: () => _tracks(tr('Les plus écoutés'), player.mostPlayed(25))),
        for (final l in player.playlists) MenuEntry(l.name, open: () => _songList(l)),
      ]);

  /// Une liste de lecture : ses morceaux, chargés à la première ouverture
  /// si la source les donne à la demande (Spotify).
  MenuPage _songList(SongList l) => MenuPage(l.name, live: true, music: true, () {
        final tracks = l.tracks;
        if (tracks != null) {
          return [for (var i = 0; i < tracks.length; i++) MenuEntry(tracks[i].title, action: () => _play(tracks, i, uri: l.uri))];
        }
        // Pas parcourable (liste suivie, pas à soi) : on peut la jouer
        // entière quand même.
        if (l.error != null) {
          return [
            if (l.uri case final uri?)
              MenuEntry(tr('Lire la liste'), action: () {
                player.playUri(uri);
                _push(NowPlayingPage());
              })
            else
              MenuEntry(tr('Aucun élément')),
          ];
        }
        l.load(onDone: notifyListeners).ignore();
        return [MenuEntry(tr('Chargement…'))];
      });

  // --- Réglages ------------------------------------------------------------

  /// La page Réglages ouverte : on y revient d'un coup après avoir choisi
  /// une bibliothèque.
  MenuPage? _settingsPage;

  MenuPage _settings() => _settingsPage = MenuPage(tr('Réglages'), live: true, kind: MenuKind.split, () => [
        MenuEntry(tr('À propos'), open: _about),
        MenuEntry(
          tr('Bibliothèque'),
          value: () => player.loading ? tr('Lecture…') : _sourceName(),
          open: _places,
        ),
        MenuEntry(
          tr('Lecture aléatoire'),
          value: () => player.shuffle ? tr('Morceaux') : tr('Non'),
          action: () => player.setShuffle(!player.shuffle),
        ),
        MenuEntry(
          tr('Répéter'),
          value: () => switch (player.repeat) {
            RepeatMode.off => tr('Non'),
            RepeatMode.one => tr('Un'),
            RepeatMode.all => tr('Tous'),
          },
          action: () => player.setRepeat(RepeatMode.values[(player.repeat.index + 1) % RepeatMode.values.length]),
        ),
        MenuEntry(tr('Rétroéclairage'), value: () => backlight == 0 ? tr('Allumé') : '$backlight s', open: _backlightMenu),
        MenuEntry(
          tr('Clic'),
          value: () => WheelClick.instance.enabled ? tr('Haut-parleur') : tr('Non'),
          action: () {
            final on = !WheelClick.instance.enabled;
            WheelClick.instance.enabled = on;
            Settings.setString('ipod.clicker', on ? 'on' : 'off');
          },
        ),
        MenuEntry(
          tr('Tonalité du clic'),
          value: () => tr(WheelClick.pitchNames[WheelClick.instance.pitch]),
          open: _pitchMenu,
        ),
        MenuEntry(tr('Touches'), value: () => keys.label, open: _keysMenu),
        // Sous Windows, rien ne réserve de place à l'iPod : on peut le garder
        // par-dessus les autres fenêtres.
        if (Platform.isWindows)
          MenuEntry(
            tr('Premier plan'),
            value: () => windowOnTop.value ? tr('Oui') : tr('Non'),
            action: () {
              windowOnTop.value = !windowOnTop.value;
              Settings.setString('window.top', windowOnTop.value ? 'on' : 'off');
            },
          ),
        MenuEntry(tr('Langue'), value: () => Lang.current.nativeName, open: _languageMenu),
      ]);

  /// Les lettres de déplacement choisies (Réglages › Touches).
  late KeyLayout keys;

  MenuPage _keysMenu() {
    final page = MenuPage(tr('Touches'), live: true, () => [
          for (final k in KeyLayout.values)
            MenuEntry(k.label, checked: () => k == keys, action: () {
              keys = k;
              Settings.setString('ipod.keys', k.name);
              menu(); // choisi : on revient aux Réglages
            }),
        ]);
    _focus(page, keys.index);
    return page;
  }

  /// Page Tonalité du clic : parcourir la liste fait entendre chaque
  /// tonalité ; valider la garde (on reste là pour comparer).
  MenuPage? _pitchPage;

  MenuPage _pitchMenu() {
    final click = WheelClick.instance;
    final page = _pitchPage = MenuPage(tr('Tonalité du clic'), live: true, () => [
          for (var i = 0; i < WheelClick.pitches.length; i++)
            MenuEntry(tr(WheelClick.pitchNames[i]), checked: () => i == click.pitch, action: () {
              click.pitch = i;
              Settings.setString('ipod.clickPitch', '$i');
            }),
        ]);
    _focus(page, click.pitch);
    return page;
  }

  /// Le clic prend la tonalité survolée tant qu'on est dans son menu.
  void _syncPreview() {
    final p = page;
    WheelClick.instance.preview = p is MenuPage && identical(p, _pitchPage) ? p.selected : null;
  }

  MenuPage _languageMenu() {
    final page = MenuPage(tr('Langue'), live: true, () => [
          for (final l in Lang.values)
            MenuEntry(l.nativeName, checked: () => l == Lang.current, action: () {
              if (l == Lang.current) return;
              Lang.set(l);
              _relabel();
            }),
        ]);
    _focus(page, Lang.current.index);
    return page;
  }

  /// Nouvelle langue : les pages ouvertes (Lecteur › Réglages › Langue)
  /// sont reconstruites avec leurs titres traduits, à la même place.
  void _relabel() {
    final fresh = <MenuPage>[_root(), _settings(), _languageMenu()];
    for (var i = 0; i < fresh.length && i < stack.length; i++) {
      final old = stack[i], now = fresh[i];
      if (old is! MenuPage) continue;
      now
        ..selected = old.selected
        ..top = old.top;
      now.selSpring.value = old.selSpring.value;
      now.topSpring.value = old.topSpring.value;
    }
    stack
      ..clear()
      ..addAll(fresh);
    leaving = null;
  }

  /// Ouvre [page] sur la ligne [at] (le choix en cours).
  void _focus(MenuPage page, int at) {
    at = math.max(0, at);
    page
      ..selected = at
      ..top = math.max(0, at - rowsOf(page) + 1);
    page.selSpring.value = at.toDouble();
    page.topSpring.value = page.top.toDouble();
  }

  MenuPage _backlightMenu() {
    final page = MenuPage(tr('Rétroéclairage'), live: true, () => [
          for (final s in backlightChoices)
            MenuEntry(backlightLabel(s), checked: () => s == backlight, action: () {
              backlight = s;
              Settings.setString('ipod.backlight', '$s');
              menu(); // choisi : on revient aux Réglages
            }),
        ]);
    // On arrive sur le choix en cours.
    _focus(page, backlightChoices.indexOf(backlight));
    return page;
  }

  // --- Bibliothèque : choisir le dossier de musique ---------------------------

  static String _folderName(String path) => lastSegment(path);

  /// On écoute la musique du dossier [path] (et pas un service en ligne).
  bool _usingFolder(String path) => path == player.musicDir && player.source.id == 'local';

  /// D'où vient la musique : le service en ligne, ou le nom du dossier.
  String _sourceName() {
    for (final a in player.accounts) {
      if (a.sourceId == player.source.id) return a.label;
    }
    return _folderName(player.musicDir);
  }

  /// Points de départ : le dossier actuel, le dossier personnel, les disques
  /// branchés, la racine (sous Windows : les lecteurs C:, D:…). Cherchés une
  /// fois à l'ouverture de la page, pas à chaque image.
  MenuPage _places() => MenuPage(tr('Bibliothèque'), () {
        final user = Platform.environment['USER'] ?? '';
        return [
          // Les services en ligne d'abord (Spotify…), puis les dossiers.
          for (final a in player.accounts) MenuEntry(a.label, open: () => _account(a)),
          MenuEntry(tr('Dossier actuel'), value: () => _folderName(player.musicDir), open: () => _folder(player.musicDir)),
          MenuEntry(tr('Dossier personnel'), open: () => _folder(homeDir())),
          if (Platform.isWindows)
            for (final drive in windowsDrives()) MenuEntry(drive, open: () => _folder(drive))
          else ...[
            for (final (label, path) in [
              (tr('Disques'), '/run/media/$user'),
              (tr('Disques'), '/media/$user'),
              (tr('Disques'), '/Volumes'),
            ])
              if (user.isNotEmpty || !path.endsWith('/')) // pas de « /media/ » sans nom
                if (Directory(path).existsSync()) MenuEntry(label, open: () => _folder(path)),
            MenuEntry(tr('Racine'), open: () => _folder('/')),
          ],
        ];
      });

  // --- Comptes en ligne (Spotify…) -------------------------------------------

  /// Un service en ligne : se connecter, l'utiliser.
  MenuPage _account(RemoteAccount a) => MenuPage(a.label, live: true, () {
        if (a.connecting) return [MenuEntry(tr('Connexion…'), value: () => tr('navigateur'))];
        if (!a.connected) {
          return [
            MenuEntry(tr('Se connecter'), action: () {
              a.connect().then((_) {
                if (a.connected) player.useSource(a.sourceId);
              }, onError: (Object e) {
                player.notice = '$e';
              }).whenComplete(notifyListeners);
              notifyListeners();
            }),
          ];
        }
        final inUse = player.source.id == a.sourceId;
        return [
          MenuEntry(tr('Utiliser %s').replaceFirst('%s', a.label), checked: () => inUse, action: () {
            if (!inUse) player.useSource(a.sourceId);
            _backToSettings();
          }),
          // Ce qu'on vient d'ajouter au compte, depuis une autre appli.
          if (inUse)
            MenuEntry(tr('Actualiser'), action: () {
              player.loadLibrary();
              _backToSettings();
            }),
          MenuEntry(tr('Compte'), value: () => a.userName ?? ''),
          MenuEntry(tr('Se déconnecter'), action: () {
            a.disconnect();
            if (inUse) player.useSource('local');
            notifyListeners();
          }),
        ];
      });

  /// Un dossier : « Utiliser ce dossier », puis ses sous-dossiers.
  MenuPage _folder(String path) => MenuPage(_folderName(path), () {
        List<Directory> subs;
        try {
          subs = Directory(path)
              .listSync(followLinks: false)
              .whereType<Directory>()
              .where((d) => !_folderName(d.path).startsWith('.'))
              .toList()
            ..sort((a, b) => _cmp(_folderName(a.path), _folderName(b.path)));
        } catch (_) {
          subs = const []; // illisible : on peut quand même le choisir
        }
        return [
          // (Coché seulement si c'est vraiment ce dossier qu'on écoute :
          // depuis Spotify, choisir le même dossier y revient.)
          MenuEntry(tr('Utiliser ce dossier'), checked: () => _usingFolder(path), action: () {
            if (!_usingFolder(path)) player.setMusicDir(path);
            _backToSettings();
          }),
          for (final d in subs) MenuEntry(_folderName(d.path), open: () => _folder(d.path)),
        ];
      });

  /// Revient d'un coup aux Réglages (en glissant vers la droite).
  void _backToSettings() {
    // (La page elle-même, pas son titre : un dossier peut s'appeler pareil.)
    final at = stack.lastIndexWhere((p) => identical(p, _settingsPage));
    if (at < 0 || at == stack.length - 1) return;
    leaving = stack.last;
    stack.removeRange(at + 1, stack.length);
    direction = -1;
    transition++;
    notifyListeners();
  }

  MenuPage _about() => MenuPage(tr('À propos'), () {
        final artists = {for (final a in player.albums) a.artist.toLowerCase()};
        return [
          MenuEntry(tr('Morceaux'), value: () => '${player.tracks.length}'),
          MenuEntry(tr('Albums'), value: () => '${player.albums.length}'),
          MenuEntry(tr('Artistes'), value: () => '${artists.length}'),
          MenuEntry(tr('Listes'), value: () => '${player.playlists.length}'),
          MenuEntry('Version', value: () => appVersion),
        ];
      });

  static int _cmp(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  MenuPage _artists() => MenuPage(tr('Artistes'), music: true, () {
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
    return MenuPage(artist, music: true, () => [
          MenuEntry(tr('Tous'), open: () => _tracks(artist, [for (final i in ids) ..._albumTracks(player.albums[i])])),
          for (final i in ids) MenuEntry(player.albums[i].title, open: () => _album(i)),
        ]);
  }

  /// Des albums : sur les écrans qui le montrent, chacun avec sa vignette
  /// et son artiste.
  MenuPage _albumList(String title, List<int> ids) => MenuPage(title, music: true, kind: MenuKind.tall, () => [
        for (final i in ids)
          MenuEntry(
            player.albums[i].title,
            subtitle: player.albums[i].artist,
            art: () => player.albumCover(i),
            open: () => _album(i),
          ),
      ]);

  List<Track> _albumTracks(Album a) => player.tracks.sublist(a.firstIndex, a.firstIndex + a.trackCount);

  /// Un album : le lancer joue cet album (l'album entier chez la source,
  /// s'il en a un).
  MenuPage _album(int i) {
    final a = player.albums[i];
    final list = _albumTracks(a);
    return MenuPage(a.title, music: true, () => [
          for (var k = 0; k < list.length; k++) MenuEntry(list[k].title, action: () => _play(list, k, uri: a.uri)),
        ]);
  }

  MenuPage _songs() => MenuPage(tr('Morceaux'), music: true, () {
        final list = [...player.tracks]..sort((a, b) => _cmp(a.title, b.title));
        return [for (var i = 0; i < list.length; i++) MenuEntry(list[i].title, action: () => _play(list, i))];
      });

  MenuPage _tracks(String title, List<Track> list) =>
      MenuPage(title, music: true, () => [for (var i = 0; i < list.length; i++) MenuEntry(list[i].title, action: () => _play(list, i))]);
}
