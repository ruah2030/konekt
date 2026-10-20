# myCard Konekt — Architecture Flutter

Document de référence pour développer l'application mobile **myCard Konekt 2.0** (powered by BestCash) à partir de la maquette `Card Konekt Material` (Flutter · Material 3).

> Les endpoints d'API ci-dessous sont **déduits de la maquette** (codes d'erreur, statuts, délais, champs). Ils doivent être validés avec l'équipe backend avant implémentation — voir la section 6.

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
| Sécurité écran | `screen_protector` (ou `FLAG_SECURE` natif) | Interdire capture d'écran sur l'affichage PAN/CVV et la saisie PIN |
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
| `authControllerProvider` | `AsyncNotifier<AuthState>` | `unknown / firstLaunch / unauthenticated / otpPending / needsPinSetup / authenticated`. Le router écoute ce provider pour ses redirections |
| `sessionProvider` | `Notifier<Session?>` | carte de session (id, last4), titulaire (prénom, initiales) |
| `cardProvider` | `AsyncNotifier<Card>` | statut (`Active / Inactive / PreActive / LostOrStolen`), gamme, émetteur. Conditionne l'accès aux services |
| `balanceProvider` | `AsyncNotifier<Balance>` | solde, rafraîchi après chaque opération réussie et en pull-to-refresh |
| `hideBalanceProvider` | `Notifier<bool>` | persisté en prefs |
| `unreadCountProvider` | dérivé de `notificationsProvider` | badge cloche |
| `systemStatusProvider` | `FutureProvider` | bannière « Incident chez un opérateur » (login + accueil) |
| `promotionsProvider.family(placement)` | `FutureProvider` | pubs filtrées/triées par `priority`, moins celles fermées |

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

### 6.1 Client

- `Dio(BaseOptions(baseUrl: Env.apiBaseUrl, connectTimeout: 10s, receiveTimeout: 30s))`.
- En-têtes systématiques : `Authorization: Bearer …`, `X-Request-Id` (UUID, affiché en « Réf. » dans les erreurs), `X-Device-Id` (UUID persisté), `X-App-Version`, `Accept-Language: fr-BJ`.
- `Idempotency-Key` (= `quoteId` ou UUID) sur l'exécution d'un paiement : **ne jamais rejouer automatiquement** un POST d'exécution, même en cas de timeout ; on passe en statut `PROCESSING` et on interroge l'opération.
- Refresh token : file d'attente des requêtes pendant le refresh (`QueuedInterceptor`).
- Pas de retry automatique sur POST ; retry exponentiel limité sur GET réseau.
- Certificate pinning recommandé en prod (application financière).

### 6.2 Format d'erreur attendu

```json
{ "error": { "code": "INSUFFICIENT_FUNDS", "message": "…", "requestId": "req_01J…", "details": {} } }
```

`ApiFailure` mappe ces codes (vus dans la maquette) :

| Code | Usage |
|---|---|
| `VALIDATION_FAILED` | Champ manquant/format, montant hors bornes, PIN de confirmation différent |
| `REQUEST_REJECTED` | Lettre « O » dans l'id, carte bénéficiaire = sa carte, numéro invalide, trop d'OTP, nouveau PIN = ancien |
| `UNAUTHENTICATED` | Identifiants incorrects, OTP incorrect/expiré |
| `PIN_CODE_INVALID` | Code de vérification incorrect |
| `PIN_TOO_WEAK` | PIN répétitif ou suite |
| `FORBIDDEN` | PIN de paiement faux, verrouillage 15 min |
| `DAILY_AMOUNT_LIMIT` | Plafond 500 000 FCFA / 24 h |
| `INSUFFICIENT_FUNDS` | Solde insuffisant (frais compris) |
| réseau / 5xx | Message générique + bouton réessayer |

Les messages affichés viennent de l'API quand ils existent ; sinon d'une table de messages FR côté app.

### 6.3 Endpoints à confirmer avec le backend

