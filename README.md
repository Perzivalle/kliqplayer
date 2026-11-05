# Lecteur

Lecteur de musique local pour Linux (Flutter + media_kit) avec plusieurs
interfaces skeuomorphiques interchangeables (« skins »), animées par des
ressorts façon iOS.

- `lib/core/` : bibliothèque (`~/Music/Musique Ipod`, ou `$LECTEUR_MUSIC`) et moteur de lecture
- `lib/physics.dart` : ressorts amortis
- `lib/skins/` : les skins (platine vinyle ; iPod à venir)

## Lancer

```sh
flutter run -d linux          # développement, `r` pour recharger à chaud
flutter build linux --release # binaire dans build/linux/x64/release/bundle/
```

Clavier : Espace lecture/pause, ← → morceau, ↑ ↓ volume, Tab skin suivante, Échap quitter.
