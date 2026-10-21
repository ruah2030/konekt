# myCard Konekt — Architecture Flutter

Document de référence pour développer l'application mobile **myCard Konekt 2.0** (powered by BestCash) à partir de la maquette `Card Konekt Material` (Flutter · Material 3).

> L'app consomme l'**API CardConnect v2** décrite dans [`GUIDE-INTEGRATION-KONEKT.md`](GUIDE-INTEGRATION-KONEKT.md), qui fait foi.
> Tant que l'API n'est pas branchée, un faux backend en mémoire reproduit ce contrat (section 6).

---

## 1. Choix techniques

| Sujet | Choix | Pourquoi |
|---|---|---|
| SDK | Flutter stable (3.x), Dart 3, Material 3 (`useMaterial3: true`) | La maquette est spécifiée en widgets M3 (NavigationBar, SegmentedButton, CarouselView, SliverAppBar.large…) |
| Gestion d'état | **Riverpod 3** (`flutter_riverpod`), sans génération de code | Injection de dépendances + état asynchrone (`AsyncValue`) + testable sans `BuildContext`. Adapté aux nombreux états chargement/erreur/expiré de l'app |
| Navigation | **go_router** (+ `go_router_builder` optionnel) | Redirections déclaratives selon l'état d'auth (splash → invitation → login → OTP → PIN → home), `StatefulShellRoute` pour les 4 onglets |
| HTTP | **dio** + intercepteurs | Auth (Bearer + refresh), `X-Request-Id`, `Idempotency-Key`, mapping d'erreurs, logs, retry |
| Modèles | Classes immuables écrites à la main + `fromJson`, `sealed class` Dart 3 | Pas de `build_runner` : build plus simple, aucun fichier généré à maintenir |
| Stockage sécurisé | `flutter_secure_storage` | Tokens, identifiant de session, id d'appareil |
| Préférences | `shared_preferences` | Premier lancement, solde masqué, préférences UI |
| Polices / icônes | `google_fonts` (Plus Jakarta Sans), `material_symbols_icons` (Rounded) | Conforme à la maquette |
| Vidéo | `video_player` | Vidéo d'onboarding sur l'écran Invitation (`onboarding-card.mp4`) |
| Notifications push | `firebase_messaging` + `flutter_local_notifications` | Résultat des opérations, nouvelle connexion, alertes carte |
| Sécurité écran | `FLAG_SECURE` natif via un canal de méthode (`core/security/screen_security.dart` + `MainActivity`) | Interdire capture d'écran sur l'affichage PAN/CVV et la saisie PIN |
| Infos appareil | `device_info_plus`, `package_info_plus` | En-têtes appareil, écran « Appareils connectés » |
| i18n / formats | `flutter_localizations` + `intl` (fr-FR) | Montants `152 400 FCFA`, dates « Hier à 14:05 » |
| Liens externes | `url_launcher` | Actions de type `url` des promotions, support |
| Qualité | `flutter_lints`/`very_good_analysis`, `mocktail`, `golden_toolkit` (ou `alchemist`) | Lint strict, tests unitaires/widgets/golden |
| Environnements | `--dart-define-from-file` (`env/dev.json`, `env/staging.json`, `env/prod.json`) | Base URL, faux backend on/off, logs selon l'environnement |
| Faux backend | `core/network/fake` : intercepteur Dio qui sert le contrat d'API en mémoire (`USE_FAKE_API=true` en dev) | Développer et tester toute l'app avant que l'API existe ; passer au vrai backend sans toucher au code des features |

Alternative acceptable : **flutter_bloc** à la place de Riverpod. Ne pas mélanger les deux.

Lancer l'app : `flutter run --dart-define-from-file=env/dev.json` (faux backend). Valeurs de test : voir l'en-tête de `lib/core/network/fake/fake_db.dart`.

---

## 2. Structure du projet (feature-first + couches)

