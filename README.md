# myCard Konekt

Application mobile Flutter (Android / iOS) de la carte virtuelle **myCard Konekt 2.0**, powered by BestCash.

- Architecture et contrat d'API : [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Avancement : [`docs/TODO.md`](docs/TODO.md)

## Démarrer

```bash
flutter pub get
flutter run --dart-define-from-file=env/dev.json      # faux backend en mémoire
flutter run --dart-define-from-file=env/staging.json  # API de staging
```

En dev, toutes les requêtes HTTP sont servies par le faux backend (`lib/core/network/fake`), qui applique les règles de la maquette.

| Écran | Valeur de test |
|---|---|
| Invitation | n'importe quel code de 8 caractères (`00000000` ou `XXXX…` = refusé) |
| Connexion | identifiant de 6 à 20 chiffres + 4 chiffres (`0000` = refusé) |
| OTP / code de vérification | n'importe quel code (`000000` = incorrect) |
| Code secret | choisi à la première connexion (pas de suite ni de chiffres identiques) |

## Qualité

```bash
dart format -l 120 lib test
flutter analyze
flutter test
```
