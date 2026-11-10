part of 'ipod.dart';

/// Banc d'essai des animations (LECTEUR_BENCH), à part de la scène qu'il
/// pilote.
extension _Bench on _IpodStageState {
  /// LECTEUR_BENCH=1 : joue chaque animation l'une après l'autre (menus,
  /// Cover Flow, En lecture, tiroir, teintes, échanges) et affiche pour
  /// chacune les temps d'image (construction ui, rendu raster), puis quitte.
  /// Le son est coupé le temps du banc ; le modèle en main est remis à la fin.
  Future<void> _bench() async {
    final only = Platform.environment['LECTEUR_BENCH']!;
    final build = <double>[], raster = <double>[], at = <int>[];
    var recording = false;
    var t0 = 0;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      if (!recording) return;
      for (final t in timings) {
        build.add(t.buildDuration.inMicroseconds / 1000);
        raster.add(t.rasterDuration.inMicroseconds / 1000);
        at.add(t.timestampInMicroseconds(ui.FramePhase.vsyncStart) ~/ 1000 - t0);
      }
    });
    Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
    Future<void> run(String name, Future<void> Function() body) async {
      if (only != '1' && !only.split(',').contains(name)) return;
      build.clear();
      raster.clear();
      at.clear();
      t0 = now();
      recording = true;
      await body();
      await wait(400); // les derniers temps arrivent par paquets
      recording = false;
      if (raster.isEmpty) {
        stdout.writeln('[bench] ${name.padRight(14)} aucune image');
        return;
      }
      String f(double v) => v.toStringAsFixed(1).padLeft(5);
      final sorted = [...raster]..sort();
      double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
      final slowAt = [for (var i = 0; i < build.length; i++) if (build[i] > 16.7 || raster[i] > 16.7) i];
      final slow = '${slowAt.length} ${[for (final i in slowAt) '@${at[i]}ms:${raster[i].round()}']}';
      stdout.writeln('[bench] ${name.padRight(14)} ${raster.length.toString().padLeft(4)} img · '
          'raster moy${f(avg(raster))} p90${f(sorted[(sorted.length * 0.9).floor()])} max${f(sorted.last)} · '
          'ui moy${f(avg(build))} max${f(build.reduce(math.max))} · lentes $slow');
    }

    void goTo(String label) {
      final p = _nav.page;
      if (p is! MenuPage) return;
      final i = p.entries.indexWhere((e) => e.label == label);
      if (i < 0) return;
      _nav.scroll(i - p.selected);
      _nav.select();
    }

    Future<void> home() async {
      while (_nav.stack.length > 1) {
        _nav.menu();
        await wait(350);
      }
    }

    final volume = widget.player.volume;
    final start = _model;
    widget.player.setVolume(0);
    // Montée de l'iPod, puis la prise qui se branche et l'écran qui s'allume.
    await run('démarrage', () async {
      ipodLanded.addListener(() => stdout.writeln('[bench]   arrivé @${now() - t0}ms'));
      screenPower.addListener(() => stdout.writeln('[bench]   écran ${screenPower.value} @${now() - t0}ms'));
      await wait(3000);
    });

    await run('repos', () => wait(1500));
    await run('menu-entrer', () async {
      for (var i = 0; i < 3; i++) {
        goTo(tr('Musique'));
        await wait(450);
        _nav.menu();
        await wait(450);
      }
    });
    goTo(tr('Musique'));
    await wait(400);
    goTo(tr('Morceaux'));
    await wait(400);
    await run('menu-défiler', () async {
      for (var i = 0; i < 25; i++) {
        _nav.scroll(1);
        await wait(70);
      }
      for (var i = 0; i < 25; i++) {
        _nav.scroll(-1);
        await wait(70);
      }
      await wait(300);
    });
    _nav.select(); // joue le morceau, passe à En lecture
    await wait(800);
    await run('en-lecture', () async {
      await wait(2000);
      _nav.scroll(1); // volume
      await wait(1800);
    });
    await home();
    goTo(tr('Musique'));
    await wait(400);
    if (_nav.page case final MenuPage p when p.entries.any((e) => e.label == 'Cover Flow')) {
      goTo('Cover Flow');
      await wait(600);
      await run('coverflow', () async {
        for (var i = 0; i < 12; i++) {
          _nav.scroll(1);
          await wait(130);
        }
        await wait(500);
      });
      await run('coverflow-bis', () async {
        // Mêmes pochettes, déjà chargées.
        for (var i = 0; i < 12; i++) {
          _nav.scroll(-1);
          await wait(130);
        }
        await wait(500);
      });
      await run('pochette', () async {
        _nav.select();
        await wait(900);
        _nav.menu();
        await wait(900);
      });
    }
    await home();
    // Souris qui approche d'un coin du haut : les poignées sortent, rentrent.
    await run('poignées', () async {
      for (final side in [1, -1, 1]) {
        _setHoverSide(side, true);
        await wait(600);
        _setHoverSide(side, false);
        await wait(600);
      }
    });
    // L'iPod d'un bord à l'autre de la fenêtre, puis remis à sa place.
    final place = _placeTarget;
    if (_canPlace) {
      await run('déplacer', () async {
        for (final to in [-1, 1, 0]) {
          stdout.writeln('[bench]   vers $to @${now() - t0}ms');
          _moveTo(to);
          await wait(900);
        }
      });
      _moveTo(place);
      await wait(900);
    }
    await run('tiroir', () async {
      for (final open in [true, false, true, false]) {
        _setOpen(open);
        await wait(1100);
      }
    });
    _setOpen(true);
    await wait(1100);
    final family = _IpodStageState._families.firstWhere((f) => f.first.family == _model.family);
    // Souris sur le tiroir, comme quand on clique une pastille.
    _drawerHover(true);
    await wait(500);
    await run('teinte', () async {
      for (final m in family.length > 1 ? [...family.skip(1), family.first] : <IpodModel>[]) {
        stdout.writeln('[bench]   choix @${now() - t0}ms');
        _choose(m);
        await wait(700);
      }
    });
    await run('quitte-tiroir', () async {
      _drawerHover(false);
      await wait(1200);
    });
    await run('échange', () async {
      final other = start.family == 'mini' ? ipodModels.firstWhere((m) => m.family == 'nano4') : ipodModels.firstWhere((m) => m.family == 'mini');
      _pick(other);
      await wait(4500);
      _setOpen(true);
      await wait(1100);
      _pick(start);
      await wait(4500);
    });
    if (_model.id != start.id) _choose(start);
    widget.player.setVolume(volume);
    widget.player.pause();
    await wait(300);
    Settings.flush();
    for (final a in widget.player.accounts) {
      a.shutdown();
    }
    exit(0);
  }

  static int now() => Timeline.now ~/ 1000;
}
