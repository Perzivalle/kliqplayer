# Lecteur

Lecteur de musique local pour Linux (Flutter + media_kit) en forme d'iPod à molette, qui flotte seul
dans une fenêtre transparente. Huit modèles, de la 1re génération au nano 4G, dessinés d'après les vrais,
avec des animations par ressorts façon iOS.

## Utilisation

- **Molette** : glisser en cercle (ou molette de la souris) pour défiler ; MENU pour revenir, centre pour
  valider, ⏯ lecture/pause, ⏮ ⏭ morceau précédent/suivant (appui long : reculer/avancer dans le morceau).
- **En lecture** : la molette règle le volume ; clic au centre pour avancer dans le morceau à la molette.
- **Menus** : Musique (Cover Flow sur les écrans couleur, Listes de lecture, Artistes, Albums, Morceaux),
  Réglages (Bibliothèque, Lecture aléatoire, Répéter, Rétroéclairage, Clic), Morceau au hasard, En lecture.
- **Tiroir** : approcher la souris d'un coin du haut de l'iPod fait apparaître une poignée ; un clic (ou la
  tirer) fait sortir le tiroir de ce côté. Un clic sur un appareil le débranche, le range et branche l'autre ;
  au survol, les pastilles montrent ses teintes et le teintent, un clic sur l'une le prend dans cette teinte.
- **Déplacer** : attraper l'iPod n'importe où sauf sur la molette (et les boutons) déplace la fenêtre.

Clavier : ↑ ↓ ou j k défiler, Entrée ou l valider, Retour arrière ou h MENU, ← → morceau (appui long :
avancer/reculer), Espace lecture/pause, T tiroir, Échap / Q quitter.

La musique vient du dossier choisi dans Réglages › Bibliothèque (par défaut `~/Music/Musique Ipod` ;
`$LECTEUR_MUSIC` a le dernier mot). Formats : mp3, flac, ogg, opus, m4a, aac, wav ; listes `.m3u`.
Les préférences et le nombre d'écoutes sont dans `~/.config/lecteur/settings.json`.

## Lancer

```sh
flutter run -d linux          # développement : `r` pour recharger à chaud (pas `R` : media_kit plante)
flutter build linux --release # binaire dans build/linux/x64/release/bundle/
flutter test                  # dont les captures de référence (test/goldens/)
```

Fluidité : `LECTEUR_FPS=1 LECTEUR_BENCH=1 build/linux/x64/profile/bundle/lecteur` (après
`flutter build linux --profile`) ouvre et referme le tiroir, affiche les temps d'image puis quitte.

## Code

- `lib/core/` : bibliothèque (parcours des tags et pochettes), moteur de lecture, préférences
- `lib/physics.dart` : ressorts amortis
- `lib/ipod/`
  - `ipod.dart` : la scène (appareil, tiroir, poignées, câble) et l'appareil
  - `nav.dart` : menus et navigation ; `screen.dart` : l'écran (transitions, rétroéclairage) ;
    `coverflow.dart` : Cover Flow
  - `look.dart` : ce qui distingue un écran ; `model.dart` : ce qui distingue un modèle
  - `classic.dart`, `nano.dart` (nano 3G), `nanos.dart` (nano 2G et 4G), `mini.dart`,
    `vintage.dart` (1re, 3e et 4e générations)
  - `wheel.dart`, `click.dart` : molette tactile et son clic ; `jack.dart` : la prise et le câble
  - `drawer.dart` : le tiroir de choix du modèle
