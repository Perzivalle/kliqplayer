# Lecteur

Lecteur de musique local pour Linux (Flutter + media_kit) en forme de
baladeur à molette, qui flotte seul au milieu d'une fenêtre transparente.
Animations par ressorts façon iOS.

- `lib/core/` : bibliothèque (`~/Music/Musique Ipod`, ou `$LECTEUR_MUSIC`), moteur de lecture, préférences
- `lib/physics.dart` : ressorts amortis
- `lib/ipod/` : le baladeur
  - `ipod.dart` : la scène (appareil + tiroir) et l'appareil
  - `nav.dart` : menus (Musique › Artistes / Albums / Morceaux, En lecture)
  - `wheel.dart`, `click.dart` : molette tactile et son clic
  - `model.dart`, `classic.dart`, `mini.dart` : les modèles et leurs teintes
  - `drawer.dart` : le tiroir de choix du modèle

## Lancer

```sh
flutter run -d linux          # développement, `r` pour recharger à chaud (pas `R` : media_kit plante)
flutter build linux --release # binaire dans build/linux/x64/release/bundle/
flutter test                  # dont les captures de référence (test/goldens/)
```

## Utilisation

- Molette : glisser en cercle (ou molette de la souris) pour défiler ; MENU pour revenir, centre pour valider,
  ⏯ lecture/pause, ⏮ ⏭ morceau précédent/suivant (appui long : reculer/avancer dans le morceau).
- En lecture : la molette règle le volume ; clic au centre pour avancer dans le morceau à la molette.
- Tiroir : approcher la souris du bord droit (ou touche T) ; un clic sur un appareil le prend en main, les
  pastilles changent la teinte. Le choix est retenu dans `~/.config/lecteur/settings.json`.

Clavier : ↑ ↓ défiler, Entrée valider, Retour arrière MENU, ← → morceau (appui long : avancer/reculer),
Espace lecture/pause, T tiroir, Échap / Q quitter.
