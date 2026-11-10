import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../core/paths.dart';
import '../../core/player.dart' show NoticeException;
import '../../core/strings.dart';

/// Connexion à Spotify : « Authorization Code » avec PKCE, sans secret
/// (rien à cacher dans l'appli). Le navigateur revient sur un petit serveur
/// local, le temps de la connexion. Les jetons sont gardés dans
/// ~/.config/lecteur/spotify.json, lisible par l'utilisateur seul.
class SpotifyAuth {
  SpotifyAuth({required this.clientId, http.Client? client}) : _http = client ?? http.Client() {
    _read();
  }

  final String clientId;
  final http.Client _http;

  /// Doit être déclarée telle quelle dans l'appli Spotify (tableau de bord
  /// développeur) : Spotify refuse « localhost », et le port fixe évite les
  /// soucis du tableau de bord avec les adresses sans port.
  static const port = 43819;
  static const redirectUri = 'http://127.0.0.1:$port/callback';

  static const scopes = [
    'user-library-read',
    'playlist-read-private',
    'playlist-read-collaborative',
    'user-read-private',
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-currently-playing',
  ];

  File get _file => File(joinPath(configDir(), joinPath('lecteur', 'spotify.json')));

  String? _access, _refresh;
  DateTime _expires = DateTime(0);

  /// Un compte est connecté (on a de quoi renouveler l'accès).
  bool get connected => _refresh != null;

  /// Jetons donnés à la main (tests).
  void debugUseTokens({required String access, required String refresh, Duration valid = const Duration(hours: 1)}) {
    _access = access;
    _refresh = refresh;
    _expires = DateTime.now().add(valid);
  }

  void _read() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final data = jsonDecode(_file.readAsStringSync()) as Map<String, Object?>;
      if (data['client'] != clientId) return; // jetons d'une autre appli
      _refresh = data['refresh'] as String?;
      _access = data['access'] as String?;
      _expires = DateTime.tryParse(data['expires'] as String? ?? '') ?? DateTime(0);
    } catch (_) {}
  }

  Future<void> _save() => writePrivate(
        _file,
        jsonEncode({'client': clientId, 'refresh': _refresh, 'access': _access, 'expires': _expires.toIso8601String()}),
      );

  /// Jeton d'accès valable (renouvelé s'il expire dans moins d'une minute,
  /// ou si [force]).
  Future<String> accessToken({bool force = false}) async {
    if (!connected) throw NoticeException(tr('Spotify : non connecté'));
    if (!force && _access != null && DateTime.now().isBefore(_expires.subtract(const Duration(minutes: 1)))) {
      return _access!;
    }
    return _refreshing ??= _renew().whenComplete(() => _refreshing = null);
  }

  Future<String>? _refreshing;

  Future<String> _renew() async {
    final res = await _http.post(Uri.parse('https://accounts.spotify.com/api/token'), body: {
      'grant_type': 'refresh_token',
      'refresh_token': _refresh!,
      'client_id': clientId,
    });
    if (res.statusCode == 400 || res.statusCode == 401) {
      // Accès retiré (mot de passe changé, appli révoquée) : il faut se
      // reconnecter.
      await logout();
      throw NoticeException(tr('Spotify : reconnectez-vous'));
    }
    if (res.statusCode != 200) throw NoticeException('Spotify : ${res.statusCode}');
    _take(jsonDecode(res.body) as Map<String, Object?>);
    await _save();
    return _access!;
  }

  void _take(Map<String, Object?> token) {
    _access = token['access_token'] as String;
    // PKCE : chaque renouvellement peut donner un nouveau jeton de
    // renouvellement.
    _refresh = (token['refresh_token'] as String?) ?? _refresh;
    _expires = DateTime.now().add(Duration(seconds: (token['expires_in'] as num?)?.toInt() ?? 3600));
  }

  /// Ouvre la page de connexion de Spotify (par [open], le navigateur) et
  /// attend le retour.
  Future<void> login(Future<void> Function(Uri url) open) async {
    final random = Random.secure();
    String randomString(int n) {
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
      return List.generate(n, (_) => chars[random.nextInt(chars.length)]).join();
    }

    final verifier = randomString(64);
    final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = randomString(16);

    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      throw NoticeException(tr('Port %s occupé').replaceFirst('%s', '$port'));
    }
    try {
      await open(Uri.https('accounts.spotify.com', '/authorize', {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
        'scope': scopes.join(' '),
      }));
      String? code, error;
      await for (final req in server.timeout(const Duration(minutes: 5))) {
        if (req.uri.path != '/callback') {
          req.response.statusCode = 404;
          await req.response.close();
          continue;
        }
        final q = req.uri.queryParameters;
        if (q['state'] == state) {
          code = q['code'];
          error = q['error'];
        }
        req.response
          ..headers.contentType = ContentType.html
          ..write('<!doctype html><meta charset="utf-8"><title>TinyPod</title>'
              '<body style="font-family:sans-serif;text-align:center;margin-top:20vh">'
              '<h2>${code != null ? tr('Connecté à Spotify') : tr('Connexion annulée')}</h2>'
              '<p>${tr('Vous pouvez fermer cet onglet.')}</p>');
        await req.response.close();
        break;
      }
      if (code == null) throw NoticeException(error == 'access_denied' ? tr('Connexion annulée') : tr('Connexion échouée'));
      final res = await _http.post(Uri.parse('https://accounts.spotify.com/api/token'), body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': clientId,
        'code_verifier': verifier,
      });
      if (res.statusCode != 200) throw NoticeException('Spotify : ${res.statusCode} ${res.body}');
      _take(jsonDecode(res.body) as Map<String, Object?>);
      await _save();
    } on TimeoutException {
      throw NoticeException(tr('Connexion annulée'));
    } finally {
      await server.close(force: true);
    }
  }

  Future<void> logout() async {
    _access = _refresh = null;
    _expires = DateTime(0);
    try {
      await _file.delete();
    } catch (_) {}
  }
}