**Onboarding / Auth**
- `POST /v1/invitations/verify` `{code}` → `{inviterName}`
- `POST /v1/waitlist` `{msisdn}` → `{position}`
- `POST /v1/auth/login` `{cardId, last4, channel}` → `{challengeId, maskedDestination, expiresAt, sendsLeft}`
- `POST /v1/auth/otp/resend` `{challengeId}`
- `POST /v1/auth/otp/verify` `{challengeId, code, device}` → `{accessToken, refreshToken, hasPin}`
- `POST /v1/auth/refresh`, `POST /v1/auth/logout`, `POST /v1/auth/logout-all`

**PIN**
- `POST /v1/pin/verification` (envoi du code SMS+e-mail) / `POST /v1/pin/verification/confirm`
- `POST /v1/pin` (création), `PUT /v1/pin` `{oldPin, newPin}`, `POST /v1/pin/reset` (lève le verrouillage)

**Carte & solde**
- `GET /v1/me` (titulaire), `GET /v1/card` (statut, gamme, émetteur, last4)
- `GET /v1/card/balance`
- `POST /v1/card/suspend`, `POST /v1/card/reactivate`, `POST /v1/card/lost`
- `POST /v1/card/sensitive-display` → URL/jeton à usage unique valable 60 s (idéalement rendu par l'émetteur, PAN/CVV jamais stockés)

**Services & paiements**
- `GET /v1/services` (catalogue, disponibilité — ex. TV « Bientôt »/indisponible)
- `GET /v1/services/data/plans?msisdn=` (forfaits à prix imposé)
- `GET /v1/services/airtime/operator?msisdn=` (détection opérateur, bornes)
- `POST /v1/quotes` `{service, amount?, planId?, target?, msisdn?, operator?, meter?, deliveryChannel?, contact?}` → `{quoteId, amount, fee, total, expiresAt, checks[], warnings[], beneficiary}`
- `POST /v1/operations` `{quoteId, pin}` + `Idempotency-Key` → `{operationId, status}`
- `GET /v1/operations/{id}` (polling 2–3 s tant que `PROCESSING`, avec `step` : `QUOTED / AUTHORIZED / AWAITING_USER_APPROVAL / PROCESSING / SUCCESS / FAILED`) — ou mise à jour via push/WebSocket
- `GET /v1/operations?cursor=` (Mes opérations, avec `reason` si échec et `extra[]` : code électricité, code de retrait)

**Historique**
- `GET /v1/card/transactions?from=&cursor=` (relevé émetteur, dernier mois, avec solde après opération)

**Notifications / profil / appareils**
- `GET /v1/notifications`, `POST /v1/notifications/{id}/read`, `POST /v1/notifications/read-all`
- `POST /v1/devices/push-token`
- `GET /v1/preferences`, `PUT /v1/preferences` `{channel: SMS|EMAIL|WHATSAPP|null}`
- `GET /v1/devices`, `DELETE /v1/devices/{id}`

**Contenu**
- `GET /v1/promotions?placement=home|receipt|history` → `{id, placement, priority, eyebrow, title, body, cta, action{type: url|service, target}, theme}`
- `GET /v1/status` → incidents opérateurs

### 6.4 Repository type

```dart
abstract interface class PaymentRepository {
  Future<Result<Quote>> createQuote(QuoteRequest req);
  Future<Result<Operation>> execute({required String quoteId, required String pin});
  Stream<Operation> watch(String operationId); // polling ou push
}
```

Les DTO restent dans `data/`, convertis en entités `domain` (`toEntity()`). Les montants sont des `int` en FCFA (pas de `double`).

---

## 7. Sécurité

- PIN et OTP : saisis via le pavé interne (pas de clavier système), jamais loggés ni persistés ; effacés de l'état après usage.
- Vérification du PIN côté serveur uniquement ; le compteur d'essais et le verrouillage (5 essais, 15 min) viennent de l'API. La détection de PIN faible côté app n'est qu'un confort.
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
