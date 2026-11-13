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
  'Couleur au hasard': ['Color Shuffle', 'Aleatorio por color', 'Farb-Zufall'],
  'En lecture': ['Now Playing', 'En reproducción', 'Aktueller Titel'],
  'Listes de lecture': ['Playlists', 'Listas', 'Playlists'],
  'Artistes': ['Artists', 'Artistas', 'Interpreten'],
  'Albums': ['Albums', 'Álbumes', 'Alben'],
  'Morceaux': ['Songs', 'Canciones', 'Titel'],
  'morceau': ['song', 'canción', 'Titel'],
  'morceaux': ['songs', 'canciones', 'Titel'],
  'Tous': ['All', 'Todo', 'Alle'],
  'Titres likés': ['Liked Songs', 'Canciones que te gustan', 'Lieblingssongs'],
  'Ajouts récents': ['Recently Added', 'Añadido recientemente', 'Zuletzt hinzugefügt'],
  'Les plus écoutés': ['Top Played', 'Más escuchadas', 'Meistgespielt'],
  'Genres': ['Genres', 'Géneros', 'Genres'],
  'Recherche': ['Search', 'Buscar', 'Suchen'],
  'Choisir des lettres': ['Pick letters', 'Elige letras', 'Buchstaben wählen'],
  // Réglages
  'À propos': ['About', 'Información', 'Info'],
  'Bibliothèque': ['Library', 'Biblioteca', 'Mediathek'],
  'Lecture…': ['Reading…', 'Leyendo…', 'Lese…'],
  'Lecture aléatoire': ['Shuffle', 'Aleatorio', 'Zufällig'],
  'Répéter': ['Repeat', 'Repetir', 'Wiederholen'],
  'Non': ['Off', 'No', 'Aus'],
  'Oui': ['On', 'Sí', 'Ein'],
  'Premier plan': ['Always on Top', 'Siempre visible', 'Im Vordergrund'],
  'Mise à jour': ['Update', 'Actualización', 'Update'],
  'Position': ['Position', 'Posición', 'Position'],
  'Libre': ['Free', 'Libre', 'Frei'],
  'Fixe': ['Fixed', 'Fija', 'Fest'],
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
  // Sources en ligne (Spotify…)
  'Chargement…': ['Loading…', 'Cargando…', 'Wird geladen…'],
  'Actualiser': ['Refresh', 'Actualizar', 'Aktualisieren'],
  'Pas de connexion': ['No Connection', 'Sin conexión', 'Keine Verbindung'],
  'Lire la liste': ['Play Playlist', 'Reproducir lista', 'Playlist abspielen'],
  'Connexion…': ['Connecting…', 'Conectando…', 'Verbinden…'],
  'navigateur': ['browser', 'navegador', 'Browser'],
  'Se connecter': ['Sign In', 'Iniciar sesión', 'Anmelden'],
  'Se déconnecter': ['Sign Out', 'Cerrar sesión', 'Abmelden'],
  'Utiliser %s': ['Use %s', 'Usar %s', '%s verwenden'],
  'Compte': ['Account', 'Cuenta', 'Konto'],
  'Créer ma clé': ['Create My Key', 'Crear mi clave', 'Schlüssel erstellen'],
  'guide': ['guide', 'guía', 'Anleitung'],
  'Coller la clé': ['Paste Key', 'Pegar clave', 'Schlüssel einfügen'],
  'Changer de clé': ['Change Key', 'Cambiar clave', 'Schlüssel ändern'],
  'Clé': ['Key', 'Clave', 'Schlüssel'],
  'Pas de clé copiée': ['No key copied', 'Ninguna clave copiada', 'Kein Schlüssel kopiert'],
  'Clé Spotify requise': ['Spotify key required', 'Clave de Spotify necesaria', 'Spotify-Schlüssel nötig'],
  'Aucun appareil Spotify': ['No Spotify Device', 'Ningún dispositivo Spotify', 'Kein Spotify-Gerät'],
  'Ouvrez Spotify sur un appareil': ['Open Spotify on a Device', 'Abre Spotify en un dispositivo', 'Spotify auf einem Gerät öffnen'],
  'Appli Spotify introuvable': ['Spotify app not found', 'App de Spotify no encontrada', 'Spotify-App nicht gefunden'],
  'Spotify : non connecté': ['Spotify: Not Signed In', 'Spotify: sin sesión', 'Spotify: nicht angemeldet'],
  'Spotify : reconnectez-vous': ['Spotify: Sign In Again', 'Spotify: vuelve a iniciar sesión', 'Spotify: erneut anmelden'],
  'Spotify Premium requis': ['Spotify Premium Required', 'Se requiere Spotify Premium', 'Spotify Premium erforderlich'],
  'Spotify : refusé': ['Spotify: Refused', 'Spotify: rechazado', 'Spotify: abgelehnt'],
  'Spotify : trop de demandes': ['Spotify: Too Many Requests', 'Spotify: demasiadas solicitudes', 'Spotify: zu viele Anfragen'],
  'Port %s occupé': ['Port %s in Use', 'Puerto %s ocupado', 'Port %s belegt'],
  'Connecté à Spotify': ['Connected to Spotify', 'Conectado a Spotify', 'Mit Spotify verbunden'],
  'Connexion annulée': ['Sign-in Cancelled', 'Inicio de sesión cancelado', 'Anmeldung abgebrochen'],
  'Connexion échouée': ['Sign-in Failed', 'Error al iniciar sesión', 'Anmeldung fehlgeschlagen'],
  'Vous pouvez fermer cet onglet.': ['You can close this tab.', 'Puedes cerrar esta pestaña.', 'Sie können diesen Tab schließen.'],
  'Navigateur introuvable': ['No Browser Found', 'Navegador no encontrado', 'Kein Browser gefunden'],
  'Artiste inconnu': ['Unknown Artist', 'Artista desconocido', 'Unbekannter Interpret'],
  'Lecteur intégré : échec': ['Built-in Player Failed', 'Error del reproductor integrado', 'Integrierter Player fehlgeschlagen'],
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
  'Gris sidéral': ['Space Gray', 'Gris espacial', 'Space Grau'],
  'Bleu (2015)': ['Blue (2015)', 'Azul (2015)', 'Blau (2015)'],
  'Rose (2015)': ['Pink (2015)', 'Rosa (2015)', 'Pink (2015)'],
};
