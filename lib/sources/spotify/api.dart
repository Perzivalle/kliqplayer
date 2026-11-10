import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/player.dart' show NoticeException;
import '../../core/strings.dart';
import 'auth.dart';

/// Réponse d'erreur de l'API (statut, raison donnée par Spotify).
class SpotifyError implements NoticeException {
  const SpotifyError(this.status, this.reason, this.detail);

  final int status;

  /// « NO_ACTIVE_DEVICE », « PREMIUM_REQUIRED »…
  final String? reason;
  final String? detail;

  @override
  String get message => switch ((status, reason)) {
        (_, 'NO_ACTIVE_DEVICE') || (404, _) when reason != 'NOT_FOUND' => tr('Aucun appareil Spotify'),
        (_, 'PREMIUM_REQUIRED') => tr('Spotify Premium requis'),
        (403, _) => '${tr('Spotify : refusé')}${detail == null ? '' : ' ($detail)'}',
        (429, _) => tr('Spotify : trop de demandes'),
        _ => 'Spotify : $status${detail == null ? '' : ' $detail'}',
      };

  @override
  String toString() => message;
}

/// Appels à l'API Web de Spotify : jeton renouvelé au besoin, attente
/// quand Spotify demande de ralentir (429).
class SpotifyApi {
  SpotifyApi(this.auth, {http.Client? client}) : _http = client ?? http.Client();

  final SpotifyAuth auth;
  final http.Client _http;

  static const _base = 'https://api.spotify.com/v1';

  Uri _uri(String path, [Map<String, String>? query]) =>
      path.startsWith('http') ? Uri.parse(path) : Uri.parse('$_base$path').replace(queryParameters: query);

  /// Corps JSON de la réponse (null : pas de contenu, 204).
  Future<Map<String, Object?>?> get(String path, [Map<String, String>? query]) => _send('GET', _uri(path, query));

  Future<void> put(String path, {Map<String, String>? query, Object? body}) =>
      _send('PUT', _uri(path, query), body: body);

  Future<void> post(String path, {Map<String, String>? query, Object? body}) =>
      _send('POST', _uri(path, query), body: body);

  /// Tous les éléments d'une liste paginée (« items » / « next »).
  Future<List<Map<String, Object?>>> pages(String path, [Map<String, String>? query]) async {
    final all = <Map<String, Object?>>[];
    String? next = _uri(path, {'limit': '50', ...?query}).toString();
    while (next != null) {
      final page = await get(next);
      if (page == null) break;
      all.addAll(((page['items'] as List?) ?? const []).whereType<Map<String, Object?>>());
      next = page['next'] as String?;
    }
    return all;
  }

  Future<Map<String, Object?>?> _send(String method, Uri uri, {Object? body}) async {
    var renewed = false;
    for (var attempt = 0;; attempt++) {
      final token = await auth.accessToken(force: renewed);
      final req = http.Request(method, uri)..headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      } else if (method != 'GET') {
        req.headers['Content-Length'] = '0';
      }
      final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 15)));
      if (res.statusCode == 401 && !renewed) {
        renewed = true;
        continue;
      }
      if (res.statusCode == 429 && attempt < 3) {
        final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? 2;
        if (wait <= 10) {
          await Future<void>.delayed(Duration(seconds: wait));
          continue;
        }
      }
      if (res.statusCode >= 400) {
        String? reason, detail;
        try {
          final err = (jsonDecode(res.body) as Map)['error'];
          if (err is Map) {
            reason = err['reason'] as String?;
            detail = err['message'] as String?;
          }
        } catch (_) {}
        throw SpotifyError(res.statusCode, reason, detail);
      }
      if (res.body.isEmpty || res.statusCode == 204) return null;
      try {
        final data = jsonDecode(res.body);
        return data is Map<String, Object?> ? data : null;
      } on FormatException {
        return null; // (certaines commandes répondent un identifiant brut)
      }
    }
  }
}
