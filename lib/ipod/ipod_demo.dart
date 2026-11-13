part of 'ipod.dart';

/// Démo filmée (LECTEUR_DEMO=fichier.json), sous Hyprland 0.57 (config en
/// Lua) : l'appli joue elle-même le rôle de l'utilisateur, étape par étape,
/// avec le vrai curseur.
///
/// Le fichier : {"go": chemin, "start": id du premier iPod, "steps": [...]}.
/// Étapes : {"coverflow": ms} navigue dans Cover Flow ; {"tint": id} prend
/// cet iPod dans le tiroir, par sa pastille ; {"colorShuffle": true} ;
/// {"next": true} ; {"wait": ms} ; {"exec": commande, "rect": [x, y, l, h]}
/// ou {"exec": …, "above": [l, h]} (fenêtre flottante, au-dessus de l'iPod).
/// La démo se prépare, écrit « [demo] prêt », puis attend que le fichier
/// « go » existe (l'enregistrement a commencé).
extension _Demo on _IpodStageState {
  Future<void> _demo() async {
    final cfg = jsonDecode(File(Platform.environment['LECTEUR_DEMO']!).readAsStringSync()) as Map<String, Object?>;
    final steps = (cfg['steps'] as List).cast<Map<String, Object?>>();
    Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
    IpodModel model(Object? id) => ipodModels.firstWhere((m) => m.id == id);
    final player = widget.player;

    while (player.loading || player.albums.isEmpty || !ipodLanded.value || _phase != _Swap.none) {
      await wait(200);
    }
    final start = model(cfg['start']);
    if (_model.id != start.id) _choose(start);
    // Les pochettes lues d'avance : Couleur au hasard part sans attendre.
    for (final s in steps) {
      if (s['tint'] case final String id) {
        if (model(id).coverColor case final c?) await player.albumsMatching(c);
      }
    }
    if (player.current == null && player.tracks.isNotEmpty) await player.playTracks(player.tracks, 0);
    await _demoHome();
    await wait(1500);
    stdout.writeln('[demo] prêt');
    final go = File(cfg['go'] as String);
    while (!go.existsSync()) {
      await wait(100);
    }
    final clock = Stopwatch()..start();
    await wait(1200);

    for (final s in steps) {
      stdout.writeln('[demo] ${s.keys.first} @${clock.elapsedMilliseconds}');
      if (s['coverflow'] case final num ms) {
        await _demoHome();
        await _demoGo(tr('Musique'));
        await _demoGo('Cover Flow');
        final end = clock.elapsedMilliseconds + ms;
        while (clock.elapsedMilliseconds < end) {
          _nav.scroll(1);
          await wait(260);
        }
        await wait(300);
      } else if (s['tint'] case final String id) {
        await _demoTint(model(id));
      } else if (s['colorShuffle'] == true) {
        await _demoHome();
        await _demoGo(tr('Couleur au hasard'));
        while (_nav.page is! NowPlayingPage) {
          await wait(50);
        }
      } else if (s['next'] == true) {
        WheelClick.instance.play();
        await player.next();
      } else if (s['wait'] case final num ms) {
        await wait(ms.round());
      } else if (s['exec'] case final String cmd) {
        await _demoExec(cmd, s);
      }
    }
    await wait(1500);
    stdout.writeln('[demo] fin @${clock.elapsedMilliseconds}');
  }

