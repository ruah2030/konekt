# myCard Konekt

Application mobile Flutter (Android / iOS) de la carte virtuelle **myCard Konekt 2.0**, powered by BestCash.

- Architecture et contrat d'API : [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Avancement : [`docs/TODO.md`](docs/TODO.md)

## Démarrer

```bash
flutter pub get
flutter run                                       # données de démo (par défaut)
flutter run --dart-define-from-file=env/dev.json
```

**Pour l'instant, l'app tourne uniquement sur des données de démo** : tous les environnements (`env/*.json`) ont
`USE_FAKE_API=true`. Aucune requête ne sort du téléphone ; le faux backend (`lib/core/network/fake`) applique les règles
de la maquette. Quand l'API sera prête, passer `USE_FAKE_API` à `false` dans `env/staging.json` et `env/prod.json`.

Données de démo : titulaire Awa Houngbédji, carte Visa •••• (4 derniers chiffres saisis à la connexion), solde
152 400 FCFA, un mois d'historique, 3 notifications, 3 appareils, publicités. La session et le code secret sont
conservés entre deux lancements ; le solde et l'historique repartent de zéro à chaque redémarrage.

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