```
lib/
├── main_dev.dart / main_staging.dart / main_prod.dart
├── app/
│   ├── app.dart                    # MaterialApp.router, thème, locale
│   ├── router/
│   │   ├── app_router.dart         # GoRouter + redirect selon AuthState
│   │   └── routes.dart             # Noms/chemins des routes
│   └── bootstrap.dart              # init (Firebase, storage, ProviderScope overrides)
├── core/
│   ├── config/env.dart             # baseUrl, flavor, USE_FAKE_API (dart-define)
│   ├── domain/                     # entités partagées : carte, transaction, opération, notification, promo, service
│   ├── providers/ticker.dart       # horloge 1 s pour les compte-à-rebours
│   ├── network/
│   │   ├── fake/                   # faux backend (FakeDb + handlers par domaine)
│   │   ├── dio_client.dart
│   │   ├── interceptors/
│   │   │   ├── auth_interceptor.dart         # Bearer + refresh token + 401
│   │   │   ├── request_id_interceptor.dart   # X-Request-Id, X-Device-Id, Accept-Language
│   │   │   ├── idempotency_interceptor.dart  # Idempotency-Key sur POST d'exécution
│   │   │   └── error_interceptor.dart        # DioException → ApiFailure
│   │   └── api_failure.dart        # code, message, ref (affiché « Réf. req_… »)
│   ├── storage/                    # secure_storage, prefs
│   ├── security/                   # screen protection, pin validator (weak PIN)
│   ├── utils/
│   │   ├── money_format.dart       # fmt / num (fr-FR, espace insécable, FCFA)
│   │   ├── relative_date.dart      # « Aujourd'hui à », « Hier à », « 12 oct. à »
│   │   ├── countdown.dart          # mm:ss (OTP, devis, affichage carte)
│   │   └── validators.dart         # msisdn, cardId (6–20 chiffres), last4, compteur
│   └── result.dart                 # Result<T> / Either
├── design_system/
│   ├── theme/
│   │   ├── app_theme.dart          # ThemeData M3
│   │   ├── color_scheme.dart       # ColorScheme Konekt
│   │   ├── app_colors.dart         # ThemeExtension : success, warning, tints par catégorie
│   │   └── typography.dart         # Plus Jakarta Sans
│   └── widgets/                    # Composants réutilisables (voir §4)
├── features/
│   ├── account/         # lectures partagées : titulaire, carte, solde, mouvements, notifications, promos
│   ├── shell/           # NavigationBar des 4 onglets
│   ├── onboarding/      # splash, invitation, obtenir une invitation, liste d'attente
│   ├── auth/            # login carte, OTP, session, déconnexion
│   ├── pin/             # création / changement / réinitialisation / saisie PIN paiement
│   ├── home/            # accueil, solde, actions rapides, catalogue
│   ├── services/        # formulaires de service, devis, traitement, reçu
│   ├── history/         # mouvements + mes opérations
│   ├── card/            # ma carte, statut, affichage sécurisé PAN/CVV
│   ├── notifications/   # liste, lu/non lu, push
│   ├── profile/         # profil, sécurité, préférences de canal, session
│   ├── devices/         # appareils connectés
│   ├── promotions/      # publicités (home / receipt / history)
│   └── system_status/   # bannière incident opérateur
└── l10n/                # app_fr.arb
```

Chaque feature suit le même découpage :

```
features/<feature>/
├── data/
│   ├── datasources/<feature>_api.dart        # appels dio
│   ├── dto/                                  # objets de requête/réponse (fromJson / toJson)
│   └── repositories/<feature>_repository_impl.dart
├── domain/
│   ├── entities/                             # modèles métier immuables
│   └── repositories/<feature>_repository.dart  # contrat abstrait
└── presentation/
    ├── providers/                            # Notifiers Riverpod
    ├── screens/
    └── widgets/
```

Règles : `presentation` ne connaît que `domain` ; `data` implémente `domain` ; aucun appel dio hors de `data/`. La couche `domain/usecases` est optionnelle — ne l'ajouter que si une logique métier est partagée entre plusieurs écrans.

---

## 3. Gestion d'état (Riverpod)

### 3.1 États globaux

| Provider | Type | Rôle |
|---|---|---|
| `authControllerProvider` | `Notifier<AuthState>` | `unknown / unauthenticated / authenticated` + `CardSession` (carte, titulaire, `hasPin`). Le routeur l'écoute pour ses redirections (création du PIN obligatoire si `hasPin == false`) |
| `cardSessionProvider` | `Provider<CardSession?>` | carte de session : `cardCustomerId` à renvoyer tel quel dans toutes les routes carte |
| `cardProvider` | `AsyncNotifier<CardInfo>` | `GET /cards` (ou `details` pour une carte externe) : statut `Active / Inactive / PreActive / LostOrStolen / Deactivated`, gamme, émetteur |
| `balanceProvider` | `FutureProvider<num>` | solde lu en direct chez l'émetteur ; erreur 400 si la carte est suspendue ou bloquée |
| `hideBalanceProvider` | `Notifier<bool>` | persisté en prefs |
| `unreadCountProvider` | `FutureProvider<int>` | `GET /notifications/unread-count`, rafraîchi chaque minute (push non branché côté API) |
| `platformStatusProvider` | `FutureProvider` | `GET /status` : bannière d'incident si `overall != operational` |
| `serviceOffersProvider` | `FutureProvider` | `GET /catalog/services` : services ouverts ou grisés avec motif |
| `promotionsProvider.family(placement)` | `FutureProvider` | publicités (⚠️ hors API, voir 6.4) |