  /// Revient au menu principal.
  Future<void> _demoHome() async {
    while (_nav.stack.length > 1) {
      _nav.menu();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Descend jusqu'à [label] dans le menu affiché, puis entre.
  Future<void> _demoGo(String label) async {
    final page = _nav.page;
    if (page is! MenuPage) return;
    final at = page.entries.indexWhere((e) => e.label == label);
    if (at < 0) return;
    while (page.selected != at) {
      _nav.scroll(at > page.selected ? 1 : -1);
      WheelClick.instance.play();
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _nav.select();
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  /// Prend [m] dans le tiroir : le curseur va jusqu'à la poignée, le tiroir
  /// sort, le curseur passe sur l'emplacement puis sur la pastille.
  Future<void> _demoTint(IpodModel m) async {
    Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
    final dev = _rectOf(_deviceKeys[_model.id]);
    if (dev == null) return;
    await _glide(Offset(dev.right + 12, dev.top + math.min(70, dev.height * 0.25)), 800);
    _setHoverSide(1, true);
    await wait(450);
    _openSide(1); // le clic sur la poignée
    await wait(1200);
    await _revealSlot(m.family);
    await wait(250);
    final slot = _rectOf(_slotKeys[m.family]);
    if (slot != null) await _glide(slot.center, 650);
    await wait(500);
    final swatch = _swatchRect(m);
    if (swatch != null) await _glide(swatch.center, 450);
    await wait(300);
    _swatch(m, Future<void>.delayed(const Duration(milliseconds: 250)));
    if (m.family == _model.family) {
      // Même famille : il change de teinte, tiroir ouvert ; on le referme.
      await wait(900);
      _setOpen(false);
    }
    await wait(400);
    // (Presque rentré suffit : le ressort met encore des secondes à s'arrêter tout à fait.)
    while (_phase != _Swap.none || _swatchPending || _wantOpen || _open.value > 0.02) {
      await wait(50);
    }
    await _glide(Offset(dev.left - 90, dev.bottom - 40), 700);
  }

  /// La pastille de [m] dans le tiroir, dans le repère de la scène.
  Rect? _swatchRect(IpodModel m) {
    Rect? found;
    void visit(Element e) {
      if (found != null) return;
      final w = e.widget;
      if (w.runtimeType.toString() == '_Swatch' && ((w as dynamic).model as IpodModel).id == m.id) {
        final box = e.findRenderObject();
        final stage = _stageKey.currentContext?.findRenderObject();
        if (box is RenderBox && stage is RenderBox && box.attached && box.hasSize) {
          found = MatrixUtils.transformRect(box.getTransformTo(stage), Offset.zero & box.size);
        }
        return;
      }
      e.visitChildElements(visit);
    }

    (_stageKey.currentContext as Element?)?.visitChildElements(visit);
    return found;
  }

  /// Ouvre [cmd] dans une fenêtre flottante : en [rect] à l'écran, ou de la
  /// taille [above] juste au-dessus de l'iPod.
  Future<void> _demoExec(String cmd, Map<String, Object?> step) async {
    List<int> nums(Object? v) => [for (final n in v as List) (n as num).round()];
    late int x, y, w, h;
    if (step['rect'] != null) {
      [x, y, w, h] = nums(step['rect']);
    } else {
      final dev = _rectOf(_deviceKeys[_model.id]);
      if (dev == null) return;
      [w, h] = nums(step['above']);
      final origin = await _windowOrigin();
      x = (origin.dx + dev.center.dx - w / 2).round();
      y = math.max(30, (origin.dy + dev.top - h - 24).round());
    }
    final esc = cmd.replaceAll('"', r'\"');
    await _hypr('dispatch hl.dsp.exec_cmd("$esc", {float = true, size = "$w $h", move = "$x $y"})');
  }

  /// Le vrai curseur glisse jusqu'à [to] (repère de la scène) en [ms].
  Future<void> _glide(Offset to, int ms) async {
    final win = await _windowOrigin();
    final pos = jsonDecode(await _hypr('j/cursorpos')) as Map<String, Object?>;
    final from = Offset((pos['x'] as num).toDouble(), (pos['y'] as num).toDouble());
    final end = win + to;
    final steps = (ms / 16).round();
    for (var k = 1; k <= steps; k++) {
      final p = Offset.lerp(from, end, Curves.easeInOutCubic.transform(k / steps))!;
      await _hypr('dispatch hl.dsp.cursor.move({x=${p.dx.round()}, y=${p.dy.round()}})');
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  /// Coin haut gauche de la fenêtre de l'appli à l'écran.
  Future<Offset> _windowOrigin() async {
    final clients = (jsonDecode(await _hypr('j/clients')) as List).cast<Map<String, Object?>>();
    final me = clients.firstWhere((c) => c['class'] == 'dev.paulux.lecteur', orElse: () => const {'at': [0, 0]});
    final at = (me['at'] as List).cast<num>();
    return Offset(at[0].toDouble(), at[1].toDouble());
  }

  /// Une commande à Hyprland, par sa prise de contrôle ; renvoie sa réponse.
  /// (Hyprland 0.57, config en Lua : « dispatch » prend une expression Lua.)
  static Future<String> _hypr(String command) async {
    final env = Platform.environment;
    final path = '${env['XDG_RUNTIME_DIR']}/hypr/${env['HYPRLAND_INSTANCE_SIGNATURE']}/.socket.sock';
    final socket = await Socket.connect(InternetAddress(path, type: InternetAddressType.unix), 0);
    socket.write(command);
    await socket.flush();
    final out = await utf8.decodeStream(socket);
    socket.destroy();
    return out;
  }
}
