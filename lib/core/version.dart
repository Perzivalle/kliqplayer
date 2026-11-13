import 'dart:convert';

import 'package:http/http.dart' as http;

/// Version de l'appli, affichée dans Réglages › À propos. La même que dans
/// pubspec.yaml (un test le vérifie).
const appVersion = '0.7.0';

/// Page où télécharger la dernière version.
const releasesUrl = 'https://github.com/Perzivalle/kliqplayer/releases/latest';

/// Version publiée plus récente que celle-ci, une fois connue : Réglages
/// affiche alors une ligne « Mise à jour ».
String? newVersion;

/// Vrai si [latest] (« v0.7.0 », « 0.10 ») dépasse [current].
bool isNewer(String latest, String current) {
  List<int> parts(String v) => [for (final p in v.replaceFirst('v', '').split('.')) int.tryParse(p) ?? 0];
  final a = parts(latest), b = parts(current);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Demande à GitHub la dernière version publiée, au lancement. Hors ligne ou
/// réponse inattendue : on ne dit rien.
Future<void> checkForUpdate() async {
  try {
    final res = await http
        .get(Uri.parse('https://api.github.com/repos/Perzivalle/kliqplayer/releases/latest'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return;
    final tag = (jsonDecode(res.body) as Map)['tag_name'];
    if (tag is String && isNewer(tag, appVersion)) newVersion = tag.replaceFirst('v', '');
  } catch (_) {}
}