### 3.2 États de flux (scopés à l'écran, `autoDispose`)

- **Invitation** : `idle → checking → ok | error` ; formatage `XXXX-XXXX`.
- **Login** : validation locale (chiffres uniquement, détection de la lettre « O », 6–20 chiffres, 4 chiffres), canal `SMS | WHATSAPP | EMAIL` (WhatsApp désactivable par config).
- **Code (écran unique, 6 modes)** : `otp`, `pinVerify`, `pinOld`, `pinNew`, `pinConfirm`, `payPin` avec un contexte `login | setup | change | reset | pay`. Modéliser comme une machine à états :
  ```dart
  sealed class CodeStep { const CodeStep(); }
  final class OtpStep extends CodeStep { const OtpStep(this.expiresAt, this.sendsLeft); final DateTime expiresAt; final int sendsLeft; }
  final class PinVerifyStep extends CodeStep { const PinVerifyStep(this.flow); final PinFlow flow; }
  final class PinNewStep extends CodeStep { const PinNewStep(this.flow); final PinFlow flow; }
  final class PinConfirmStep extends CodeStep { const PinConfirmStep(this.flow, this.firstEntry); final PinFlow flow; final String firstEntry; }
  // + PinOldStep, PayPinStep(quoteId)
  ```
  Dans l'implémentation, l'OTP, le parcours PIN (setup/change/reset) et le PIN de paiement sont trois écrans distincts qui partagent le même widget de saisie (`CodeEntryView` : PinDots + pavé numérique).
  Le premier PIN (`firstEntry`) ne quitte jamais la mémoire du notifier ; il n'est ni loggé ni persisté.
- **Paiement** (`paymentFlowProvider`) : `form → quoting → quote(live|expired) → pin → processing(step) → receipt(success|failed|processing)`. Le devis porte `quoteId`, `expiresAt` (10 min), `checks[]`, `warnings[]`.
- **Affichage sécurisé** : `loading → shown(expiresAt 60 s) → expired`.

### 3.3 Timers

Un seul `tickerProvider` (`StreamProvider<DateTime>` toutes les 1 s, `autoDispose`) consommé par les compte-à-rebours (OTP, devis, affichage carte, verrouillage PIN, rotation des pubs). Toujours calculer « restant = expiresAt − now » (heure serveur si fournie) plutôt que décrémenter un compteur.

### 3.4 Feedback UI

