# Konekt

Application mobile Flutter (Android / iOS) de la carte virtuelle **Konekt 2.0**, powered by BestCash.

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
de la maquette. Quand l'API sera branchée, passer `USE_FAKE_API` à `false` dans `env/staging.json` et `env/prod.json`.

Données de démo : titulaire Awa Houngbédji, carte Visa •••• (4 derniers chiffres saisis à la connexion), solde
152 400 FCFA, un mois d'historique, 3 notifications, 3 appareils, publicités. La session et le code secret sont
conservés entre deux lancements ; le solde et l'historique repartent de zéro à chaque redémarrage.

| Écran | Valeur de test |
|---|---|
| Invitation | n'importe quel code (enregistré comme code de parrainage marchand) |
| Connexion | identifiant de 6 à 20 chiffres + 4 chiffres (`0000` = refusé) ; WhatsApp est indisponible |
| Code reçu (connexion, PIN, opération) | n'importe quel code à 6 chiffres (`000000` = incorrect) |
| Code secret | à créer à la première connexion (pas de suite ni de chiffres identiques) |

Le faux backend suit le contrat de l'API CardConnect v2 ([`docs/GUIDE-INTEGRATION-KONEKT.md`](docs/GUIDE-INTEGRATION-KONEKT.md)).
Pour brancher la vraie API : `USE_FAKE_API=false`, `API_BASE_URL` (hôte, sans `/api/v1`) et `KONEKT_APP_ID` (fourni par l'équipe backend).

## Liens d'invitation

Un lien d'invitation ouvre l'app et enregistre le code marchand (envoyé à `login/confirm` comme
`merchantReferralCode`) : `konekt://invite?code=REF-XYZ123` ou `https://konekt.app/invite?code=REF-XYZ123`.
Au premier lancement, l'écran d'invitation s'affiche pré-rempli ; app déjà ouverte : toast « Code d'invitation
enregistré » ; personne connectée : le code est gardé pour la prochaine connexion (logique :
`lib/features/onboarding/data/invite_link_service.dart`).

```bash
adb shell am start -a android.intent.action.VIEW -d "konekt://invite?code=REF-XYZ123"
adb shell am start -a android.intent.action.VIEW -d "https://konekt.app/invite?code=REF-XYZ123"
xcrun simctl openurl booted "konekt://invite?code=REF-XYZ123"
```

Les liens `https` n'ouvrent l'app (sans passer par le navigateur) qu'une fois le domaine vérifié : publier
`https://konekt.app/.well-known/assetlinks.json` (package `bj.bestcash.konekt` + empreinte SHA-256 du certificat de
signature Play) et `https://konekt.app/.well-known/apple-app-site-association` (`applinks`, `TEAMID.bj.bestcash.konekt`,
chemin `/invite`), et activer la capacité *Associated Domains* sur l'App ID iOS (`ios/Runner/Runner.entitlements`).

## Icône et écran de démarrage

Sources dans `assets/branding/` (générées à partir des logos de `assets/images/`). Après modification :

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Qualité

```bash
dart format -l 120 lib test
flutter analyze
flutter test
```
