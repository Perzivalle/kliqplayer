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
import '../physics.dart';
import 'click.dart';
import 'look.dart';

sealed class IpodPage {
  String get title;
}

class MenuEntry {
  const MenuEntry(this.label, {this.open, this.action, this.value, this.checked});

  final String label;

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

enum NowPlayingMode { progress, volume, scrub }

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
  IpodNav(this.player, {required ScreenLook look})
      : visibleRows = look.visibleRows,
        coverFlow = look.coverFlow {
    stack = [_root()];
    backlight = int.tryParse(Settings.getString('ipod.backlight') ?? '') ?? 10;
    keys = KeyLayout.values.asNameMap()[Settings.getString('ipod.keys')] ?? KeyLayout.hjkl;
    WheelClick.instance.enabled = Settings.getString('ipod.clicker') != 'off';
    WheelClick.instance.pitch =
        (int.tryParse(Settings.getString('ipod.clickPitch') ?? '') ?? 2).clamp(0, WheelClick.pitches.length - 1);
  }

  final PlayerController player;

  /// Nombre de lignes visibles dans un menu (dépend de l'écran du modèle).
  int visibleRows;

  /// L'écran sait afficher Cover Flow (écran couleur).
  bool coverFlow;

  // --- Rétroéclairage ----------------------------------------------------------

  /// Secondes avant que l'écran s'éteigne (0 : toujours allumé).
  int backlight = 10;

  DateTime lastInput = clock.now();

  bool get lit => backlight == 0 || clock.now().difference(lastInput) < Duration(seconds: backlight);

  /// Une main sur l'appareil : l'écran se rallume.
  void touch() {
    final wasLit = lit;
    lastInput = clock.now();
    if (!wasLit) notifyListeners();
  }

  /// Un autre appareil prend la navigation : même écran, même sélection,
  /// recadrée pour son nombre de lignes. Sans Cover Flow (écran
  /// monochrome), on en ressort.
  void fitLook(ScreenLook look) {
    coverFlow = look.coverFlow;
    if (!coverFlow) {
      final at = stack.indexWhere((p) => p is CoverFlowPage);
      if (at > 0) {
        stack.removeRange(at, stack.length);
        leaving = null;
        notifyListeners();
      }
    }
    final rows = look.visibleRows;
    if (rows == visibleRows) return;
    visibleRows = rows;
    for (final p in stack.whereType<MenuPage>()) {
      if (p.selected >= p.top + rows) p.top = p.selected - rows + 1;
      final count = p.entries.length;
      p.top = p.top.clamp(0, math.max(0, count - rows));
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
      case NowPlayingPage():
        _setMode(
          mode == NowPlayingMode.scrub ? NowPlayingMode.progress : NowPlayingMode.scrub,
          const Duration(seconds: 4),
        );
        notifyListeners();
    }
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

  MenuPage _root() => MenuPage(tr('Lecteur'), live: true, () => [
        // Ce qui n'a pas marché (pas d'appareil Spotify…) ; valider l'efface.
        if (player.notice case final notice?)
          MenuEntry(notice, action: () {
            player.notice = null;
          }),
        MenuEntry(tr('Musique'), open: _music),
        MenuEntry(tr('Réglages'), open: _settings),
        MenuEntry(tr('Morceau au hasard'), action: () {
          if (player.tracks.isEmpty) return;
          _play(player.tracks, math.Random().nextInt(player.tracks.length));
        }),
        if (player.current != null) MenuEntry(tr('En lecture'), open: NowPlayingPage.new),
      ]);

  MenuPage _music() => MenuPage(tr('Musique'), live: true, () => [
        if (coverFlow && player.albums.isNotEmpty)
          MenuEntry('Cover Flow', open: () => CoverFlowPage(math.max(0, player.currentAlbum))),
        MenuEntry(tr('Listes de lecture'), open: _playlists),
        MenuEntry(tr('Artistes'), open: _artists),
        MenuEntry(tr('Albums'), open: () => _albumList(tr('Albums'), _sortedAlbums(null))),
        MenuEntry(tr('Morceaux'), open: _songs),
      ]);

  MenuPage _playlists() => MenuPage(tr('Listes de lecture'), () => [
        MenuEntry(tr('Ajouts récents'), open: () => _tracks(tr('Ajouts récents'), player.recentlyAdded(25))),
        MenuEntry(tr('Les plus écoutés'), open: () => _tracks(tr('Les plus écoutés'), player.mostPlayed(25))),
        for (final l in player.playlists) MenuEntry(l.name, open: () => _songList(l)),
      ]);

  /// Une liste de lecture : ses morceaux, chargés à la première ouverture
  /// si la source les donne à la demande (Spotify).
  MenuPage _songList(SongList l) => MenuPage(l.name, live: true, () {
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

  MenuPage _settings() => MenuPage(tr('Réglages'), live: true, () => [
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
      ..top = math.max(0, at - visibleRows + 1);
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
            _backTo(tr('Réglages'));
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
            _backTo(tr('Réglages'));
          }),
          for (final d in subs) MenuEntry(_folderName(d.path), open: () => _folder(d.path)),
        ];
      });

  /// Revient d'un coup à la page [title] (en glissant vers la droite).
  void _backTo(String title) {
    final at = stack.lastIndexWhere((p) => p.title == title);
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
          MenuEntry('Version', value: () => '0.5.0'),
        ];
      });

  static int _cmp(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  MenuPage _artists() => MenuPage(tr('Artistes'), () {
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
          MenuEntry(tr('Tous'), open: () => _tracks(artist, [for (final i in ids) ..._albumTracks(player.albums[i])])),
          for (final i in ids) MenuEntry(player.albums[i].title, open: () => _album(i)),
        ]);
  }

  MenuPage _albumList(String title, List<int> ids) =>
      MenuPage(title, () => [for (final i in ids) MenuEntry(player.albums[i].title, open: () => _album(i))]);

  List<Track> _albumTracks(Album a) => player.tracks.sublist(a.firstIndex, a.firstIndex + a.trackCount);

  /// Un album : le lancer joue cet album (l'album entier chez la source,
  /// s'il en a un).
  MenuPage _album(int i) {
    final a = player.albums[i];
    final list = _albumTracks(a);
    return MenuPage(a.title, () => [
          for (var k = 0; k < list.length; k++) MenuEntry(list[k].title, action: () => _play(list, k, uri: a.uri)),
        ]);
  }

  MenuPage _songs() => MenuPage(tr('Morceaux'), () {
        final list = [...player.tracks]..sort((a, b) => _cmp(a.title, b.title));
        return [for (var i = 0; i < list.length; i++) MenuEntry(list[i].title, action: () => _play(list, i))];
      });

  MenuPage _tracks(String title, List<Track> list) =>
      MenuPage(title, () => [for (var i = 0; i < list.length; i++) MenuEntry(list[i].title, action: () => _play(list, i))]);
}