- `SnackBar` : messages courts (« Nouveau code envoyé. », « Préférence enregistrée. »).
- `AlertDialog` (rayon 28) : confirmations sensibles (suspendre, réactiver, perte/vol, déconnexion d'appareil, tout déconnecter).
- Bloc erreur inline : `message` + `code · Réf. <requestId>` (support).

---

## 4. Design system

**ColorScheme** (extrait de la maquette) :

| Rôle | Hex |
|---|---|
| primary / onPrimary | `#140A72` / `#FFFFFF` |
| secondary / secondaryContainer | `#F0B23A` / `#FFF4D6` |
| tertiary | `#3B63F0` |
| primaryContainer | `#EEF0FF` |
| error / errorContainer | `#DC2B2B` / `#FDECEC` |
| success (extension) | `#1FA54E` |
| warning (extension) | `#F97316` |
| surface / surfaceContainer | `#FFFFFF` / `#F1F2F8` |
| onSurfaceVariant / outline | `#64748B` / `#94A3B8` |
| Indicateur NavigationBar | `#FCE68A` |
| Fond splash | dégradé `#140A72 → #0B1233` |

**Formes** : boutons `StadiumBorder`, champs `filled` (`fillColor #F6F7FB`, rayon 18), cartes rayon 16, dialogues rayon 28.
**Police** : Plus Jakarta Sans 400–800. **Icônes** : Material Symbols Rounded (rempli pour l'onglet actif).

**Composants à créer** (`design_system/widgets`) :
`KonektPrimaryButton`, `KonektTextField`, `PinDots` (6 cases), `NumericKeypad` (1–9, 0, effacer), `ErrorBlock` (message + code + réf.), `StatusPill` (statut carte / opération), `MoneyText`, `AmountRow` (libellé/valeur pour devis & reçu), `TxTile` (icône teintée + montant signé + sous-titre), `ServiceTile` (catalogue), `QuickAction`, `PromoCard` (thèmes `navy / gold / mint`, fermeture, CTA), `PromoCarousel` (points indicateurs, rotation), `IncidentBanner`, `CountdownChip`, `ProcessingStepper`, `ConfirmDialog`, `VirtualCardView` (VISA, •••• last4), `EmptyState`.

---

## 5. Navigation (go_router)

```
/splash
/invite
/invite/request          (Obtenir une invitation + liste d'attente)
/login
/code                    (extra: CodeStep)
StatefulShellRoute (NavigationBar) :
  /home
  /history               (onglets Mouvements | Mes opérations)
  /card
     /card/display       (affichage sécurisé PAN/CVV — plein écran)
  /profile
     /profile/devices
/notifications
/service/:type           (transfer | payout | topup | airtime | data | elec | cash | tv)
/service/:type/quote
/payment/processing
/receipt/:operationId
```

Redirections globales (`redirect` lié à `authControllerProvider`) :
- splash ≈ 2,9 s puis : premier lancement → `/invite`, sinon → `/login` (ou `/home` si session valide).
- OTP validé et pas de PIN → flux `setup` (étapes 1/3 → 3/3) avant `/home`.
- 401 non récupérable → purge de la session → `/login`.
- Statut carte ≠ `Active` → les services/affichage sont bloqués avec le message adapté au statut.

Retour arrière depuis `/code` selon le contexte : `login → /login`, `pay → devis`, `setup → /login`, `change/reset → /profile` ; `pinConfirm → pinNew`.

---

## 6. Consommation de l'API

Référence complète : [`GUIDE-INTEGRATION-KONEKT.md`](GUIDE-INTEGRATION-KONEKT.md).

### 6.1 Client (`core/network`)

- Base : `<API_BASE_URL>/api/v1` ; les repositories utilisent des chemins relatifs (`/cards/balance/$id`).
- En-têtes : `Authorization: Bearer <sessionToken>` (sauf routes publiques), `X-Request-Id`, `Accept-Language: fr`, `User-Agent: CardKonekt/<version> (<OS>)`.
- **401** (guide §1.6) : `SESSION_EXPIRED` → un seul `POST /auth/customer/refresh` à la fois (`QueuedInterceptor`), les deux jetons remplacés, puis un rejeu ; échec → déconnexion. `UNAUTHENTICATED` « Jeton non reconnu pour cette route » → bug d'intégration, **pas** de déconnexion.
- **Idempotence** : pas d'en-tête dédié ; `reference` / `requestId` dans le corps, UUID v4 neuf par tentative de paiement, réutilisé seulement pour rejouer la même tentative. Aucun paiement n'est relancé automatiquement.
- Délai de réception 75 s : les confirmations de paiement appellent l'émetteur pendant la requête.

### 6.2 Erreurs

Format unique : `{ statusCode, code, message, details, timestamp, path, requestId }`. `ApiFailure` expose `code` (logique), `message` (affiché tel quel), `ref` (« Réf. » pour le support) et `fieldErrors(champ)` pour `VALIDATION_FAILED`.

### 6.3 Correspondance écrans → routes

| Écran | Routes |
|---|---|
| Démarrage | session stockée ? → `GET /cards` (test) ; `GET /status` (bannière) |
| Connexion | `GET /auth/customer/channels` → `POST /auth/customer/login/init` → `POST /auth/customer/login/confirm` (avec `device` et `merchantReferralCode` = code d'invitation) |
| Code secret | `pin/setup/request` → `POST /auth/customer/pin` ; `pin/change` ; `pin/reset/request` → `pin/reset/confirm` |
| Accueil | `GET /cards`, `GET /cards/balance/:id`, `GET /notifications/unread-count`, `GET /catalog/services`, `GET /status` |
| Historique | `GET /cards/transactions/:id` (relevé émetteur, par période) ; `GET /operations` (paginé) |
| Reçu | `GET /cards/operations/:id` ou `GET /operations/:id` |
| Envoyer | `POST /cards/transfer/initiate` → `POST /cards/operations/:id/execute` (PIN) ou `/cards/operations/confirm` (OTP) |
| Retirer vers Mobile Money | `GET /external-wallets/channels` → `POST /cards/to-mobile-money/initiate` → execute / confirm |
| Recharger ma carte | catalogue `wallet-to-card` : `POST /catalog/quote` → `POST /catalog/confirm` → validation téléphone ou code B-MO (`/commerce/operations/:id/funding/confirm`) |
| Crédit, forfait, électricité, TV, retrait guichet | `GET /catalog/lookup/...` → `POST /catalog/quote` → `POST /catalog/confirm` (PIN) → suivi |
| Ma carte | `PATCH /cards/status` ; `POST /cards/display/authorize` → WebView sur `displayUrl` (60 s, usage unique) |
| Notifications | `GET /notifications`, `POST /notifications/:id/read`, `POST /notifications/read-all`, `DELETE /notifications/:id` |
| Profil / sécurité | `GET`/`PATCH /auth/customer/preferences`, `GET`/`DELETE /auth/customer/devices`, `logout`, `logout-all` |

### 6.4 Écarts entre la maquette et l'API

- **Invitation** : aucune route de vérification. Le code est conservé localement et envoyé comme `merchantReferralCode` à `login/confirm`.
- **Liste d'attente** et **publicités** : aucune route dans l'API. Servies uniquement par le faux backend (`POST /waitlist`, `GET /promotions`) ; à arbitrer avec le produit/backend.
- **Relevé émetteur** : pas de sens débit/crédit ; l'app le déduit de l'évolution de `runningBalance` (à confirmer avec l'équipe API).
- **Push** : non implémenté côté API ; la pastille interroge `unread-count`.

### 6.5 Faux backend (`core/network/fake`)

Un intercepteur Dio sert le contrat en mémoire quand `USE_FAKE_API=true` (valeur actuelle de tous les environnements). `FakeDb` stocke l'état au format JSON de l'API ; un handler par domaine reproduit chemins, corps acceptés (champ inconnu → 400 comme l'API), réponses, codes et messages d'erreur. Passer au vrai backend = `USE_FAKE_API=false` + `API_BASE_URL` + `KONEKT_APP_ID`.

---

## 7. Sécurité

- PIN et OTP : saisis via le pavé interne (pas de clavier système), jamais loggés ni persistés ; effacés de l'état après usage.
- Vérification du PIN côté serveur uniquement ; le compteur d'essais et le verrouillage (5 essais, 15 min) viennent de l'API. La détection de PIN faible côté app n'est qu'un confort.
- Affichage PAN/CVV : l'app ne reçoit qu'une URL à usage unique (60 s) chargée dans une WebView détruite à la fermeture ; les données vont du coffre VGS à l'écran sans passer par l'app.
- `FLAG_SECURE`/protection capture sur : affichage carte, saisie PIN, devis/reçu sensibles. Masquage dans le sélecteur d'apps.
- Tokens dans `flutter_secure_storage` (Keychain / Keystore). Session unique par carte.
- Déconnexion à l'inactivité (à définir avec le métier) et à la révocation d'appareil.
- Obfuscation release (`--obfuscate --split-debug-info`), détection root/jailbreak à arbitrer.
- Logs réseau désactivés en prod ; ne jamais logger les corps de requêtes paiement/PIN.

---

## 8. Tests & CI

- **Unitaires** : formatteurs (montant, date relative, mm:ss), validateurs, détection PIN faible, mapping `ApiFailure`, notifiers (machine à états du code, flux de paiement, expiration devis).
- **Widgets/golden** : chaque écran dans ses états (chargement, erreur, carte suspendue/pré-active/bloquée, pas de transaction, devis expiré…).
- **Intégration** : parcours login → OTP → création PIN → envoi → reçu, avec un faux backend (`http_mock_adapter` ou serveur mock).
- **CI (GitHub Actions, `.github/workflows/ci.yml`)** : `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test --coverage`, build APK de dev.
- Helper de test : `test/helpers/test_app.dart` (`TestEnv`) — faux backend sans latence, stockage en mémoire, app complète ou écran isolé.
