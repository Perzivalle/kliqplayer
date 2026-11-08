import 'settings.dart';

/// Langues de l'interface. Le français sert de clé : tout texte affiché
/// passe par [tr], qui renvoie sa traduction (ou le français tel quel).
enum Lang {
  fr('Français'),
  en('English'),
  es('Español'),
  de('Deutsch');

  const Lang(this.nativeName);

  /// Nom de la langue dans cette langue (menu Réglages › Langue).
  final String nativeName;

  static Lang current = Lang.values.asNameMap()[Settings.getString('lang')] ?? Lang.fr;

  static void set(Lang lang) {
    current = lang;
    Settings.setString('lang', lang.name);
  }
}

/// Traduit [fr] dans la langue choisie.
String tr(String fr) {
  final lang = Lang.current;
  if (lang == Lang.fr) return fr;
  final t = _strings[fr];
  return t == null ? fr : t[lang.index - 1];
}

/// « 3 sur 12 ».
String trOf(int n, int total) => '$n ${tr('sur')} $total';

/// « 10 secondes ».
String trSeconds(int s) => '$s ${tr('secondes')}';

/// Anglais, espagnol, allemand.
const _strings = <String, List<String>>{
  // Menus
  'Lecteur': ['Player', 'Reproductor', 'Player'],
  'Musique': ['Music', 'Música', 'Musik'],
  'Réglages': ['Settings', 'Ajustes', 'Einstellungen'],
  'Morceau au hasard': ['Shuffle Songs', 'Canción aleatoria', 'Zufallstitel'],
  'En lecture': ['Now Playing', 'En reproducción', 'Aktueller Titel'],
  'Listes de lecture': ['Playlists', 'Listas', 'Playlists'],
  'Artistes': ['Artists', 'Artistas', 'Interpreten'],
  'Albums': ['Albums', 'Álbumes', 'Alben'],
  'Morceaux': ['Songs', 'Canciones', 'Titel'],
  'Tous': ['All', 'Todo', 'Alle'],
  'Ajouts récents': ['Recently Added', 'Añadido recientemente', 'Zuletzt hinzugefügt'],
  'Les plus écoutés': ['Top Played', 'Más escuchadas', 'Meistgespielt'],
  // Réglages
  'À propos': ['About', 'Información', 'Info'],
  'Bibliothèque': ['Library', 'Biblioteca', 'Mediathek'],
  'Lecture…': ['Reading…', 'Leyendo…', 'Lese…'],
  'Lecture aléatoire': ['Shuffle', 'Aleatorio', 'Zufällig'],
  'Répéter': ['Repeat', 'Repetir', 'Wiederholen'],
  'Non': ['Off', 'No', 'Aus'],
  'Un': ['One', 'Una', 'Einen'],
  'Rétroéclairage': ['Backlight', 'Retroiluminación', 'Beleuchtung'],
  'Allumé': ['On', 'Activada', 'Ein'],
  'Toujours allumé': ['Always On', 'Siempre activada', 'Immer ein'],
  'secondes': ['seconds', 'segundos', 'Sekunden'],
  'Clic': ['Clicker', 'Clic', 'Klicken'],
  'Haut-parleur': ['Speaker', 'Altavoz', 'Lautsprecher'],
  'Tonalité du clic': ['Click Tone', 'Tono del clic', 'Klickton'],
  'Très grave': ['Very Low', 'Muy grave', 'Sehr tief'],
  'Grave': ['Low', 'Grave', 'Tief'],
  'Normale': ['Normal', 'Normal', 'Normal'],
  'Aiguë': ['High', 'Agudo', 'Hoch'],
  'Très aiguë': ['Very High', 'Muy agudo', 'Sehr hoch'],
  'Touches': ['Keys', 'Teclas', 'Tasten'],
  'Langue': ['Language', 'Idioma', 'Sprache'],
  'Dossier actuel': ['Current Folder', 'Carpeta actual', 'Aktueller Ordner'],
  'Dossier personnel': ['Home Folder', 'Carpeta personal', 'Persönlicher Ordner'],
  'Disques': ['Drives', 'Discos', 'Laufwerke'],
  'Racine': ['Root', 'Raíz', 'Stammordner'],
  'Utiliser ce dossier': ['Use This Folder', 'Usar esta carpeta', 'Diesen Ordner verwenden'],
  'Listes': ['Playlists', 'Listas', 'Playlists'],
  // Écrans
  'Aucun album': ['No Albums', 'Ningún álbum', 'Keine Alben'],
  'Aucun élément': ['No Items', 'Ningún elemento', 'Keine Objekte'],
  'Aucun morceau': ['No Songs', 'Ninguna canción', 'Keine Titel'],
  'sur': ['of', 'de', 'von'],
  // Tiroir : modèles et teintes
  '1re génération': ['1st Generation', '1.ª generación', '1. Generation'],
  '2e génération': ['2nd Generation', '2.ª generación', '2. Generation'],
  '3e génération': ['3rd Generation', '3.ª generación', '3. Generation'],
  '4e génération': ['4th Generation', '4.ª generación', '4. Generation'],
  '5e génération': ['5th Generation', '5.ª generación', '5. Generation'],
  'Argent': ['Silver', 'Plata', 'Silber'],
  'Noir': ['Black', 'Negro', 'Schwarz'],
  'Blanc': ['White', 'Blanco', 'Weiß'],
  'Bleu': ['Blue', 'Azul', 'Blau'],
  'Vert': ['Green', 'Verde', 'Grün'],
  'Rouge': ['Red', 'Rojo', 'Rot'],
  'Rose': ['Pink', 'Rosa', 'Pink'],
  'Violet': ['Purple', 'Morado', 'Violett'],
  'Jaune': ['Yellow', 'Amarillo', 'Gelb'],
  'Orange': ['Orange', 'Naranja', 'Orange'],
  'Or': ['Gold', 'Oro', 'Gold'],
};
