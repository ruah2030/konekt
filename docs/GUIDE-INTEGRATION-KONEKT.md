<!-- docs/GUIDE-INTEGRATION-KONEKT.md -->

# Guide d'intégration de l'application Card Konekt (KONEKT) sur l'API CardConnect v2

> **À qui s'adresse ce guide ?** À un développeur, même débutant, qui doit construire l'application
> libre-service **Card Konekt** (mobile ou web) en s'appuyant sur l'API **CardConnect v2** (`ccapi`).
> Il décrit **toutes** les ressources que l'application peut consommer, comment les enchaîner et
> comment réagir à chaque erreur.
>
> **Source de vérité :** ce guide a été établi en lisant le code de `ccapi` (branche
> `claude/determined-tesla-9dyfbp`, octobre 2026). Les noms de champs sont ceux du code. En cas de
> doute, la documentation Swagger de l'environnement (`/docs`, quand elle est ouverte) fait foi.

---

## Sommaire

- [Partie 1 — Prise en main](#partie-1--prise-en-main)
- [Partie 2 — Authentification du porteur](#partie-2--authentification-du-porteur)
- [Partie 3 — Parcours de l'application écran par écran](#partie-3--parcours-de-lapplication-écran-par-écran)
- [Partie 4 — Cartes et affichage sécurisé](#partie-4--cartes-et-affichage-sécurisé)
- [Partie 5 — Catalogue et paiements en libre-service](#partie-5--catalogue-et-paiements-en-libre-service)
- [Partie 6 — Historique, notifications, Mobile Money, disponibilité, géographie, KYC](#partie-6--historique-notifications-mobile-money-disponibilité-géographie-kyc)
- [Partie 7 — Recettes de code prêtes à l'emploi](#partie-7--recettes-de-code-prêtes-à-lemploi)
- [Partie 8 — Checklist avant mise en production](#partie-8--checklist-avant-mise-en-production)
- [Partie 9 — Points ouverts côté API (à suivre avec l'équipe backend)](#partie-9--points-ouverts-côté-api)

---

# Partie 1 — Prise en main

## 1.1 Le modèle en une minute

| Notion | Ce qu'il faut retenir |
|---|---|
| **Porteur** | L'utilisateur de Konekt. Il n'a **ni compte ni mot de passe** : il se connecte avec **sa carte** (identifiant émetteur + 4 derniers chiffres) et un **code reçu par message**. |
| **Session = une carte** | Une session ne porte que sur la carte utilisée pour se connecter. Un porteur de deux cartes ouvre deux sessions. |
| **Code secret (PIN)** | 6 chiffres, défini à la première connexion. Il confirme **chaque mouvement d'argent**. |
| **Marchand de session** | Le marchand qui « parraine » la session (code d'invitation, sinon marchand par défaut de la région). Il perçoit les commissions. L'app n'a rien à gérer, sauf transmettre le code d'invitation s'il existe. |
| **Devis puis confirmation** | Tout paiement se fait en deux temps : un **devis** (prix figé, valable 10 min) puis une **confirmation** (avec le PIN). |
| **Émetteur** | GTP / Onafriq, qui détient réellement la carte. Solde, mouvements et détails sont lus chez lui en direct. |

## 1.2 URL de base et environnements

```
https://<hôte-api>/api/v1/<route>
```

- Toutes les routes sont préfixées par **`/api/v1`**. Exceptions : `GET /health`, `/docs` (Swagger) et
  les fichiers statiques `/public/...`.
- L'hôte dépend de l'environnement (développement, staging, production). Mettez-le en **variable de
  configuration** de l'app (ex. `API_BASE_URL`) et ne l'écrivez jamais en dur.
- **Web uniquement :** l'origine de votre site doit figurer dans `CORS_ALLOWED_ORIGINS` côté API.
  L'application mobile n'est pas concernée par le CORS.

> ⚠️ **Anciennes routes v1.** L'ancienne route `POST /api/v1/secure-card/login/init` **n'existe plus**
> (elle renvoie 404, comme vu dans les journaux de production). La connexion se fait désormais sur
> `POST /api/v1/auth/customer/login/init` (voir Partie 2).

## 1.3 En-têtes HTTP

| En-tête | Quand | Valeur |
|---|---|---|
| `Content-Type` | Toute requête avec corps | `application/json` |
| `Authorization` | Toute route protégée | `Bearer <sessionToken>`. Le mot `Bearer` suivi d'**un espace** est obligatoire. Sans lui, le jeton est ignoré. |
| `Accept-Language` | Recommandé | `fr` (il entre dans l'empreinte de l'appareil du journal de sécurité). |
| `User-Agent` | Recommandé | Nom et version de l'app, ex. `CardKonekt/1.4.0 (Android 14)`. |
| `X-Request-Id` | Facultatif | Identifiant unique par requête. Sinon le serveur en génère un, renvoyé dans `requestId` des erreurs. |

**Pas d'en-tête `Idempotency-Key`.** L'idempotence passe par des champs du corps (`reference`,
`requestId`) décrits route par route.

## 1.4 Conventions de données

- **Montants** : nombres en **XOF** (franc CFA), ex. `144030` ou `720.15`. Ne les envoyez jamais en
  chaîne. Côté affichage, formatez-les vous-même : `144 030 F CFA`.
- **Saisie des décimales** : si l'utilisateur tape `0,5`, convertissez la virgule en point **avant**
  l'envoi (`"0,5".replace(',', '.')`). Le serveur refuse `"0,5"`.
- **Dates** : chaînes ISO 8601 en UTC (`2026-10-15T09:14:22.418Z`). Convertissez-les dans le fuseau
  du téléphone pour l'affichage. Les filtres de période attendent `YYYY-MM-DD`, et `startDate` doit
  être ≤ `endDate`.
- **Identifiant de carte (`cardCustomerId`)** : **chiffres uniquement** (6 à 20). Les espaces sont
  tolérés et retirés. La **lettre O** saisie à la place du **zéro** est refusée par un 400 explicite.
  Dans les champs de saisie, utilisez un **clavier numérique** et retirez les espaces.
- **Champs inconnus interdits** : l'API rejette (400 `VALIDATION_FAILED`, `property X should not
  exist`) tout champ non prévu dans un corps **ou** dans les paramètres de requête d'un DTO.
  N'envoyez que les champs documentés.

## 1.5 Format unique des erreurs

Toute erreur a **exactement** cette forme :

```json
{
  "statusCode": 400,
  "code": "VALIDATION_FAILED",
  "message": "Certains champs sont invalides. Le détail figure dans « details ».",
  "details": { "last4Digits": ["Quatre chiffres attendus."] },
  "timestamp": "2026-10-15T09:14:22.418Z",
  "path": "/api/v1/auth/customer/login/init",
  "requestId": "req_01J8XQZ4K2"
}
```

| Champ | Usage dans l'app |
|---|---|
| `code` | **Clé machine stable.** Branchez la logique dessus : `switch (error.code)`. |
| `message` | **Texte pour l'humain**, en français, affichable tel quel. Il peut changer : ne le comparez jamais. |
| `details` | Uniquement pour `VALIDATION_FAILED` : messages par champ, à placer sous le bon champ du formulaire. |
| `requestId` | À afficher discrètement (« Réf. : … ») et à joindre au support. |

**Codes génériques** (communs à toutes les routes) :

| `code` | HTTP | Réaction recommandée |
|---|---|---|
| `VALIDATION_FAILED` | 400 | Afficher `details` sous les champs. |
| `REQUEST_REJECTED` | 4xx | Afficher `message`. |
| `UNAUTHENTICATED` | 401 | Voir le tableau 401 ci-dessous. |
| `SESSION_EXPIRED` | 401 | Renouveler la session (`/auth/customer/refresh`), puis rejouer l'appel une fois. |
| `FORBIDDEN` | 403 | Afficher `message` (refus métier : carte bloquée, PIN faux…). |
| `NOT_FOUND` | 404 | Afficher `message`. |
| `CONFLICT` | 409 | Afficher `message`. |
| `RATE_LIMITED` | 429 | « Trop de tentatives, patientez une minute. » |
| `PROVIDER_UNAVAILABLE` | 502/503/504 | « Service partenaire momentanément indisponible, réessayez. » |
| `INTERNAL_ERROR` | 500 | « Erreur inattendue » + `requestId`. |

Les routes ajoutent leurs **codes métier** (`PIN_TOO_WEAK`, `QUOTE_EXPIRED`, `DAILY_AMOUNT_LIMIT`, …),
documentés dans chaque partie.

## 1.6 401 : quand déconnecter, quand ne pas déconnecter

| Situation | HTTP / `code` | Que faire |
|---|---|---|
| Jeton de session expiré | 401 `SESSION_EXPIRED` | Appeler `/auth/customer/refresh`, puis rejouer. |
| Session fermée côté serveur (déconnexion, appareil révoqué) | 401 `SESSION_EXPIRED` (« Session fermée ou expirée ») | Tenter un refresh ; s'il échoue → écran de connexion. |
| Jeton invalide ou corrompu | 401 `UNAUTHENTICATED` | Écran de connexion. |
| **Jeton porteur valide, mais la route n'est pas ouverte aux porteurs** | 401 `UNAUTHENTICATED`, message « Jeton non reconnu pour cette route… » | **Ne PAS déconnecter.** C'est un bug d'intégration : vous appelez une route qui n'est pas pour Konekt (ou la route KYC/OTP visiteur **avec** un jeton : appelez-la **sans** `Authorization`). |
| `/auth/customer/refresh` renvoie 401 | 401 | Jeton de renouvellement usé, expiré ou rejoué → écran de connexion. |

## 1.7 Limites de fréquence et plafonds

| Portée | Limite | Erreur |
|---|---|---|
| `GET /auth/customer/channels` | 30 / min / adresse IP | 429 |
| `POST /auth/customer/login/init` | 10 / min / IP **et** 3 codes / heure / carte (réglable) | 429, ou 400 « Trop de demandes de code. Réessayez dans une heure. » |
| `POST /auth/customer/login/confirm` | 20 / min / IP | 429 |
| `POST /auth/customer/refresh` | 60 / min | 429 |
| `pin/setup/request`, `pin/reset/request` | 5 / min | 429, ou 400 `PIN_CODE_RATE_LIMITED` |
| `/commerce/operations/{id}/funding/*` | 30 / min / porteur | 429 |
| Devis porteur | 60 / heure glissante | 403 `QUOTE_RATE_LIMIT` |
| Opérations porteur | 15 / 24 h glissantes | 403 `DAILY_OPERATION_LIMIT` |
| Montant porteur | 500 000 XOF / 24 h glissantes | 403 `DAILY_AMOUNT_LIMIT` |
| Carte (émetteur GTP) | Dépôt max 2 000 000 XOF ; retrait 900 000 XOF / jour | Refus de l'émetteur |

Les valeurs « réglables » se changent dans la configuration de la plateforme (admin) sans nouvelle
version de l'app. **N'écrivez pas ces chiffres en dur** dans les messages : affichez le `message`
du serveur.

---

# Partie 2 — Authentification du porteur

Contrôleur : `src/auth/customer-auth.controller.ts`, préfixe **`/api/v1/auth/customer`**.

## 2.1 Vue d'ensemble

```
┌──────────────────────┐   GET  /auth/customer/channels           (canaux SMS/WhatsApp/Email dispo)
│ Écran « Ma carte »   │
│ id carte + 4 chiffres│── POST /auth/customer/login/init         → code envoyé (masque du contact)
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Écran « Code reçu »  │── POST /auth/customer/login/confirm      → tokens + card + holder + hasPin
└──────────┬───────────┘
           ▼  hasPin == false ?
┌──────────────────────┐── POST /auth/customer/pin/setup/request  → code de vérification envoyé
│ Écran « Créer PIN »  │── POST /auth/customer/pin                → PIN défini
└──────────┬───────────┘
           ▼
     Accueil (Partie 3)          … session expirée → POST /auth/customer/refresh
```

## 2.2 `GET /auth/customer/channels` — Canaux disponibles pour recevoir le code

- **Auth :** aucune. **Limite :** 30 / min.
- **But :** savoir quels canaux proposer **avant** d'afficher le choix au porteur. Un canal dont
  l'opérateur est en panne disparaît (`available: false`).

**Réponse 200**
```json
{
  "success": true,
  "channels": [
    { "channel": "SMS", "available": true },
    { "channel": "WHATSAPP", "available": false },
    { "channel": "EMAIL", "available": true }
  ],
  "defaultChannel": "SMS"
}
```
**À faire :** ne proposez que les canaux `available: true` et présélectionnez `defaultChannel`.

## 2.3 `POST /auth/customer/login/init` — Demander un code de connexion

- **Auth :** aucune. **Limites :** 10 / min / IP, 3 codes / heure / carte.

**Corps**
| Champ | Type | Obligatoire | Règle |
|---|---|---|---|
| `cardCustomerId` | string | oui | Identifiant de la carte chez l'émetteur (chiffres). |
| `last4Digits` | string | oui | Exactement 4 chiffres (`^\d{4}$`). |
| `doubleAuthMethod` | `"SMS"` \| `"WHATSAPP"` \| `"EMAIL"` | non | Canal souhaité. Absent : le serveur choisit et peut envoyer sur **plusieurs** canaux. |
| `appId` | string | oui | Identifiant de l'application, fourni par l'équipe backend (variable serveur `BESTCASH_SECURE_CARD_APP_ID`). Mauvaise valeur → 401 « Application non reconnue. » |

```json
{ "cardCustomerId": "121436474", "last4Digits": "4589", "doubleAuthMethod": "SMS", "appId": "<APP_ID_KONEKT>" }
```

**Réponse 200**
```json
{
  "success": true,
  "message": "Code envoyé.",
  "channelsUsed": ["SMS"],
  "maskedContacts": ["+229****456"],
  "expiryMinutes": 5
}
```
Affichez « Code envoyé au +229****456, valable 5 minutes ».

**Erreurs**
| HTTP | Cause | Afficher |
|---|---|---|
| 400 `VALIDATION_FAILED` | Format des champs | `details` |
| 400 | Trop de codes demandés pour cette carte (3 / h) ; ou aucun canal disponible | `message` |
| 401 | Informations de connexion invalides. **Volontairement vague** : carte inconnue, mauvais 4 chiffres et carte bloquée donnent tous la même réponse. | « Identifiant ou chiffres incorrects. » |
| 429 | Trop d'appels depuis cette adresse | « Patientez une minute. » |

## 2.4 `POST /auth/customer/login/confirm` — Valider le code et ouvrir la session

- **Auth :** aucune. **Limite :** 20 / min. **3 essais** par code, comptés même pour des requêtes simultanées.

**Corps**
| Champ | Type | Obligatoire | Règle |
|---|---|---|---|
| `cardCustomerId` | string | oui | Le même qu'à l'étape `init`. |
| `last4Digits` | string | oui | Le même qu'à l'étape `init`. |
| `appId` | string | oui | Le même qu'à l'étape `init`. |
| `code` | string | oui | 6 chiffres (`^\d{6}$`). |
| `merchantReferralCode` | string | non | ≤ 40 car. Code d'invitation du marchand (lien de parrainage, QR…). Un code inconnu **ne bloque pas** la connexion. |
| `countryCode` | string | non | 2 lettres (ex. `BJ`). Sert seulement si le dossier n'a pas de pays. |
| `stateRegionCode` | string | non | ≤ 10 car. (ex. `LI`). |
| `device` | objet | **fortement recommandé** | Voir ci-dessous. **Sans lui, pas de notifications push ni de liste d'appareils fiable** (et `devices/push-token` répondra 403). |

`device` :
| Champ | Type | Obligatoire | Règle |
|---|---|---|---|
| `type` | enum `DeviceType` | oui | ex. `ANDROID`, `IOS`, `WEB` (voir l'enum dans Swagger). |
| `fcmToken` | string | non | ≤ 512 car. Jeton Firebase, s'il est déjà disponible. |
| `label` | string | non | ≤ 80 car., ex. `Samsung Galaxy A14`. |

```json
{
  "cardCustomerId": "121436474",
  "last4Digits": "4589",
  "appId": "<APP_ID_KONEKT>",
  "code": "482910",
  "merchantReferralCode": "REF-XYZ123",
  "device": { "type": "ANDROID", "fcmToken": "fcm_dGhp...", "label": "Samsung Galaxy A14" }
}
```

**Réponse 200**
```json
{
  "success": true,
  "message": "Connexion réussie.",
  "tokens": {
    "sessionToken": "eyJhbGciOiJIUzI1NiIs...",
    "refreshToken": "kJ8x2mQ7pL4nR9vT...",
    "sessionId": "clcs1234567890",
    "expiresIn": 1800,
    "refreshExpiresIn": 2592000
  },
  "card": { "cardCustomerId": "121436474", "last4Digits": "4589", "status": "Active" },
  "holder": { "firstName": "Kossi", "lastName": "Adjovi" },
  "hasPin": false,
  "isExternalCard": false
}
```

| Champ | Ce que l'app en fait |
|---|---|
| `tokens.sessionToken` | Mis dans `Authorization: Bearer …` de **chaque** appel. Durée : `expiresIn` secondes (30 min par défaut). |
| `tokens.refreshToken` | Stocké de façon **sécurisée** (Keychain iOS / EncryptedSharedPreferences Android / jamais en `localStorage` en clair sur le web). Durée : 30 jours. **Usage unique** (voir 2.5). |
| `card.status` | `Active`, `PreActive` (pas encore activée) ou `Inactive` (suspendue). Adaptez l'accueil : une carte `Inactive` ne peut ni payer ni recevoir. |
| `hasPin` | **`false` → écran de création du PIN obligatoire avant tout le reste.** |
| `isExternalCard` | `true` : carte émise hors plateforme. Le porteur utilise l'app mais **ne peut pas acheter de nouvelle carte**. Masquez cette offre. |

**Erreurs**
| HTTP | Cause | Afficher |
|---|---|---|
| 401 | Code incorrect, expiré ou déjà utilisé (3 essais max) | `message`. Au-delà, proposer « Renvoyer un code » (refaire `login/init`). |
| 403 | Carte perdue/volée ou désactivée : le motif est cette fois **explicite** | `message` + bouton « Contacter le support ». |
| 403 | « Le service est momentanément indisponible dans votre région. » (aucun marchand de session configuré) | `message`. |

## 2.5 `POST /auth/customer/refresh` — Renouveler la session

- **Auth :** aucune (le corps porte le jeton). **Limite :** 60 / min.
- **Corps :** `{ "refreshToken": "kJ8x2mQ7pL4nR9vT..." }`
- **Réponse 200 :** `{ "success": true, "sessionToken": "...", "refreshToken": "...", "sessionId": "...", "expiresIn": 1800, "refreshExpiresIn": 2592000 }`

> ⚠️ **RÈGLE D'OR : chaque refresh invalide l'ancien `refreshToken`.**
> 1. Remplacez **immédiatement** les deux jetons stockés par les nouveaux.
> 2. **Ne lancez jamais deux refresh en parallèle.** Si cinq requêtes reçoivent un 401 en même temps,
>    une seule doit appeler `/refresh` ; les autres attendent son résultat (voir la recette 7.2).
> 3. Présenter deux fois le même `refreshToken` est pris pour une **copie frauduleuse** : **toutes**
>    les sessions de cette connexion sont fermées et le porteur doit se reconnecter.

**Erreurs :** 401 (jeton invalide, expiré, rejoué) → écran de connexion. 403 : carte bloquée depuis
la connexion → écran d'information + support.

## 2.6 Déconnexion

| Route | Auth | Effet | Réponse |
|---|---|---|---|
| `POST /auth/customer/logout` | Bearer | Ferme la session **courante**, avec effet immédiat. | `{ "success": true, "message": "Déconnexion effectuée." }` (ou « Cette session était déjà fermée. ») |
| `POST /auth/customer/logout-all` | Bearer | Ferme **toutes** les sessions sur tous les appareils (téléphone perdu). | `{ "success": true, "closed": 3 }` |

Après l'appel, effacez les jetons stockés **même si la requête échoue** (réseau coupé).

## 2.7 Code secret (PIN)

**Règles d'un PIN :** exactement **6 chiffres**. Refusés : six fois le même chiffre (`111111`) et
les suites consécutives (`123456`, `987654`, `345678`…) → 400 `PIN_TOO_WEAK`. Vérifiez ces règles
**dans l'app** avant l'envoi, pour un retour immédiat.

**Verrouillage :** 5 PIN faux (réglable) → compte verrouillé **15 minutes** (réglable). Pendant le
verrou, toute opération est refusée (403 « Trop de codes erronés. Réessayez dans N minute(s)… »).
La **réinitialisation** du PIN lève le verrou.

### 2.7.1 Créer le PIN (première connexion, `hasPin: false`)

1. `POST /auth/customer/pin/setup/request` (Bearer, sans corps, 5 / min). Un code de vérification
   part sur les contacts du dossier.
   ```json
   { "success": true, "channelsUsed": ["SMS","EMAIL"], "maskedContacts": ["+**********456","pi***@example.com"], "expiryMinutes": 5 }
   ```
   Erreurs : 400 `PIN_ALREADY_DEFINED` (déjà défini → aller à l'accueil) ; 400 `PIN_CODE_RATE_LIMITED`.
2. `POST /auth/customer/pin` (Bearer, 10 / min). Réponse **201**.
   ```json
   { "pin": "482915", "code": "604218" }
   ```
   | Erreur (400) | Signification | Que faire |
   |---|---|---|
   | `VALIDATION_FAILED` (`details.code`) | Code de vérification absent ou mal formé | Redemander les 6 chiffres reçus. |
   | `PIN_TOO_WEAK` | PIN trop simple. **Le code reçu reste valable.** | Faire choisir un autre PIN et renvoyer **le même** `code`. |
   | `PIN_ALREADY_DEFINED` | Déjà défini | Aller à l'accueil. |
   | `PIN_CODE_INVALID` | Code reçu faux (`details.attemptsLeft`) | « Code incorrect, N essai(s) restant(s). » |
   | `PIN_CODE_EXPIRED` / `PIN_CODE_EXHAUSTED` / `PIN_CODE_ALREADY_USED` | Code inutilisable | Relancer l'étape 1. |

   > Ici, un **401** concerne toujours la **session**, jamais le code reçu.

### 2.7.2 Changer le PIN

`POST /auth/customer/pin/change` (Bearer) — `{ "currentPin": "482915", "pin": "730519" }`
- 200 `{ "success": true, "message": "Code secret modifié." }`
- 400 : nouveau PIN trop simple ou identique à l'ancien. 403 : ancien PIN faux (compte comme un essai) ou compte verrouillé.

### 2.7.3 PIN oublié

1. `POST /auth/customer/pin/reset/request` (Bearer, sans corps), même réponse que `setup/request`.
2. `POST /auth/customer/pin/reset/confirm` (Bearer) — `{ "code": "604218", "pin": "730519" }` →
   200 `{ "success": true, "message": "Code secret réinitialisé." }`. Mêmes erreurs qu'en 2.7.1.
   Cette étape lève aussi le verrouillage.

## 2.8 Appareils connectés

| Route | Description |
|---|---|
| `GET /auth/customer/devices` | Liste des appareils : `deviceId`, `type`, `label`, **`isCurrent`** (appareil courant, à marquer « Cet appareil »), `hasActiveSession`, `notificationsEnabled`, `lastSeenAt`, `lastIpAddress`, `firstSeenAt`. |
| `DELETE /auth/customer/devices/:deviceId` | Déconnecte cet appareil, avec effet immédiat. Réponse `{ "success": true, "deviceId": "...", "closedSessions": 1, "message": "Appareil déconnecté..." }`. 404 si l'appareil n'existe pas ou n'est pas à vous. Demandez une confirmation si `isCurrent` est vrai. |
| `POST /auth/customer/devices/push-token` | `{ "fcmToken": "..." }` (≤ 512). À appeler dès que Firebase délivre un jeton ou le renouvelle. 403 si la session n'a pas d'appareil : il faut alors transmettre `device` à `login/confirm`. |

## 2.9 Préférences de notification

- `GET /auth/customer/preferences` → `{ "success": true, "preferredChannel": "SMS" | "EMAIL" | "WHATSAPP" | null }`
- `PATCH /auth/customer/preferences` → `{ "preferredChannel": "EMAIL" }`, ou `null` pour revenir à l'ordre par
  défaut (SMS, puis courriel, puis WhatsApp). Champ absent : rien ne change. 409 : carte sans dossier
  chez nous (carte vendue ailleurs), aucune préférence possible.
- Un événement donne **un seul** message sur le canal choisi, les autres ne servant qu'en repli. La
  déclaration de carte perdue fait exception : elle est envoyée partout.

---

# Partie 3 — Parcours de l'application écran par écran

Cette table indique, pour chaque écran de Konekt, les appels à faire. Le détail de chaque route est
dans les parties 2, 4, 5 et 6.

| # | Écran | Appels | Remarques |
|---|---|---|---|
| 1 | Démarrage | Jetons stockés ? → `GET /cards` (test de session) ; 401 → refresh → sinon écran 2 | `GET /status` (public) pour afficher une bannière d'incident. |
| 2 | Connexion : carte | `GET /auth/customer/channels` → `POST /auth/customer/login/init` | Clavier numérique ; retirer les espaces ; code d'invitation lu depuis le lien d'installation. |
| 3 | Connexion : code | `POST /auth/customer/login/confirm` | Envoyer `device`. Compte à rebours `expiryMinutes`. |
| 4 | Création du PIN | `POST /auth/customer/pin/setup/request` → `POST /auth/customer/pin` | Obligatoire si `hasPin=false`. |
| 5 | Accueil | `GET /cards`, `GET /cards/balance/:id`, `GET /notifications/unread-count`, `GET /catalog/services` | Montrer le solde, la pastille et les services disponibles (griser ceux qui ne le sont pas). |
| 6 | Historique | `GET /cards/transactions/:id` (mouvements émetteur) et `GET /operations` (opérations plateforme) | Voir Partie 6 pour le cloisonnement. |
| 7 | Détail d'une opération / reçu | `GET /cards/operations/:operationId` (ou `GET /operations/:id`) | |
| 8 | Voir ma carte (numéro, CVV) | `POST /cards/display/authorize` → ouvrir l'URL renvoyée (WebView) | Lien d'une minute, à usage unique. |
| 9 | Transfert carte → carte | `POST /cards/transfer/initiate` → `POST /cards/operations/:id/execute` (PIN) **ou** `/cards/operations/confirm` (code SMS) → `GET /cards/operations/:id` | |
| 10 | Retrait vers Mobile Money | `GET /external-wallets/channels` → `POST /external-wallets/payout/quote` (`fromCard: true`) → `POST /external-wallets/confirm` (PIN) | Ou la voie `cards/to-mobile-money` (Partie 4). Choisir **une** voie et s'y tenir. |
| 11 | Recharge crédit / forfait | `GET /catalog/lookup/mobile/:msisdn/products` → `POST /catalog/quote` → `POST /catalog/confirm` | |
| 12 | Électricité / TV | `/catalog/lookup/electricity/...` ou `/catalog/lookup/tv/...` → devis → confirmation | |
| 13 | Recharger ma carte depuis mon Mobile Money | `POST /catalog/quote` (`wallet-to-card`) → `POST /catalog/confirm` → validation sur le téléphone ou code B-MO (`/commerce/operations/:id/funding/confirm`) → suivi | |
| 14 | Retrait au guichet | `cash-withdrawal` via le catalogue | |
| 15 | Bloquer / débloquer ma carte | `PATCH /cards/status` | Voir le tableau des transitions (Partie 4). |
| 16 | Notifications | `GET /notifications`, `POST /notifications/:id/read`, `POST /notifications/read-all` | Le push n'est pas encore branché : interroger `unread-count`. |
| 17 | Sécurité | `GET /auth/customer/devices`, `DELETE /auth/customer/devices/:id`, `POST /auth/customer/pin/change`, `pin/reset/*`, `logout`, `logout-all` | |
| 18 | Préférences | `GET` / `PATCH /auth/customer/preferences` | |

**Règles d'or transverses**
1. **Toujours un devis avant de payer**, et toujours afficher le total réellement débité (montant +
   frais) avant de demander le PIN.
2. **Un identifiant unique (UUID v4) par tentative de paiement** dans `reference` / `requestId`. Ne
   réutilisez **jamais** une valeur, même entre deux porteurs (voir Partie 9).
3. **Ne répétez pas un paiement en cas de doute** (réseau coupé après l'envoi) : relisez l'opération
   (`GET /cards/operations/:id`) ou renvoyez **la même** `reference`, qui est idempotente.
4. **`INITIALIZED`, `PENDING`, `PENDING_APPROVAL` ou `PROCESSING` = ce n'est pas fini.** Interrogez
   toutes les 5 à 10 secondes jusqu'à un statut final (`SUCCESS`, `FAILED`, `CANCELLED`, `EXPIRED`,
   `REVERSED`, `REFUNDED`), avec un délai maximal (ex. 10 min). Au-delà, affichez « Opération en cours
   de traitement, vous serez notifié » sans **jamais** relancer le paiement.


---

# Partie 4 — Cartes et affichage sécurisé

> Toutes les routes sont sous `/api/v1` et exigent `Authorization: Bearer <sessionToken>`, sauf mention contraire. Le porteur ne peut agir que sur **la carte de sa session** : envoyez `cardCustomerId` exactement comme reçu dans `card.cardCustomerId` à la connexion.
>
> Dans cette partie, les renvois « § » désignent les sections de la Partie 4 elle-même.

### 4.0 Propriété de la carte : Comment est contrôlée la propriété de la carte

`CardAccessService.assertCanOperate` (`src/cards/services/card-access.guard-service.ts`) : pour un porteur, quel que soit le geste (lecture, débit, changement d'état), on calcule `encryptSearchable(cardCustomerId demandé)` et on le compare à `requester.id`. Pas d'appel distant.

- Différent → **403** `FORBIDDEN` « Vous ne pouvez agir que sur la carte avec laquelle vous vous êtes connecté. Reconnectez-vous avec l’autre carte pour l’utiliser. »
- ⚠️ La comparaison est **exacte sur la chaîne** : envoyez le `cardCustomerId` exactement comme reçu au login (chiffres uniquement, sans espace). Sur les routes où le DTO ne normalise pas (transfert `fromCardCustomerId`, affichage), un espace ou un zéro de tête manquant donne un 403.
- Pour les opérations : un porteur ne lit que les opérations qu'il a lancées (`createdBy === byString`) ou où figure sa carte (n'importe quel rôle) ; il n'annule/confirme/exécute que celles qu'il a lancées ou où sa carte est **SOURCE**.

### 4.0 bis Services carte ouverts au porteur : Services ouverts au porteur

`CUSTOMER_ALLOWED_SERVICES` (`src/cards/cards.constants.ts`) : `merchant:card:transfer`, `merchant:card:wallet-to-card`, `merchant:card:card-to-wallet`. Les gestes adossés au portefeuille d'un marchand (recharge `merchant:card:credit`, débit vers caisse `merchant:card:debit`, émission) sont fermés au porteur (403 « Cette opération passe par le portefeuille d'un marchand : adressez-vous à un point de vente. »). Les routes `issue/*`, `credit`, `debit/initiate` n'acceptent d'ailleurs pas l'acteur `customer` (403 au garde).

### 1. `GET /api/v1/cards` — Ma carte

**But.** Lister les cartes visibles par le requérant. Pour un porteur : uniquement les fiches de carte **émises sur la plateforme** dont `cardCustomerIdEnc` = carte de session (0 ou 1 en pratique).

**Auth.** `@AllowedActors('merchant','internal','admin','customer')`. `@RequireMerchantPermissions('merchant:card:read')` / `@RequireAdminPermissions('admin:card:read')` sans effet pour le porteur.

**Query (`GetCardsQueryDto`)** — tous facultatifs :

| Champ | Type | Règles | Exemple |
|---|---|---|---|
| `merchantId` | string | `@IsString` — « admin uniquement » (ignoré comme filtre pour le porteur) | — **ne pas envoyer** (voir ⚠️) |
| `cardTierSlug` | string | `@IsString` | `virtual:uba-bj:visa-prepaid-card:6-month` |
| `type` | enum `CardType` | `VIRTUAL` \| `PHYSICAL` | `VIRTUAL` |
| `status` | enum `CardStatus` | `Active` \| `Inactive` \| `PreActive` \| `LostOrStolen` \| `Deactivated` | `Active` |
| `search` | string | recherche insensible à la casse sur prénom/nom/email du dossier, `contains` sur téléphone | `kossi` |
| `createdBy` | string | filtre exact | — |
| `page` | int | `@Type(Number) @IsInt @Min(1)`, défaut 1 | `1` |
| `limit` | int | `@IsInt @Min(1) @Max(100)`, défaut 20 | `20` |
| `sortOrder` | `asc`\|`desc` | défaut `desc` (tri `createdAt`) | `desc` |

**Réponse 200 (`CardsListResponseDto`)**

```json
{
  "success": true,
  "data": [
    {
      "id": "clcd1234567890",
      "type": "VIRTUAL",
      "status": "Active",
      "customerId": "121436474",
      "last4": "4821",
      "cardTierSlug": "virtual:uba-bj:visa-prepaid-card:6-month",
      "cardTier": {
        "id": "clct1234567890",
        "slug": "virtual:uba-bj:visa-prepaid-card:6-month",
        "label": "Virtual Standard - UBA BJ",
        "type": "VIRTUAL",
        "provider": { "id": "clcp1234567890", "slug": "uba-bj:visa-prepaid-card", "label": "UBA BJ - VISA PREPAID CARD" },
        "duration": { "value": 6, "unit": "MONTH" }
      },
      "holder": {
        "kycId": "clkyc1234567890",
        "firstName": "Kossi",
        "lastName": "Adjovi",
        "email": "kossi.adjovi@example.com",
        "phoneCode": "+229",
        "phone": "61234567",
        "country": "Bénin",
        "city": "Cotonou",
        "identityStatus": "APPROVED",
        "identityExpiresAt": "2029-03-14T00:00:00.000Z"
      },
      "merchantId": "clm1234567890",
      "createdAt": "2026-08-12T14:30:52.000Z",
      "updatedAt": "2026-08-14T09:12:03.000Z"
    }
  ],
  "pagination": { "total": 1, "page": 1, "limit": 20, "totalPages": 1, "hasNextPage": false, "hasPreviousPage": false },
  "stats": null
}
```

Types : `status` ∈ CardStatus ; `customerId`, `last4`, `cardTier`, `holder`, `duration` nullables ; `holder.identityStatus` ∈ KycStatus (`DRAFT`, `PENDING_AI`, `AI_REJECTED`, `PENDING_MERCHANT`, `APPROVED`, `EXPIRED`, `REVOKED`, `KYC_CONFLICT`) ; `duration.unit` ∈ `HOUR|DAY|WEEK|MONTH|YEAR`.

**Règles métier.**
- Carte **externe** (non émise sur la plateforme) → `data: []`, `total: 0`. Ce n'est pas une erreur : utilisez alors `GET /cards/details/:cardCustomerId` et `GET /cards/balance/:cardCustomerId`.
- `status` est **notre copie** (synchronisée à chaque lecture émetteur) ; pour décider, lisez `details`/`balance`.
- `holder.identityStatus = EXPIRED` : la carte reste utilisable, mais aucune nouvelle carte ne pourra être achetée avant renouvellement de la pièce.
- `stats` est `null` pour un porteur… **sauf s'il envoie `merchantId`** : ⚠️ le service calcule alors les compteurs de parc de ce marchand (`query.merchantId ? _computeStats(query.merchantId)`), sans contrôle d'appartenance. Ne pas envoyer `merchantId` (et c'est une fuite d'information à corriger côté API).

**Erreurs.** 400 `VALIDATION_FAILED` (paramètre invalide) ; 401 (cf. Partie 1.5).

---

### 2. `GET /api/v1/cards/balance/:cardCustomerId` — Solde

**But.** Solde lu **en direct chez l'émetteur**. Ne jamais mettre en cache.

**Auth.** `customer` (+ merchant/internal/admin). Carte de session uniquement.

**Path.** `cardCustomerId` — passé dans `CardCustomerIdPipe` : espaces retirés puis `^\d{6,20}$` ; sinon **400** `REQUEST_REJECTED` « Identifiant de carte invalide : chiffres uniquement (vérifiez qu’aucune lettre « O » n’a été saisie à la place du zéro). »

**Query.** `cardTierSlug` (string, facultatif, `@Query` brut sans DTO) — inutile pour une carte émise sur la plateforme (la gamme en base fait foi, une indication contraire est ignorée) ; utile seulement pour une carte externe si plusieurs émetteurs sont gérés. Répété (`?cardTierSlug=a&cardTierSlug=b`) → 400 « cardTierSlug : une seule valeur attendue. »

**Réponse 200 (`CardBalanceResponseDto`)**

```json
{ "success": true, "balance": 74560, "currencyIsoCode": "XOF" }
```

**Règles métier (`CardQueryService.getBalance`).**
1. Propriété (§4.0). 2. Résolution de la gamme (`CardTierResolver.resolve`). 3. Fiche émetteur (cache 5 s).
- Carte `PreActive` → `{ balance: 0, currencyIsoCode: "xof" }` **sans appeler l'émetteur** (⚠️ devise en minuscules dans ce cas, `XOF`/valeur émetteur sinon : normalisez côté app).
- Carte `Active` → solde émetteur.
- Carte `Inactive` (suspendue) → **400** « Cette carte est suspendue. Réactivez-la d’abord : tant qu’elle est suspendue, aucune autre opération n’est possible. » — le solde d'une carte suspendue n'est pas lisible : affichez un état « carte suspendue » avec un bouton « Réactiver ».
- `LostOrStolen` / `Deactivated` → 400 (messages ci-dessous).

**Erreurs.**

| Statut | code | message (extrait) | Quoi faire |
|---|---|---|---|
| 400 | REQUEST_REJECTED | identifiant invalide (pipe) | Corriger l'identifiant |
| 403 | FORBIDDEN | « Vous ne pouvez agir que sur la carte avec laquelle vous vous êtes connecté… » | Bug app / reconnexion |
| 400 | CARD_TIER_REQUIRED / CARD_TIER_AMBIGUOUS | « …précisez sa gamme (cardTierSlug). » | Renvoyer avec `cardTierSlug` |
| 404 | NOT_FOUND | « Gamme « x » introuvable » (indication fausse sur carte externe) | Retirer/corriger `cardTierSlug` |
| 400 | REQUEST_REJECTED | « Cette carte est suspendue… » / « Cette carte a été déclarée perdue ou volée. Contactez le support : vos fonds peuvent être transférés sur une nouvelle carte. » / « Cette carte a été désactivée. Contactez le support — vos fonds ne sont pas perdus. » | Écran d'état + lien support |
| 404 | NOT_FOUND | « Aucune carte ne correspond à l'identifiant 121436474. » | Déconnexion / support |
| 500 | INTERNAL_ERROR | « Impossible de joindre l'émetteur de la carte. Réessayez dans un instant. » | Réessayer plus tard, afficher « solde indisponible » |

---

### 3. `GET /api/v1/cards/transactions/:cardCustomerId` — Mouvements

**But.** Relevé de la carte chez l'émetteur, sur une période (défaut : dernier mois).

**Auth.** `customer`. Carte de session uniquement.

**Path.** `cardCustomerId` : même pipe que §2 (`^\d{6,20}$` après retrait des espaces).

**Query** (bruts, sans DTO) :

| Champ | Type | Règles | Exemple |
|---|---|---|---|
| `cardTierSlug` | string | facultatif, cf. §2 | — |
| `startDate` | string | facultatif ; `AAAA-MM-JJ` ou date-heure **avec décalage** ; regex `^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?(Z\|[+-]\d{2}:?\d{2}))?$` (insensible à la casse) ; jour réel (le 30 février est refusé) | `2026-09-01` |
| `endDate` | string | idem ; défaut = maintenant | `2026-09-30` |

Défauts : `end = now`, `start = end − 1 mois`. `start > end` → 400 « La date de début doit précéder la date de fin. ». Date invalide → 400 « « startDate » doit être une date AAAA-MM-JJ existante (ou une date-heure avec décalage). »

⚠️ Une date seule `AAAA-MM-JJ` est lue par `new Date()` → minuit **UTC** de ce jour (y compris pour `endDate` : la journée de fin n'est donc pas incluse ; pour inclure le 30, envoyez `2026-09-30T23:59:59+01:00` ou `2026-10-01`).

**Réponse 200 (`CardTransactionsResponseDto`)**

```json
{
  "success": true,
  "transactions": [
    {
      "transactionId": 2089709140,
      "transactionDate": "17-AUG-2026",
      "transactionTime": "02:14:22",
      "transactionTimeHH24": "14:14:22",
      "baseAmount": 50000,
      "fee": 440,
      "totalAmount": 50440,
      "runningBalance": 74560,
      "transactionDesc": "Transfert sortant",
      "referenceInformation": "REF-4471",
      "merchantCountry": "BJ",
      "extendedInformation": null
    }
  ]
}
```

Formats **de l'émetteur, non convertis** (`JJ-MMM-AAAA`, heures en 12 h et 24 h) ; ordre du plus récent au plus ancien. Le contenu est renvoyé tel que l'émetteur le fournit (`transactions: transactions as never`) — prévoyez des champs manquants.

**Règles.** Carte `PreActive` → `transactions: []` sans appel émetteur. `Inactive`/`LostOrStolen`/`Deactivated` → 400 (mêmes messages que §2).

**Erreurs.** Identiques à §2, plus les deux 400 de dates ci-dessus.

---

### 4. `GET /api/v1/cards/details/:cardCustomerId` — Détails émetteur

**But.** Coordonnées du porteur et **état réel** de la carte chez l'émetteur (fait foi sur la liste).

**Auth.** `customer`. Carte de session.

**Path / Query.** `cardCustomerId` (pipe §2) ; `cardTierSlug` facultatif.

**Réponse 200 (`CardDetailsResponseDto`)**

```json
{
  "success": true,
  "card": {
    "firstName": "Kossi",
    "lastName": "Adjovi",
    "mobilePhoneNumber": "22961234567",
    "emailAddress": "kossi.adjovi@example.com",
    "cardStatus": "AC",
    "status": "Active",
    "last4": "4821",
    "cardTierSlug": "virtual:uba-bj:visa-prepaid-card:6-month"
  }
}
```

- `cardStatus` (vocabulaire émetteur) : `AC` active, `PA` pré-active, `IA` suspendue, `LC` perdue/volée, `DE` désactivée.
- `status` (notre vocabulaire, `CardStatus`) : nullable si l'émetteur renvoie un état inconnu.
- `last4` : nullable si l'habilitation CARDLAST4 manque (la lecture n'échoue pas).
- Volontairement étroit : ni numéro de pièce, ni date de naissance, ni adresse.

**Règles.** Pas de restriction d'état (lisible pour `PA`, `IA`) **sauf** si la carte est connue en base comme `LostOrStolen`/`Deactivated` → 400 immédiat (sans appel émetteur). C'est l'appel à faire au démarrage de l'app / avant une action pour connaître l'état.

**Erreurs.** 400 identifiant/gamme, 403 propriété, 400 carte terminale connue, 404 « Aucune carte ne correspond à l'identifiant … », 500 émetteur injoignable (cf. §2).

---

### 5. `GET /api/v1/cards/services/:serviceSlug/availability` — Renseignements service (DÉPRÉCIÉE)

**But.** Bornes, tarifs simulés au **canal porteur** (`CUSTOMER_SELF_SERVICE`) et gammes. Dépréciée au profit de `GET /api/v1/catalog/services/{service}?amount=…` (hors périmètre) — à utiliser de préférence.

**Auth.** `@AllowedActors('merchant','internal','customer')`.

**Path.** `serviceSlug` : string libre (pas de validation de format). Pour le porteur, valeurs utiles : `merchant:card:transfer`, `merchant:card:card-to-wallet`, `merchant:card:wallet-to-card`. (Encodez `:` en `%3A` si votre client HTTP le requiert.)

**Réponse 200 (`ServiceAvailabilityResponseDto`)**

```json
{
  "success": true,
  "service": { "slug": "merchant:card:transfer", "label": "Transfert carte à carte" },
  "isAvailable": true,
  "initiationMode": "CUSTOMER_SELF_SERVICE",
  "limits": { "minAmount": 1000, "maxAmount": 5000000 },
  "estimatedFees": [
    { "amount": 10000, "fee": 150, "totalAmount": 10150, "resolved": true },
    { "amount": 50000, "fee": 440, "totalAmount": 50440, "resolved": true },
    { "amount": 100000, "fee": 800, "totalAmount": 100800, "resolved": true },
    { "amount": 500000, "fee": 3500, "totalAmount": 503500, "resolved": true },
    { "amount": 1000000, "fee": 0, "totalAmount": 1000000, "resolved": false }
  ],
  "cardTiers": [
    { "slug": "virtual:uba-bj:visa-prepaid-card:6-month", "label": "Virtual Standard - UBA BJ", "type": "VIRTUAL", "provider": { "slug": "uba-bj:visa-prepaid-card", "label": "UBA BJ - VISA PREPAID CARD" } }
  ]
}
```

**Règles.**
- `limits` : limite configurée du service, sinon défaut `{ minAmount: 1000, maxAmount: 10000000 }`. ⚠️ Ces bornes **ne sont pas appliquées** par les routes d'initiation (qui n'imposent que 100 ≤ montant ≤ 10 000 000 et la couverture de la grille) : appliquez-les vous-même à la saisie.
- `estimatedFees` sur 10 000 / 50 000 / 100 000 / 500 000 / 1 000 000, **sans gamme** (barème générique ; le vrai prix d'une carte émise sur la plateforme dépend de sa gamme). `resolved: false` ⇒ pas de tarif : n'affichez pas « gratuit ».
- `cardTiers` = gammes distribuées par le **marchand de session**, sans intérêt pour le porteur (il n'a pas à choisir de gamme).
- `isAvailable` vaut toujours `true` quand la réponse est 200. Aucun contrôle `CUSTOMER_ALLOWED_SERVICES` ici : un porteur peut interroger `merchant:card:credit` alors qu'il ne peut pas l'utiliser.

**Erreurs.** 404 `NOT_FOUND` « Le service « x » n'est pas disponible. » (inconnu/inactif).

---

### 6. Flux « sortie d'argent » : vue d'ensemble (transfert carte→carte, retrait vers mobile money)

```
             ┌────────────────────────────────────────────┐
  (1) POST /cards/transfer/initiate          ou  POST /cards/to-mobile-money/initiate
             └───────────────┬────────────────────────────┘
                             │ réponse : operationId, requiresConfirmation, fee, amountDebited…
           ┌─────────────────┴──────────────────┐
  requiresConfirmation = false          requiresConfirmation = true
  (porteur AVEC code secret)            (porteur SANS code secret : OTP envoyé)
           │                                     │
  (2a) POST /cards/operations/{id}/execute (2b) POST /cards/operations/confirm
       body { "pin": "482915" }               body { "operationId", "code" }
           │                                     │
           └──────────────► 200 ConfirmOperationResponseDto (status SUCCESS)
  (à tout moment avant 2a/2b)  DELETE /cards/operations/{id}  → annulation
  (suivi / reçu)               GET    /cards/operations/{id}
```

**Choix de la voie (`CardDebitOrchestrator._resolveConfirmationPolicy`).** Pour un porteur :
- `req.customer.kycId` présent **et** un PIN défini sur ce dossier (`CustomerPinService.hasPin`) → `requiresConfirmation: false`, statut opération `PENDING`, `consentMode: HOLDER_PIN`, **aucun SMS**. → étape 2a avec le PIN.
- Sinon → `requiresConfirmation: true`, statut `PENDING_APPROVAL`, `consentMode: HOLDER_OTP`, code à 6 chiffres envoyé au porteur (SMS/WhatsApp/Email). → étape 2b.

L'app connaît `hasPin` dès le login (`login/confirm` renvoie `hasPin`) : si `false`, invitez à définir le PIN (`POST /auth/customer/pin/setup/request` puis `POST /auth/customer/pin`) — sinon chaque sortie d'argent passera par un OTP.

**Lisez TOUJOURS `requiresConfirmation`** : attendre un SMS quand il vaut `false` est le premier motif de support.

**Montants.** Fonds venant de la carte : `amountDebited = amount + fee` (ce que paie le porteur, à annoncer), `amountCredited = amount` (ce que reçoit le destinataire). Les frais sont **arrêtés à l'initiation** (`frozenFee`) et réutilisés à l'exécution.

**Durées.** OTP valable 5 min (`OTP_EXPIRY_MINUTES`), 3 essais (`OTP_MAX_ATTEMPTS`). L'opération porte `timeoutAt = +10 min` (`OPERATION_EXPIRY_MINUTES`) mais **ni `execute` ni `confirm` ne vérifient `timeoutAt`** : si l'utilisateur abandonne, annulez explicitement (`DELETE`) plutôt que de compter sur l'expiration.

**Exécution synchrone.** `confirm`/`execute` appellent l'émetteur (et l'opérateur mobile) dans la requête : prévoyez un délai d'attente long (≥ 60 s) et un écran « traitement en cours ». Ne relancez jamais automatiquement après un 500 contenant « NE LA RELANCEZ PAS » : consultez `GET /cards/operations/{id}`.

---

### 7. `POST /api/v1/cards/transfer/initiate` — Préparer un transfert carte → carte

**But.** Envoyer de l'argent de **ma carte (de session)** vers une autre carte du **même émetteur** (gammes différentes autorisées).

**Auth.** `@AllowedActors('merchant','internal','customer')`, `@RequireMerchantPermissions('merchant:card:transfer')` (sans effet pour le porteur), `@HttpCode(200)`. Service `merchant:card:transfer` autorisé au porteur. Aucune limite de fréquence.

**Body (`TransferCardDto`)**

| Champ | Type | Requis | Validation | Exemple |
|---|---|---|---|---|
| `fromCardCustomerId` | string | oui | `@IsString` seulement (**pas** de normalisation ni de regex) — doit être la carte de session, au caractère près | `"121436474"` |
| `toCardCustomerId` | string | oui | `@IsString` seulement | `"121436999"` |
| `cardTierSlug` | string | non | `@IsString` — gamme de la carte de départ, inutile si émise sur la plateforme | — |
| `toCardTierSlug` | string | non | `@IsString` — gamme de la carte destinataire (utile si externe et plusieurs émetteurs) | `"physical:uba-bj:visa-prepaid-card:miton"` |
| `amount` | number | oui | `@Type(Number) @IsNumber @Min(100) @Max(10000000)` — montant **reçu** par le destinataire | `15000` |
| `otpChannel` | enum | non | `@IsIn(['SMS','WHATSAPP','EMAIL'])`, défaut `SMS` ; sans effet si le porteur a un PIN | `"SMS"` |
| `requestId` | string | non | `@IsString @MaxLength(64)` — clé d'idempotence (UUID recommandé, cf. Partie 3 (règles d’or) et Partie 9) | `"6f1c9a1e-2b0f-4f43-9d8b-3c0e1e7f8a21"` |

Exemple :
```json
{ "fromCardCustomerId": "121436474", "toCardCustomerId": "121436999", "amount": 15000, "requestId": "6f1c9a1e-2b0f-4f43-9d8b-3c0e1e7f8a21" }
```

**Réponse 200 (`InitTransferResponseDto`)**

```json
{
  "success": true,
  "operationId": "clop1234567890",
  "requiresConfirmation": false,
  "otpChannel": null,
  "sentTo": null,
  "expiresInSeconds": 0,
  "attemptsLeft": 0,
  "fee": 200,
  "amountDebited": 15200,
  "amountCredited": 15000,
  "cardHolderName": "Kossi Adjovi",
  "isReplay": false,
  "targetLast4": "9034",
  "targetHolderName": "Afiavi Sossou"
}
```

Variante OTP (porteur sans PIN) : `"requiresConfirmation": true, "otpChannel": "SMS", "sentTo": "********567", "expiresInSeconds": 300, "attemptsLeft": 3`.

| Champ | Type | Sens |
|---|---|---|
| `operationId` | string | à passer à execute/confirm/cancel/get |
| `requiresConfirmation` | boolean | **décide de l'étape suivante** (§6) |
| `otpChannel` | `SMS`\|`WHATSAPP`\|`EMAIL`\|null | canal **réellement** utilisé (bascule sur EMAIL si pas de téléphone) |
| `sentTo` | string\|null | contact masqué (téléphone : tous les chiffres sauf les 3 derniers remplacés par `*` ; email : `ko***@example.com`) |
| `expiresInSeconds` | number | 300 si OTP, sinon 0 |
| `attemptsLeft` | number | 3 si OTP, sinon 0 (0 aussi sur rejeu) |
| `fee`, `amountDebited`, `amountCredited` | number | frais arrêtés ; débité carte = montant + frais ; reçu = montant |
| `cardHolderName` | string | nom du porteur de la carte source chez l'émetteur |
| `isReplay` | boolean | `true` = même `requestId` déjà traité : aucun nouveau code, champs de canal nuls |
| `targetLast4` | string | 4 derniers chiffres de la destination |
| `targetHolderName` | string | nom du destinataire chez l'émetteur |

**Règles métier (`CardTransferService.initiate` → `CardDebitOrchestrator.initiate`), dans l'ordre :**
1. `from === to` → 400.
2. Service autorisé au porteur ; `fromCardCustomerId` = carte de session (403 sinon). **Aucune contrainte sur la destination** (toute carte du même émetteur, y compris externe).
3. Résolution des gammes source et destination ; émetteurs différents → 400 `CARD_PROVIDER_MISMATCH`.
4. La destination doit pouvoir **recevoir** : statut émetteur `AC` ou `PA` (premier crédit). `IA` (suspendue) / `LC` / `DE` refusés.
5. Calcul des frais (barème de la gamme de la carte **source** ; aucun barème de gamme pour une carte externe ; canal `CUSTOMER_SELF_SERVICE`).
6. Source : statut `AC` **uniquement** (une carte `PA` ou `IA` ne peut pas envoyer) et solde ≥ `amount + fee` (lecture fraîche).
7. 4 derniers chiffres (source et destination) lus sur la fiche émetteur.
8. Choix PIN/OTP (§6), création de l'opération (`PENDING` ou `PENDING_APPROVAL`), rattachement des cartes SOURCE et TARGET, envoi OTP éventuel.

**À faire dans l'app.** Afficher et faire **confirmer `targetHolderName` + `targetLast4`** avant l'étape 2 (un transfert abouti ne se reprend pas) ; afficher `amountDebited` comme « vous payez » et `fee`.

**Erreurs.**

| Statut | code | message | Quoi faire |
|---|---|---|---|
| 400 | VALIDATION_FAILED | champ manquant/invalide, champ inconnu, `amount` < 100 ou > 10 000 000 | Corriger la saisie (`details`) |
| 400 | REQUEST_REJECTED | « La carte de destination doit être différente de la carte de départ. » | Message inline |
| 403 | FORBIDDEN | « Vous ne pouvez agir que sur la carte avec laquelle vous vous êtes connecté… » | Bug / reconnexion |
| 400 | CARD_PROVIDER_MISMATCH | « Transfert impossible entre cartes de deux émetteurs différents… » | Message inline |
| 400 | CARD_TIER_REQUIRED / CARD_TIER_AMBIGUOUS | « …précisez sa gamme (cardTierSlug). » | Rare : renvoyer avec `toCardTierSlug` |
| 404 | NOT_FOUND | « Aucune carte ne correspond à l'identifiant 121436999. » | « Carte destinataire inconnue » |
| 400 | REQUEST_REJECTED | Refus d'état (attention : peut concerner la **destination** OU la **source**, le message ne dit pas laquelle) : « Cette carte est suspendue. Réactivez-la d’abord… », « Cette carte n’a pas encore été activée. Rechargez-la une première fois… », « …déclarée perdue ou volée… », « …désactivée… », « Opération impossible sur cette carte. » | Vérifier d'abord l'état de la carte source via `details` pour formuler le bon message |
| 400 | REQUEST_REJECTED | « Solde insuffisant : 12000 disponible(s), 15200 nécessaire(s) (frais compris). » | Proposer un montant plus faible |
| 404 | NOT_FOUND | « Aucun tarif applicable pour … — montant …, canal CUSTOMER_SELF_SERVICE. La grille ne couvre pas ce montant. » | Montant hors grille : changer de montant |
| 400 | REQUEST_REJECTED | « Les frais (x) absorbent la totalité du montant (y)… » | Augmenter le montant |
| 400 | REQUEST_REJECTED | « Tarif de ce service mal configuré : opération refusée… » / « Le service « merchant:card:transfer » n'est pas disponible. » | Service indisponible |
| 400 | REQUEST_REJECTED | « Cette requête est déjà en cours de traitement. » (double envoi simultané du même `requestId`) | Attendre, relire l'opération |
| 400 | REQUEST_REJECTED | « Aucun numéro ni courriel connu pour ce porteur : impossible de lui demander son autorisation. » (voie OTP) | Inviter à définir un PIN / support |
| 503 | PROVIDER_UNAVAILABLE | « Les quatre derniers chiffres de cette carte sont momentanément indisponibles chez l’émetteur… » | Réessayer plus tard |
| 500 | INTERNAL_ERROR | « Impossible de joindre l'émetteur de la carte. Réessayez dans un instant. » | Réessayer |

Note : le contrôle d'idempotence (`requestId`) a lieu **après** les contrôles d'état et de solde ; un rejeu peut donc échouer en 400 si le solde a changé entre-temps.

---

### 8. `POST /api/v1/cards/to-mobile-money/initiate` — Préparer un retrait vers un portefeuille mobile

**But.** Débiter **ma carte** et verser sur un portefeuille mobile (B-MO / BestCash Money ou autre opérateur via agrégateur). **Irréversible** une fois parti.

**Auth.** `@AllowedActors('merchant','internal','customer')`, `@RequireMerchantPermissions('merchant:card:card-to-wallet')` (sans effet porteur), `@HttpCode(200)`. Service `merchant:card:card-to-wallet` autorisé au porteur.

**Body (`CardToMobileMoneyDto`)**

| Champ | Type | Requis | Validation | Exemple |
|---|---|---|---|---|
| `cardCustomerId` | string | oui | `@IsString` + `@IsCardCustomerId` (espaces retirés, `^\d{6,20}$`, message « Identifiant de carte invalide… ») — carte de session | `"121436474"` |
| `cardTierSlug` | string | non | `@IsString` | — |
| `amount` | number | oui | `@Type(Number) @IsNumber @Min(100) @Max(10000000)` — montant **reçu** par le portefeuille | `10000` |
| `phone` | string | oui | `@IsString` (pas de format imposé) | `"+22961234567"` |
| `wallet` | string | oui | `@IsString` — slug du canal externe (`providerSlug`, insensible à la casse) | `"BMO"` / `"mtn-benin"` |
| `firstName` | string | non* | `@IsString @MaxLength(80)` — **obligatoire pour tout portefeuille sauf B-MO** | `"Kossi"` |
| `lastName` | string | non* | `@IsString @MaxLength(80)` — idem | `"Adjovi"` |
| `reason` | string | non | `@IsString @MaxLength(120)` — motif visible du bénéficiaire (défaut à l'exécution : « Retrait depuis carte ») | `"Retrait"` |
| `otpChannel` | enum | non | `SMS`\|`WHATSAPP`\|`EMAIL`, défaut `SMS` | `"SMS"` |
| `requestId` | string | non | `@IsString @MaxLength(64)` | UUID |

**Réponse 200 (`InitOperationResponseDto`)** — mêmes champs que §7 **sans** `targetLast4`/`targetHolderName` :

```json
{
  "success": true,
  "operationId": "clop5550001112",
  "requiresConfirmation": false,
  "otpChannel": null,
  "sentTo": null,
  "expiresInSeconds": 0,
  "attemptsLeft": 0,
  "fee": 300,
  "amountDebited": 10300,
  "amountCredited": 10000,
  "cardHolderName": "Kossi Adjovi",
  "isReplay": false
}
```

**Règles métier (`CardDebitOrchestrator.initiate` + `_assertWalletCanReceive`).**
1. Service autorisé ; carte = carte de session.
2. Gamme résolue (pas de contrôle « gamme distribuée » pour le porteur).
3. **Vérification du portefeuille avant tout** : si le canal est un canal B-MO direct, B-MO est interrogé (quota 300 vérifications/heure par porteur, en mémoire) :
   - numéro sans compte B-MO → 400 ;
   - compte trouvé → **le nom B-MO remplace** `firstName`/`lastName` saisis (le versement se fait sous ce nom) ;
   - B-MO injoignable, quota atteint, ou erreur de canal → 503.
   - Canal non B-MO (agrégateur) : pas de vérification, mais `firstName` et `lastName` non vides **exigés** (400 sinon).
4. Frais, puis carte `AC` et solde ≥ `amount + fee`.
5. PIN/OTP (§6), création de l'opération.

⚠️ La réponse ne renvoie **pas** le nom du bénéficiaire retenu par B-MO : pour l'afficher avant confirmation, lisez `GET /cards/operations/{operationId}` (`parties[]`, rôle `BENEFICIARY`, `verified: true`), ou utilisez la vérification de titulaire du catalogue. Faites **vérifier le numéro** par l'utilisateur avant l'étape 2.

**Erreurs.** Celles de §7 applicables à la source (validation, 403, gamme, état, solde, tarif, idempotence, OTP, 503 last4, 500 émetteur) plus :

| Statut | code | message | Quoi faire |
|---|---|---|---|
| 403 | FORBIDDEN | « Cette opération passe par le portefeuille d'un marchand… » | (n'arrive pas pour ce service) |
| 400 | REQUEST_REJECTED | « Ce numéro n’a pas de compte BestCash Money : nous ne versons qu’à un compte existant. Vérifiez le numéro. » | Inline sur le champ téléphone |
| 400 | REQUEST_REJECTED | « Le prénom et le nom du bénéficiaire sont requis pour ce portefeuille. » | Afficher les champs nom/prénom |
| 503 | PROVIDER_UNAVAILABLE | « Le portefeuille de destination ne peut pas être vérifié pour l’instant. Réessayez dans quelques instants. » | Réessayer plus tard |

---

### 9. `POST /api/v1/cards/operations/{operationId}/execute` — Exécuter avec le PIN (voie sans OTP)

**But.** Conclure une opération initiée avec `requiresConfirmation: false`, en prouvant l'accord par le **code secret (PIN) à 6 chiffres** du porteur.

**Auth.** `@AllowedActors('merchant','internal','customer')`, aucune permission déclarée (droit vérifié contre le service de l'opération — dispensé pour le porteur). `@HttpCode(200)`.

**Path.** `operationId` (string, ex. `clop1234567890`).

**Body (`ExecuteOperationDto`)**

| Champ | Type | Requis | Validation | Exemple |
|---|---|---|---|---|
| `pin` | string | **oui pour un porteur** (facultatif dans le DTO) | `@IsString @Matches(/^\d{6}$/)` message « Six chiffres attendus. » | `"482915"` |

**Réponse 200 (`ConfirmOperationResponseDto`)**

```json
{
  "success": true,
  "operationId": "clop1234567890",
  "status": "SUCCESS",
  "fee": 200,
  "amountDebited": 15200,
  "amountCredited": 15000,
  "reference": "clop1234567890",
  "completedAt": "2026-10-15T09:14:22.418Z",
  "details": { "sourceReference": "2089709140", "targetReference": "2089709141" }
}
```

`details` dépend de la destination : transfert → `sourceReference`, `targetReference` ; mobile money → `providerReference`, `payoutReference` (à citer en premier en cas de réclamation). `reference` = `operationId` (⚠️ pas la référence lisible `COP-…` ; celle-ci est dans `GET /cards/operations/{id}`).

**Séquence serveur (`proceedWithoutConfirmation` + `CardDebitExecutor.run`).**
1. Opération introuvable → 404.
2. Appartenance : opération lancée par le porteur (`consentMode` `HOLDER_PIN`/`HOLDER_OTP`) ⇒ seul ce porteur (`createdBy` = son `byString`, ou carte SOURCE = sa carte) peut conclure. Un marchand ne peut **jamais** conclure ce qu'un porteur a lancé.
3. Statut doit être `PENDING` (sinon 400 explicatif).
4. L'opération doit avoir été créée sans exigence de code (`confirmationExemption`), sinon 400.
5. **PIN** (`buildCardConsent` → `CustomerPinService.verifyPin(kycId, pin)`) : `pin` absent → 400 `CARD_CONSENT_REQUIRED` ; pas de `kycId` de session → 403 `CARD_CONSENT_UNAVAILABLE` ; PIN faux → 403 avec essais restants ; verrou après **5** échecs (config `CUSTOMER_PIN_MAX_ATTEMPTS`) pendant **15 min** (config `CUSTOMER_PIN_LOCK_MINUTES`). **Un PIN faux n'annule pas l'opération** : elle reste `PENDING`, l'utilisateur peut ressaisir.
6. Passage atomique `PENDING → PROCESSING` (double clic → 400 « déjà en cours de traitement »).
7. Exécution saga : débit carte source (montant + frais) puis crédit destination / versement mobile. En cas d'échec, compensation automatique (recrédit de la carte). Notifications porteur (et destinataire pour un transfert) envoyées en arrière-plan.

**Erreurs.**

| Statut | code | message | Quoi faire |
|---|---|---|---|
| 400 | VALIDATION_FAILED | `pin` mal formé / champ inconnu | Inline |
| 404 | NOT_FOUND | « Opération introuvable. » | Recommencer l'initiation |
| 403 | FORBIDDEN | « Cette opération ne vous appartient pas. » | Bug app |
| 400 | REQUEST_REJECTED | état : « Cette opération a déjà été effectuée. » / « …est en cours de traitement. » / « …a été annulée. » / « …a expiré. Recommencez-la. » / « …a échoué. Recommencez-la. » / « Cette opération n'est pas confirmable (état PENDING_APPROVAL). » (⇒ elle exigeait un OTP : utilisez `confirm`) | Selon le cas : afficher le reçu, ou recommencer |
| 400 | REQUEST_REJECTED | « Cette opération requiert une confirmation par code. » | Basculer vers `confirm` |
| 400 | CARD_CONSENT_REQUIRED | « Votre code secret est requis pour payer avec votre carte. » | Demander le PIN |
| 403 | CARD_CONSENT_UNAVAILABLE | « Le paiement par carte n’est pas disponible pour une carte émise hors de la plateforme… » | Rare (session sans dossier) : support |
| 403 | FORBIDDEN | « Code incorrect — 3 tentative(s) restante(s). » | Ressaisie, afficher le compteur |
| 403 | FORBIDDEN | « Trop de codes erronés. Votre compte est bloqué pendant 15 minutes. Vous pouvez aussi réinitialiser votre code. » / « Trop de codes erronés. Réessayez dans N minute(s), ou réinitialisez votre code. » | Proposer « PIN oublié » (`/auth/customer/pin/reset/request`) |
| 400 | REQUEST_REJECTED | « Aucun code secret n’a encore été défini pour ce compte. » | Parcours de création du PIN |
| 400 | REQUEST_REJECTED | « Cette opération est déjà en cours de traitement. » | Ne pas relancer ; suivre via GET |
| 400 | REQUEST_REJECTED | « Cette opération ne peut pas être confirmée. Recommencez-la. » (pas de tarif arrêté) / « …ne peut pas être exécutée. Contactez le support. » | Recommencer / support |
| 500 | INTERNAL_ERROR | « Le transfert a échoué : … » / « Le retrait vers mobile money a échoué : … » (compensation réussie : carte recréditée) | Informer, l'utilisateur peut réessayer avec une **nouvelle** initiation |
| 500 | INTERNAL_ERROR | Messages contenant « NE LA RELANCEZ PAS » (sort incertain, compensation incomplète, versement parti mais non enregistré, versement non confirmé) → opération `FAILED` + `requiresReview` | Ne PAS relancer ; écran « en vérification », afficher la référence, suivre via GET |

---

### 10. `POST /api/v1/cards/operations/confirm` — Confirmer par OTP (voie avec code)

**But.** Conclure une opération initiée avec `requiresConfirmation: true` en saisissant le code reçu par SMS/WhatsApp/Email.

**Auth.** `@AllowedActors('merchant','internal','customer')`, aucune permission déclarée. `@HttpCode(200)`.

**Body (`ConfirmOperationDto`)**

| Champ | Type | Requis | Validation | Exemple |
|---|---|---|---|---|
| `operationId` | string | oui | `@IsString` | `"clop1234567890"` |
| `code` | string | oui | `@IsString @Matches(/^\d{6}$/)` message « Le code comporte six chiffres. » | `"123456"` |

**Réponse 200.** `ConfirmOperationResponseDto` identique à §9.

**Séquence serveur (`CardDebitOrchestrator.confirm`).**
1. Opération introuvable → 404 ; appartenance (§9 étape 2) ; statut doit être `PENDING_APPROVAL`.
2. Dernier OTP non vérifié et non expiré (5 min) ; aucun → 400 « Le code a expiré. Recommencez l’opération pour en recevoir un nouveau. » (**il n'existe pas de route de renvoi du code** : il faut annuler et ré-initier).
3. Essai réservé atomiquement **avant** comparaison ; comparaison en temps constant sur l'empreinte HMAC.
4. Code faux : 400 « Code incorrect — N tentative(s) restante(s). » ; au 3ᵉ échec l'opération passe `CANCELLED` (« Code incorrect. L’opération a été annulée par sécurité. ») ; au-delà « Trop de tentatives. L’opération a été annulée par sécurité. »
5. Code consommé, `PENDING_APPROVAL → PROCESSING`, puis exécution (identique à §9 étape 7).

**Erreurs.**

| Statut | code | message | Quoi faire |
|---|---|---|---|
| 400 | VALIDATION_FAILED | code non à 6 chiffres | Inline |
| 404 | NOT_FOUND | « Opération introuvable. » | Recommencer |
| 403 | FORBIDDEN | « Cette opération ne vous appartient pas. » | Bug app |
| 400 | REQUEST_REJECTED | messages d'état (cf. §9), dont « Cette opération n'est pas confirmable (état PENDING). » (⇒ voie PIN : utilisez `execute`) | Selon le cas |
| 400 | REQUEST_REJECTED | « Le code a expiré. Recommencez l’opération pour en recevoir un nouveau. » | Bouton « Recommencer » (nouvelle initiation, nouveau `requestId`) |
| 400 | REQUEST_REJECTED | « Code incorrect — 2 tentative(s) restante(s). » | Ressaisie, afficher le compteur |
| 400 | REQUEST_REJECTED | « Code incorrect. L’opération a été annulée par sécurité. » / « Trop de tentatives… » | Retour au formulaire, recommencer |
| 400 | REQUEST_REJECTED | « Ce code vient d’être utilisé. » / « Cette opération vient d’être annulée ou traitée. » | Relire l'opération (GET) |
| 500 | INTERNAL_ERROR | échecs d'exécution (cf. §9) | Idem §9 |

---

### 11. `GET /api/v1/cards/operations/{operationId}` — Suivre une opération (reçu)

**But.** État et détail d'une opération (cartes, catalogue compris). Montants = ceux **arrêtés** à l'initiation.

**Auth.** `@AllowedActors('merchant','internal','admin','customer')`. Porteur : opérations qu'il a lancées, ou où figure sa carte (tout rôle, y compris un transfert **reçu**). Sinon 404 (et non 403, pour ne rien révéler).

**Path.** `operationId`.

**Réponse 200 (`OperationStatusResponseDto`)**

```json
{
  "success": true,
  "operationId": "clop1234567890",
  "reference": "COP-20261015-091422-A7B9",
  "type": "CARD_OPERATION",
  "status": "SUCCESS",
  "initiationMode": "CUSTOMER_SELF_SERVICE",
  "amount": 15000,
  "fee": 200,
  "amountDebited": 15200,
  "amountCredited": 15000,
  "reason": null,
  "awaiting": null,
  "cards": [
    { "role": "SOURCE", "last4": "4821", "holderName": "Kossi Adjovi" },
    { "role": "TARGET", "last4": "9034", "holderName": "Afiavi Sossou" }
  ],
  "service": { "slug": "merchant:card:transfer", "label": "Transfert carte à carte" },
  "merchantName": "Boutique Cotonou Centre",
  "parties": [],
  "initiatedBy": { "type": "customer", "name": "Kossi Adjovi" },
  "createdAt": "2026-10-15T09:13:40.000Z",
  "approvedAt": "2026-10-15T09:14:20.000Z"
}
```

- `status` ∈ `INITIALIZED`, `PENDING`, `PENDING_APPROVAL`, `PROCESSING`, `SUCCESS`, `FAILED`, `CANCELLED`, `REVERSED`, `REFUNDED`, `EXPIRED`.
- `type` ∈ OperationType ; `initiationMode` ∈ `MERCHANT_ASSISTED` | `CUSTOMER_SELF_SERVICE` | `API_KEY`.
- `fee`/`amountDebited`/`amountCredited` nullables ; `reason` = motif d'échec ou d'annulation.
- `cards[].role` ∈ `MAIN` | `SOURCE` | `TARGET`.
- `parties[]` : `{ role: "PAYER"|"BENEFICIARY", name, identifier (masqué pour un porteur), channelSlug, channelLabel, verified }` — c'est là que figure le bénéficiaire d'un retrait mobile money.
- `merchantName` = marchand de session pour une opération porteur.
- `awaiting` (seulement si `PENDING`) : `CONFIRMATION_CODE` (paiement B-MO du catalogue en attente : **rafraîchir toutes les 10 s**, la route interroge B-MO au plus toutes les 15 s et passe à `SUCCESS` dès paiement), `PROVIDER_SETTLEMENT`, ou `null`.

**Usage KONEKT.** Écran reçu après execute/confirm ; reprise après un 500 « NE LA RELANCEZ PAS » ; affichage d'un transfert reçu ; polling des achats catalogue payés via B-MO.

**Erreurs.** 404 « Opération introuvable. » (inexistante ou hors périmètre).

---

### 12. `DELETE /api/v1/cards/operations/{operationId}` — Annuler une opération en attente

**But.** Abandonner un transfert/retrait initié et non encore exécuté (ex. l'utilisateur quitte l'écran PIN/OTP).

**Auth.** `@AllowedActors('merchant','internal','customer')`, `@HttpCode(200)`. Porteur : opération qu'il a lancée, ou débit où sa carte est **SOURCE** (jamais un transfert qu'il ne fait que recevoir).

**Path.** `operationId`. **Body facultatif** : `{ "reason": "Abandon par l'utilisateur" }` (`@Body('reason')`, string libre, non validé ; défaut « Annulée par son auteur »).

**Réponse 200 (`CancelOperationResponseDto`)**

```json
{ "success": true, "operationId": "clop1234567890", "message": "Opération annulée." }
```

**Règles.**
- Réservé aux **débits de carte** (opérations portant une `destination`). Un achat du catalogue en attente de paiement → 400 `USE_FUNDING_CANCEL` : utiliser `POST /api/v1/commerce/operations/{id}/funding/cancel`.
- Annulable depuis `PENDING`, `PENDING_APPROVAL`, `INITIALIZED` uniquement (écriture conditionnelle : une exécution concurrente gagne).
- Une fois l'exécution commencée, pas d'annulation manuelle : la compensation est automatique.

**Erreurs.**

| Statut | code | message | Quoi faire |
|---|---|---|---|
| 404 | NOT_FOUND | « Opération introuvable. » | Ignorer / rafraîchir |
| 400 | USE_FUNDING_CANCEL | « Cette opération s’annule par POST /commerce/operations/{id}/funding/cancel, qui prévient le prestataire de paiement. » | Appeler la route indiquée |
| 400 | REQUEST_REJECTED | « Cette opération ne peut plus être annulée : elle est déjà en cours de traitement ou terminée. » | Relire l'opération (GET) |

---

### 13. `PATCH /api/v1/cards/status` — Suspendre / réactiver / déclarer perdue

**But.** Permettre au porteur de **suspendre** (réversible), **réactiver**, ou **déclarer perdue/volée** (définitif) sa carte, sans passer par un marchand.

**Auth.** `@AllowedActors('merchant','internal','customer')`, `@RequireMerchantPermissions('merchant:card:update-status')` (sans effet porteur). Porteur : carte de session uniquement (règle « vendeur seulement » réservée aux marchands). ⚠️ **Aucun PIN ni OTP exigé** : sécurisez l'action dans l'app (confirmation explicite, idéalement re-saisie du PIN côté client si vous le souhaitez — non vérifiée par l'API). Pas de `@HttpCode` → réponse **200** (PATCH).

**Body (`ChangeCardStatusDto`)**

| Champ | Type | Requis | Validation | Exemple |
|---|---|---|---|---|
| `cardCustomerId` | string | oui | `@IsString @IsCardCustomerId` (espaces retirés, `^\d{6,20}$`) | `"121436474"` |
| `cardTierSlug` | string | non | `@IsString` | — |
| `newStatus` | enum | oui | `@IsIn(['Active','Inactive','LostOrStolen'])` | `"Inactive"` |
| `phoneCountryCode` | string | non | `@IsString` — seulement si l'émetteur ne renvoie pas le numéro | `"229"` |
| `phoneNumber` | string | non | `@IsString` | `"61234567"` |
| `acknowledgeIrreversible` | boolean | **oui si `LostOrStolen`** | `@IsOptional @IsBoolean` ; doit valoir `true` | `true` |

**Réponse 200 (`ChangeCardStatusResponseDto`)**

```json
{ "success": true, "operationId": "clop7778889990", "previousStatus": "Active", "newStatus": "Inactive" }
```

`previousStatus` = état **constaté chez l'émetteur** avant le changement.

**Transitions réellement acceptées** (`_assertTransitionAllowed` + `CardValidationService.assertTransitionAccepted`, matrice `ALLOWED`) :

| État actuel (émetteur) | → `Active` | → `Inactive` | → `LostOrStolen` |
|---|---|---|---|
| `Active` (AC) | 400 déjà dans l'état | ✅ | ✅ (avec `acknowledgeIrreversible: true`) |
| `Inactive` (IA) | ✅ | 400 déjà dans l'état | ❌ 400 « Cette carte est suspendue. Réactivez-la d’abord… » |
| `PreActive` (PA) | ❌ 400 | ❌ 400 | ❌ 400 « Cette carte n’a pas encore été activée. Rechargez-la une première fois pour commencer à l’utiliser. » |
| `LostOrStolen` / `Deactivated` | ❌ 400 | ❌ 400 | ❌ 400 |

⚠️ **ÉCART 1** : la description Swagger affirme qu'« une carte non encore activée se bloque aussi » ; le code la refuse (`ALLOWED[PreActive] = ['CREDIT']`).
⚠️ **ÉCART 2 (piège UX)** : une carte **suspendue** ne peut pas être déclarée perdue directement. Pour déclarer perdue une carte suspendue : `Active` d'abord, puis `LostOrStolen` (deux appels). Prévoyez-le dans le parcours « J'ai perdu ma carte ».

**Séquence serveur.** Propriété → gamme → fiche émetteur **fraîche** → contrôle de transition → accusé pour `LostOrStolen` → last4 → téléphone (celui de l'émetteur fait foi) → opération `PROCESSING` (montant 0, rôle `MAIN`) → appel émetteur → mise à jour de notre copie + opération `SUCCESS` → notification (déclaration de perte : email **et** SMS, modèle `card-lost-declared`).

**UX déclaration de perte.** Afficher un avertissement explicite (« définitif, même retrouvée ») avant d'envoyer `acknowledgeIrreversible: true`, puis rassurer : **les fonds ne sont pas perdus**, ils seront transférés sur une nouvelle carte avec le support. Après succès, la session reste valide mais plus aucune opération n'est possible sur la carte (lectures en 400).

**Erreurs.**

| Statut | code | message | Quoi faire |
|---|---|---|---|
| 400 | VALIDATION_FAILED | `newStatus` hors liste, identifiant invalide, champ inconnu | Inline |
| 403 | FORBIDDEN | carte hors session | Bug / reconnexion |
| 400 | CARD_TIER_* | gamme | Rare |
| 400 | REQUEST_REJECTED | carte connue perdue/désactivée (avant appel émetteur) : « Cette carte a été déclarée perdue ou volée. Contactez le support… » | Écran support |
| 404 | NOT_FOUND | « Aucune carte ne correspond à l'identifiant … » | Support |
| 400 | REQUEST_REJECTED | « Cette carte est déjà dans l’état demandé. » | Rafraîchir l'état |
| 400 | REQUEST_REJECTED | « Une carte déclarée perdue ou volée ne peut plus être remise en service, même retrouvée. Contactez le support… » / « Cette carte a été désactivée. Seul le support peut intervenir. » | Écran support |
| 400 | REQUEST_REJECTED | refus de transition émetteur (PA / IA→LostOrStolen, cf. tableau) | Guider (réactiver d'abord, recharger d'abord) |
| 400 | REQUEST_REJECTED | « Cette déclaration est DÉFINITIVE : … Confirmez en posant « acknowledgeIrreversible » après avoir averti le porteur. » | Afficher l'avertissement puis renvoyer avec `true` |
| 400 | REQUEST_REJECTED | « Numéro de téléphone requis : fournissez-le pour identifier la carte. » / « Numéro de téléphone inexploitable : « … ». » | Renvoyer avec `phoneCountryCode` + `phoneNumber` |
| 503 | PROVIDER_UNAVAILABLE | last4 indisponible | Réessayer |
| 500 | INTERNAL_ERROR | « Impossible de joindre l'émetteur… » / « Le changement d'état a échoué : … » (opération `FAILED`) | Réessayer ; pour une perte, proposer aussi le support |

---

### 14. Affichage sécurisé des données de carte (PAN / expiration / CVV)

#### 14.1 Vue d'ensemble

```
App KONEKT ──(1) POST /api/v1/cards/display/authorize  [Bearer porteur]
           ◄── { displayUrl, expiresAt, expiresInSeconds: 60 }
App ──(2) charge displayUrl dans une WebView / iframe (≤ 60 s, une seule fois)
Navigateur ──(3) GET /api/v1/card-display?t=<jeton>   [public, jeton consommé]
           ◄── page HTML (VGS Show) qui récupère PAN/exp/CVV directement depuis le coffre VGS
Option web ──(0) <script src="/api/v1/card-display/sdk.js"> puis CardConnectDisplay.mount('#zone', displayUrl)
```

Les données de carte ne transitent ni par l'app ni par nos serveurs : elles vont du coffre (VGS) au cadre affiché. L'app ne reçoit qu'une adresse.

#### 14.2 `POST /api/v1/cards/display/authorize`

**But.** Obtenir une adresse d'affichage **à usage unique, valable 60 s**, pour la carte de session.

**Auth.** `@UseGuards(AuthGuard)`, `@AllowedActors('customer','merchant','internal')`, `@RequireMerchantPermissions('merchant:card:read-sensitive-info')` (sans effet porteur), `@HttpCode(200)`. Pas de throttle (plafonds métier ci-dessous).

**Body (`RequestDisplayDto`)**

| Champ | Type | Requis | Validation | Exemple |
|---|---|---|---|---|
| `cardCustomerId` | string | oui | `@IsString @IsNotEmpty` (**pas** de normalisation ni regex : envoyer exactement l'identifiant de session) | `"121436474"` |
| `cardTierSlug` | string | non | `@IsOptional @IsString @IsNotEmpty` | — |
| `surface` | objet | non (porteur) | `@ValidateNested`, `DisplaySurfaceDto` | **à omettre** pour KONEKT |
| `surface.kind` | enum | oui si `surface` | `@IsIn(['WEB','NATIVE_APP'])` | `"NATIVE_APP"` |
| `surface.domain` | string | oui si `kind = WEB` | `@IsString @IsNotEmpty @MaxLength(253)` | `"app.cardkonekt.bj"` |

Exemple KONEKT :
```json
{ "cardCustomerId": "121436474" }
```

**Réponse 200 (`AuthorizeDisplayResponseDto`)**

```json
{
  "success": true,
  "displayUrl": "https://api.card-connect.bestcash.me/api/v1/card-display?t=xK7fQ2…",
  "expiresAt": "2026-10-15T09:15:22.000Z",
  "expiresInSeconds": 60
}
```

**Règles métier (`CardDisplayTokenService.issue`), dans l'ordre :**
1. **Propriété** : `encryptSearchable(cardCustomerId) === requester.id`, sinon 403 « Vous ne pouvez afficher que votre propre carte. » Le porteur n'a **pas** à déclarer de surface ni de domaine (`_assertSurfaceDeclared` n'est appelé que pour marchand/clé).
2. Résolution de la gamme.
3. **Plafonds sur 24 h glissantes** :
   - par carte : `CARD_DISPLAY_MAX_PER_CARD_PER_DAY` (défaut **20**) jetons émis → 403 « Cette carte a été consultée trop de fois aujourd’hui. Réessayez demain. » ;
   - par marchand : `max(50, nbCartesDuMarchand × CARD_DISPLAY_DAILY_RATIO_PER_CARD (défaut 3))`. ⚠️ Pour un porteur, le « marchand » est le **marchand de session** (souvent le marchand régional par défaut, partagé par toute une région) : les affichages de **tous** ses porteurs s'additionnent, rapportés aux cartes **vendues** par ce marchand. Risque réel de 403 « Votre volume de consultations est inhabituellement élevé et a été suspendu par précaution. Contactez-nous. » pour des porteurs innocents — à surveiller / à remonter à l'équipe API.
   - Chaque appel à `authorize` compte, même si la page n'est jamais ouverte : **n'appelez `authorize` qu'au tap sur « Afficher »**, pas en préchargement.
4. Fiche émetteur (cache 5 s) : `LostOrStolen` / `Deactivated` → 403 « Les données de cette carte ne peuvent plus être affichées : elle a été bloquée. » (ou 400 si déjà connue terminale en base). `PreActive` et `Inactive` restent affichables.
5. last4 requis (503 si absent chez l'émetteur).
6. Jeton aléatoire 32 octets (stocké haché), `surfaceKind` = `surface.kind` ou **`WEB` par défaut**, `allowedDomain` = domaine normalisé si `kind = WEB` avec domaine, sinon `null`. IP et User-Agent enregistrés.
7. `displayUrl = <CARD_DISPLAY_PAGE_URL>?t=<jeton>`.

⚠️ **Ne pas envoyer `surface: { kind: "WEB", domain: … }` depuis l'app mobile** : cela active, à l'ouverture de la page, le contrôle d'origine par `Referer` ; une WebView native n'en envoie généralement pas → 403 « Origine non vérifiable. ». En omettant `surface` (ou avec `NATIVE_APP`), `allowedDomain = null` : pas de contrôle d'origine ni d'en-tête `frame-ancestors`. Pour une **version web** de KONEKT, envoyer `surface: { kind: "WEB", domain: "<domaine de l'app web>" }` est recommandé (CSP `frame-ancestors` + contrôle du Referer) ; pour un porteur, ce domaine n'a pas à être pré-déclaré.

⚠️ **À vérifier en configuration** : la valeur par défaut de `CARD_DISPLAY_PAGE_URL` est `https://dev-api.card-connect.bestcash.me/card-display` **sans** `/api/v1`, alors que la route est servie sous `/api/v1/card-display`. Si la configuration de l'environnement n'a pas été ajustée (ou si nginx ne réécrit pas), la page renverra 404. L'app doit toujours utiliser `displayUrl` tel quel (ne pas le reconstruire).

**Erreurs.**

| Statut | code | message | Quoi faire |
|---|---|---|---|
| 400 | VALIDATION_FAILED | `cardCustomerId` vide, `surface` invalide, champ inconnu | Corriger |
| 403 | FORBIDDEN | « Vous ne pouvez afficher que votre propre carte. » | Bug / reconnexion |
| 400 | CARD_TIER_* / 404 gamme | gamme | Rare |
| 403 | FORBIDDEN | « Cette carte a été consultée trop de fois aujourd’hui. Réessayez demain. » | Message + désactiver le bouton |
| 403 | FORBIDDEN | « Votre volume de consultations est inhabituellement élevé… Contactez-nous. » | Message + support |
| 403 | FORBIDDEN | « Les données de cette carte ne peuvent plus être affichées : elle a été bloquée. » | Écran carte bloquée |
| 400 | REQUEST_REJECTED | carte connue perdue/désactivée | Écran carte bloquée |
| 404 | NOT_FOUND | « Aucune carte ne correspond à l'identifiant … » | Support |
| 503 | PROVIDER_UNAVAILABLE | last4 indisponible | Réessayer plus tard |
| 500 | INTERNAL_ERROR | émetteur injoignable | Réessayer |

#### 14.3 `GET /api/v1/card-display?t=<jeton>` — Page d'affichage (publique)

**But.** Page HTML chargée par la WebView/iframe. **Non authentifiée** (pas d'`AuthGuard` ni d'`@AllowedActors`) : c'est le jeton `t` qui autorise. Exclue de Swagger.

**Query.** `t` (string, obligatoire) — le jeton de `displayUrl`. Ne jamais journaliser ni conserver l'URL.

**Contrôles (`CardDisplayTokenService.consume`).**
1. `t` absent → **400** page « Lien incomplet. »
2. Jeton inconnu → page d'erreur « Lien d’affichage invalide. »
3. Déjà consommé → « Ce lien a déjà servi. Redemandez l’affichage. » (**un rechargement de page échoue** : c'est voulu).
4. Expiré (> 60 s après émission) → « Ce lien a expiré. Redemandez l’affichage. »
5. Si `allowedDomain` : `Referer` absent → « Origine non vérifiable. » ; domaine du Referer différent (sous-domaines acceptés) → « Origine non autorisée. »
6. Consommation atomique (deux chargements simultanés : le second → « Ce lien vient d’être utilisé. »).

Toute erreur de consommation est rendue en **HTML, statut 403** (même pour les cas « expiré »/« déjà servi ») — pas de JSON. La page d'erreur affiche un cadenas et le message (échappé).

**Succès : 200 `text/html`**, en-têtes : `Cache-Control: no-store, no-cache, must-revalidate`, `Pragma: no-cache`, `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`, et `Content-Security-Policy: frame-ancestors https://<domaine> https://*.<domaine>` seulement si un domaine web a été déclaré.

**Contenu de la page.** Charge `https://js.verygoodvault.com/vgs-show/2.2.2/show.js`, affiche « Chargement des données sécurisées… », puis trois champs VGS (Numéro de carte formaté `#### #### #### ####`, Expiration, CVV) chacun avec un bouton de copie VGS (`⧉`) ; la requête au coffre envoie `last4Digits` et `PROGRAMID`. Messages d'échec internes : « Le composant sécurisé n'a pas pu être chargé. Vérifiez votre connexion. », « Les données de cette carte n'ont pas pu être récupérées. », « Le chargement a pris trop de temps. Réessayez. » (après 15 s), « Une erreur est survenue à l'affichage des données. » Fond transparent, hauteur conseillée ≥ 180 px.

**Côté app mobile (WebView).**
- Charger `displayUrl` **immédiatement** (< 60 s) et **une seule fois** ; désactiver le rechargement automatique / la restauration d'état de la WebView (sinon page « déjà servi »).
- JavaScript activé ; accès réseau à `js.verygoodvault.com` et au domaine VGS.
- Le presse-papiers est rempli par les boutons VGS (pas par l'app).
- À la fermeture de l'écran : détruire la WebView (les données restent affichées sinon). Pour réafficher : nouvel appel `authorize`.
- Empêcher les captures d'écran sur cet écran (FLAG_SECURE Android / masquage iOS) — recommandation, non imposée par l'API.

#### 14.4 `GET /api/v1/card-display/sdk.js` — Script d'intégration (public)

**But.** Script JavaScript sans secret pour les intégrations **web** (React/Vue/vanilla). Public, `Content-Type: application/javascript; charset=utf-8`, `Cache-Control: public, max-age=3600`. Exclu de Swagger.

**API exposée** : `window.CardConnectDisplay`
- `mount(target, displayUrl, options?)` : `target` = sélecteur CSS ou élément ; supprime d'abord tout cadre précédent du conteneur (évite de consommer deux autorisations) ; crée un `<iframe sandbox="allow-scripts">` (**sans** `allow-same-origin` : la page hôte ne peut pas lire le contenu), `width: 100%`, `min-height` = `options.minHeight` ou 180 px, sans bordure, fond transparent. `options.onReady()` sur `load`, `options.onError(err)` sur `error`. Lève `Error` si conteneur introuvable ou `displayUrl` manquant. Retourne `{ unmount() }`.
- `unmount(target)` : retire les iframes `[data-cardconnect-display]` du conteneur — **à appeler quand la vue disparaît**.

Exemple (KONEKT web) :
```html
<script src="https://<hôte-api>/api/v1/card-display/sdk.js"></script>
<div id="card-secure"></div>
<script>
  const { displayUrl } = await api.post('/api/v1/cards/display/authorize', {
    cardCustomerId: session.cardCustomerId,
    surface: { kind: 'WEB', domain: location.hostname }
  });
  const handle = CardConnectDisplay.mount('#card-secure', displayUrl, {
    minHeight: 220,
    onError: () => showToast("L'affichage n'a pas pu être chargé.")
  });
  // en quittant l'écran : handle.unmount();
</script>
```

Note : le commentaire d'en-tête du SDK cite `POST /cards/display/authorize` sans le préfixe ; l'URL réelle est `/api/v1/cards/display/authorize`. Pour le porteur, le SDK peut être appelé depuis le front (le jeton de session porteur n'est pas une clé partenaire) ; la règle « demander depuis votre serveur » vise les marchands munis d'une clé d'accès.

#### 14.5 Routes `cards/display/domains` (hors porteur)

`GET/POST/DELETE /api/v1/cards/display/domains[/:domainId]` : `@AllowedActors('merchant','internal'[,'admin'])` — **inaccessibles au porteur** (403). Inutiles pour KONEKT.

---

### 15. Routes du contrôleur cartes FERMÉES au porteur (pour mémoire)

| Route | Acteurs | Résultat avec un jeton porteur |
|---|---|---|
| `POST /api/v1/cards/issue/virtual` | merchant, internal | 401 « Jeton non reconnu pour cette route. Reconnectez-vous. » (aucun acteur admis ne reconnaît ce jeton) |
| `POST /api/v1/cards/issue/physical` | merchant, internal | idem |
| `POST /api/v1/cards/credit` | merchant, internal | idem |
| `POST /api/v1/cards/debit/initiate` | merchant, internal | idem |

L'achat d'une carte et la recharge par mobile money en libre-service passent par le **catalogue/commerce** (hors périmètre). Aucune route du contrôleur cartes n'est publique (classe sous `@UseGuards(AuthGuard)`) ; les seules routes publiques du périmètre sont `GET /api/v1/card-display` et `GET /api/v1/card-display/sdk.js`.

---

---

# Partie 5 — Catalogue et paiements en libre-service

> Services vendus dans Konekt (crédit, forfaits, électricité, TV, retrait au guichet, recharge de carte depuis un Mobile Money) : consultation, devis, confirmation, suivi.
>
> Les renvois « § » désignent les sections de cette partie ; « §0.x » renvoie à la Partie 1 (conventions) et à la Partie 2 (authentification).

### 1. Vue d'ensemble du parcours

```
           (facultatif) GET /catalog/services            ← quels services / moyens de paiement / frais
                        GET /catalog/services/{key}?amount=…
                                    │
             consultation fournisseur (sans engagement)
   GET /catalog/lookup/mobile/{msisdn}/products?type=…   (crédit / forfaits)
   GET /catalog/lookup/electricity/{ref}/invoices        (factures SBEE)
   GET /catalog/lookup/tv/{numCard}/current | /offers    (Canal+)
                                    │
                         POST /catalog/quote             ← devis : prix figé, vérifications, display
                                    │   (feasible=false → afficher reason, corriger)
                         GET  /catalog/quote/{quoteId}   ← relecture (rechargement d'écran)
                                    │
                         POST /catalog/confirm           ← paiement + exécution
               ┌────────────────────┼─────────────────────────────┐
     CUSTOMER_CARD (+ pin)   CUSTOMER_EXTERNAL_CHANNEL      CUSTOMER_EXTERNAL_CHANNEL
     → completed:true          awaiting=PAYER_APPROVAL         awaiting=CONFIRMATION_CODE (B-MO)
       status SUCCESS          → attendre (polling)            → POST /commerce/operations/{id}/funding/confirm
                                                               → ou …/funding/cancel
                                    │
               GET /cards/operations/{operationId}  (annexe — suivi, toutes les 10 s)
```

Délais par défaut : devis valable **10 min** (`QUOTE_VALIDITY_MINUTES`) ; attente de validation
téléphone **10 min** (`BCP_CALLBACK_TIMEOUT_MINUTES`) ; attente du code B-MO **15 min**
(`BMO_CODE_TIMEOUT_MINUTES`) ; attente d'un verdict B-MO muet **35 min** (`BMO_SETTLEMENT_TIMEOUT_MINUTES`).

---

### 2. Règles transverses (devis, frais, paiement)

#### 2.1 Services (« sellables ») accessibles au porteur

Liste blanche `CUSTOMER_ALLOWED_SELLABLES` (`src/_commerce/customer-scope.service.ts`) croisée avec
les moyens de paiement déclarés par chaque vendeur (`serviceSlugs`). Le porteur ne peut **jamais**
payer par `MERCHANT_WALLET` (403 `FUNDS_SOURCE_NOT_ALLOWED`). Il faut en outre que le **marchand de
session** ait souscrit au service correspondant (sinon 403 « … n'est pas activé sur votre compte »).

| `service` (clé) | Libellé | Montant | Sources porteur → slug de service tarifé | Contrat `input` |
|---|---|---|---|---|
| `mobile-topup` | Recharge téléphonique | FREE (`input.amount`) | `CUSTOMER_CARD` → `merchant:addon:sell-mno-airtime:from-card` ; `CUSTOMER_EXTERNAL_CHANNEL` → `merchant:addon:sell-mno-airtime:from-bcp` | `MobileTopupInputDto` |
| `mobile-data` | Forfait internet | IMPOSED | `…:sell-mno-data:from-card` ; `…:sell-mno-data:from-bcp` | `MobileDataInputDto` |
| `electricity-prepaid` | Électricité prépayée | FREE | `…:sell-electricity-prepaid:from-card` ; `…:from-bcp` | `ElectricityPrepaidInputDto` |
| `electricity-postpaid` | Facture d'électricité | IMPOSED | `…:sell-electricity-postpaid:from-card` ; `…:from-bcp` | `ElectricityPostpaidInputDto` |
| `tv-subscription` | Abonnement télévision | IMPOSED | `…:sell-tv-subscription:from-card` ; `…:from-bcp` | `TvSubscriptionInputDto` |
| `cash-withdrawal` | Retrait au guichet | FREE | `merchant:addon:atm:from-card` ; `merchant:addon:atm:from-bcp` | `CashWithdrawalInputDto` |
| `wallet-to-card` | Recharge de carte depuis un portefeuille mobile | FREE | **uniquement** `CUSTOMER_EXTERNAL_CHANNEL` → `merchant:card:wallet-to-card` | `WalletToCardInputDto` |
| `payout-to-external`* | Versement vers un portefeuille externe | FREE | `CUSTOMER_CARD` → `merchant:external-wallet:payout:from-card` | (pas de contrat — voir annexe) |
| `external-to-external`* | Transfert entre portefeuilles externes | FREE | `CUSTOMER_EXTERNAL_CHANNEL` → `merchant:external-wallet:transfer` | (pas de contrat) |
| `collect-from-external`* | Encaissement depuis un portefeuille externe | FREE | `CUSTOMER_EXTERNAL_CHANNEL` → `merchant:external-wallet:collect` | (pas de contrat) |

\* Enregistrés au même registre, donc techniquement acceptés par `POST /catalog/quote`, mais conçus
pour les routes dédiées `/external-wallets/*` (hors périmètre). À ne pas utiliser via `/catalog`
dans Konekt (voir §6).

**Refusés au porteur** : `card-purchase` (réservé au visiteur — 403 `SERVICE_NOT_SELF_SERVICE`,
« Ce service n'est pas disponible depuis votre application. Rendez-vous chez un marchand. »).

#### 2.2 Contrats `input` par service (validation à l'entrée)

Le contrôleur valide `input` avec la classe du service (`SELLABLE_INPUT_CONTRACTS`). En cas d'erreur :
**400, `code: "REQUEST_REJECTED"`** (et non `VALIDATION_FAILED`), message :
`Données invalides pour le service « <service> » — input.<champ> : <message> ; …`.

**FREE** : le montant va dans `input.amount` (entier, 1 – 1 000 000). Le `amount` à la racine est
déprécié (entier 100 – 1 000 000), encore accepté avec l'avertissement
« `amount` à la racine est déprécié pour ce service : placez-le dans `input.amount`. ».
**IMPOSED** : aucun montant transmis au vendeur ; un montant fourni est ignoré avec l'avertissement
« Montant ignoré : le prix de ce service est fixé par le fournisseur et appliqué d'office. ».
`amount` est retiré de `input` avant transmission au vendeur.

##### `mobile-topup` — `MobileTopupInputDto`
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `beneficiary` | string | oui | `IsString`, `IsNotEmpty`, `MaxLength(20)` ; normalisé au devis (`+229…`, `229…`, `00229…`, `01XXXXXXXX`) | `"+2290196666262"` |
| `productId` | string | oui | `IsString`, `IsNotEmpty`, `MaxLength(40)` — `id` rendu par le lookup `type=TOPUP` | `"17"` |
| `amount` | int | conditionnel | `IsOptional`, `IsInt` (« Montant entier attendu (le franc CFA n'a pas de centimes). »), `Min(1)`, `Max(1000000)`. Obligatoire si le produit est `RANGE` ; ignoré (remplacé par `price`, avertissement) si `FIXED` | `1000` |

##### `mobile-data` — `MobileDataInputDto`
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `beneficiary` | string | oui | `IsNotEmpty`, `MaxLength(20)` | `"+2290196666262"` |
| `productId` | string | oui | `IsNotEmpty`, `MaxLength(40)` — `id` du lookup `type=DATA` | `"18472"` |

##### `electricity-prepaid` — `ElectricityPrepaidInputDto`
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `meterNum` | string | oui | `Matches(/^\d{6,20}$/)` — « meterNum : chiffres uniquement. » | `"01234567890"` |
| `recipientChannel` | `"whatsapp" \| "email"` | oui | `IsIn(['whatsapp','email'])` | `"whatsapp"` |
| `recipientContact` | string | oui | `IsNotEmpty`, `MaxLength(120)` ; au devis : e-mail `/^[^@\s]+@[^@\s]+\.[^@\s]+$/` ou numéro `/^\+?\d{8,15}$/` (espaces/tirets retirés) | `"+2290167123456"` |
| `amount` | int | **oui (métier)** | `IsOptional` au DTO, mais devis refusé sans lui (« Indiquez le montant d'électricité à acheter. ») ; 1 – 1 000 000 | `5000` |

##### `electricity-postpaid` — `ElectricityPostpaidInputDto`
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `customerReference` | string | oui | `IsNotEmpty`, `MaxLength(40)` | `"610201551642KA"` |
| `invoiceReferences` | string[] | non | `IsArray`, `ArrayMaxSize(50)`, `IsString({each})`. Absent/vide ⇒ **toutes** les impayées | `["FAC-2026-07-0042"]` |

##### `tv-subscription` — `TvSubscriptionInputDto`
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `numCard` | string | oui | `Matches(/^[A-Za-z0-9]{8,20}$/)` — « numCard : lettres et chiffres uniquement. » | `"24100027499297"` |
| `mainOffer` | string | non | `MaxLength(40)`. Absent ⇒ **reconduction** de l'offre en cours ; présent ⇒ changement de bouquet | `"ACCESS"` |
| `duration` | string | si `mainOffer` | `MaxLength(20)` ; obligatoire (métier) avec `mainOffer` (« Choisissez une durée pour ce bouquet avant de poursuivre. ») | `"1"` |
| `optionsList` | string | non | `MaxLength(200)`, codes séparés par virgules, `""` si aucun | `"OPT_SPORT,OPT_CINEMA"` |

##### `cash-withdrawal` — `CashWithdrawalInputDto`
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `deliveryChannel` | `"SMS" \| "EMAIL" \| "WHATSAPP"` | oui | `IsEnum(DeliveryChannel)` | `"SMS"` |
| `beneficiaryContact` | string | oui | `IsNotEmpty`, `MaxLength(120)` ; au devis : e-mail si `EMAIL`, sinon `/^\+?\d{8,15}$/` | `"+2290167123456"` |
| `beneficiaryName` | string | non | `MaxLength(120)` | `"Kossi Adjovi"` |
| `pin` | string | non | `Matches(/^\d{4}$/)` — « pin : quatre chiffres. » Fourni ⇒ **non transmis** au bénéficiaire (le porteur le communique lui-même) ; absent ⇒ engendré et envoyé avec le code | `"4829"` |
| `amount` | int | **oui (métier)** | 1 – 1 000 000 | `10000` |

##### `wallet-to-card` — `WalletToCardInputDto`
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `cardCustomerId` | string | oui | `IsNotEmpty`, `MaxLength(40)` — **doit être la carte de session** (sinon 403) | `"121436474"` |
| `cardTierSlug` | string | non | `IsNotEmpty` si présent, `MaxLength(80)` ; retrouvée sinon | `"virtual:uba-bj:visa-prepaid-card:6-month"` |
| `amount` | int | **oui (métier)** | 1 – 1 000 000 | `5000` |

#### 2.3 Calcul des frais en libre-service

Mode d'initiation : `customer` (et `visitor`) ⇒ `OperationInitiationMode.CUSTOMER_SELF_SERVICE`
(`QuoteService._resolveInitiationMode`, identique dans `ServiceOfferService`). Il est figé sur le devis et l'opération.

**Frais internes** (`FeeCalculatorService.calculate`) — sur le **slug du service tarifé** (dépend de la source, cf. §2.1) :
1. Candidats : tarifs actifs, non « parrainage seulement », `initiationMode ∈ {CUSTOMER_SELF_SERVICE, MERCHANT_ASSISTED}`
   (repli comptoir), `merchantId ∈ {marchand de session, null}`, `cardTierSlug = null` (le devis catalogue ne
   transmet **aucune gamme**), et dont la plage couvre le montant (`exact`, `min/max`).
2. Classement : canal exact +8, gamme +4, marchand +2, montant exact +1 → le meilleur gagne.
3. `FIXED` → valeur ; `PERCENTAGE` → % du montant ; arrondi à 2 décimales.
4. **Aucune grille ne couvre le montant ⇒ 404 `NOT_FOUND`** « Aucun tarif applicable pour <service> — montant X,
   canal CUSTOMER_SELF_SERVICE. La grille ne couvre pas ce montant. » (c'est une exception, pas un `feasible:false`).
   Tarif % aberrant ⇒ 400 « Tarif de ce service mal configuré… ».

**Frais du prestataire de paiement** (`ExternalFeeService.estimate`) — seulement si `CUSTOMER_EXTERNAL_CHANNEL` :
grille COLLECT du canal (et du pays). `isAllowedToCharge=true` ⇒ `externalFeeAdvanced` (ajouté au débit) ;
sinon `externalFeeWithheld` (retenu par le prestataire, **non ajouté** au débit). Pas de grille ⇒ 0 (journalisé).
`CUSTOMER_CARD` ⇒ 0 frais externes.

**Montants** (`QuoteService._computeAmounts`, source porteur) :
- `amountDebited = amount + internalFee + externalFeeAdvanced` (ce que la carte / le portefeuille paie) ;
- `amountCredited = amount` (ce que reçoit le bénéficiaire).
- Arrondis à 2 décimales ; devise `"xof"`.

À afficher : `amountDebited` au payeur, `amountCredited` au bénéficiaire, jamais `amount` seul.

> ⚠️ Bornes affichées par `GET /catalog/services` (`limits.minAmount/maxAmount`, table `ServiceAmountLimit`,
> défauts 1 000 / 10 000 000) **ne sont pas contrôlées au devis**. Seuls comptent : la couverture de la grille
> de frais (404), les bornes du produit opérateur (`mobile-topup`), et le contrat d'entrée (≤ 1 000 000).

#### 2.4 Comment le porteur paie

| Source | Preuve exigée | Synchrone ? |
|---|---|---|
| `CUSTOMER_CARD` | **Code secret (PIN) du porteur, 6 chiffres**, dans `pin` de `POST /catalog/confirm`. Pas d'OTP, pas d'appel `card-consent`. Carte = **carte de session** uniquement. Carte émise hors plateforme (pas de `kycId`) ⇒ paiement par carte impossible. | Oui : débit + exécution dans l'appel → `completed: true` |
| `CUSTOMER_EXTERNAL_CHANNEL` | Validation chez l'opérateur : `PAYER_APPROVAL` (validation sur le téléphone — agrégateur BCP) ou `CONFIRMATION_CODE` (B-MO direct : code SMS à saisir via `/commerce/operations/{id}/funding/confirm`). | Non : `completed: false`, `status: PENDING` |

Vérification du PIN (`CustomerPinService.verifyPin`) : `CUSTOMER_PIN_MAX_ATTEMPTS` (défaut 5) essais, puis
verrou `CUSTOMER_PIN_LOCK_MINUTES` (défaut 15 min). Erreurs (sans code dédié → `code` déduit) :
- 403 `FORBIDDEN` « Code incorrect — N tentative(s) restante(s). »
- 403 `FORBIDDEN` « Trop de codes erronés. Votre compte est bloqué pendant 15 minutes. Vous pouvez aussi réinitialiser votre code. »
- 403 `FORBIDDEN` « Trop de codes erronés. Réessayez dans N minute(s), ou réinitialisez votre code. »
- 400 `REQUEST_REJECTED` « Aucun code secret n'a encore été défini pour ce compte. »

> ⚠️ Le PIN est vérifié **dans le contrôleur, avant tout autre contrôle** (y compris rejeu, existence du devis).
> Un appel de confirmation par carte avec un mauvais PIN consomme un essai même si le devis est expiré.

#### 2.5 Statuts

- Devis (`QuoteStatus`) : `OPEN` (confirmable), `CONSUMED`, `EXPIRED`, `REJECTED` (refusé à l'établissement).
- Opération (`OperationStatus`) vus par l'app : `PENDING` (attente du payeur), `PROCESSING` (exécution en cours /
  en revue), `SUCCESS`, `FAILED`, `REFUNDED` (échec + remboursé), `CANCELLED`, `EXPIRED`.
- `awaiting` (si `PENDING`) : `PAYER_APPROVAL` | `CONFIRMATION_CODE` | `PROVIDER_SETTLEMENT`.

#### 2.6 Idempotence (`reference`) — règles et pièges

- Si `reference` est fourni, `POST /catalog/confirm` cherche d'abord une opération `(merchantId du devis, reference)` ;
  si elle existe, **rend son état actuel** (rejeu, sans nouvelle vente, sans consommer le devis).
- Deux confirmations simultanées avec la même `reference` : la seconde reçoit 400 `REQUEST_REJECTED`
  « Une vente portant la référence « … » est déjà en cours de traitement. »
- ⚠️ **Piège libre-service** : la clé est `(marchand de session, reference)` et le rejeu **ne vérifie pas l'auteur**.
  Tous les porteurs d'un même marchand de session partagent l'espace de références : une référence prévisible
  (« KONEKT-1 ») pourrait renvoyer l'opération d'un autre porteur ou bloquer la sienne. **Générer un UUID v4
  par tentative de paiement**, le conserver localement, et le réutiliser uniquement pour rejouer la même tentative.
- Pour un paiement par carte, le rejeu exige à nouveau le PIN (vérifié avant la détection du rejeu).

---

### 3. Routes

#### 3.1 `GET /api/v1/catalog` — liste du catalogue (DÉPRÉCIÉE)

**But** : services vendables pour l'organisation, avec les moyens de paiement acceptés. Remplacée par `GET /catalog/services`.

**Auth** : `@AllowedActors('merchant','internal','customer','admin','visitor')` ; Bearer porteur ; aucune permission.

**Paramètres** : aucun.

**Réponse 200** (`CatalogListResponseDto`) :
```json
{
  "success": true,
  "data": [
    { "key": "mobile-topup", "label": "Recharge téléphonique", "fundsSources": ["MERCHANT_WALLET", "CUSTOMER_CARD", "CUSTOMER_EXTERNAL_CHANNEL"] },
    { "key": "wallet-to-card", "label": "Recharge de carte depuis un portefeuille mobile", "fundsSources": ["CUSTOMER_EXTERNAL_CHANNEL"] }
  ]
}
```
- `key: string`, `label: string`, `fundsSources: QuoteFundsSource[]`.

**Règles** (`ServiceAccessService.listSellableFor`) : pour un porteur, filtre **uniquement** sur les souscriptions
du marchand de session — **pas** sur la liste blanche libre-service ni sur l'exclusion de `MERCHANT_WALLET`.
La réponse peut donc contenir `MERCHANT_WALLET`, `card-purchase`, `collect-from-external`… qui seront refusés au devis.
Liste vide si la session n'a pas de marchand.

**Erreurs** : 401 (Partie 1.6 / Partie 2).

**App** : ne pas utiliser ; employer `GET /catalog/services`.

---

#### 3.2 `GET /api/v1/catalog/services` — services, disponibilité et frais (liste)

**But** : tout ce que le porteur peut employer, par moyen de paiement : ouvert ou non (et pourquoi), bornes, frais au montant minimum.

**Auth** : `@AllowedActors('merchant','internal','customer','admin','visitor')` ; aucune permission.

**Query** (`ServiceOfferListQueryDto`) :
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `beneficiaryCountry` | string | non | `IsString`, `Length(2,2)` | `BJ` |
| `availableOnly` | boolean | non | `"true"`/`true` ⇒ vrai, toute autre valeur ⇒ faux | `false` |

**Réponse 200** (`ServiceOfferListResponseDto`) : `{ success, data: ServiceOffer[], count }`.

`ServiceOffer` :
| Champ | Type | Sens |
|---|---|---|
| `key` | string | clé à mettre dans `service` (catalogue) ou slug d'un service carte |
| `label` | string | libellé |
| `kind` | `"CATALOG" \| "CARD_SERVICE"` | `CATALOG` → `POST /catalog/quote` ; `CARD_SERVICE` → routes `/cards` (hors périmètre) |
| `category` | string \| null | ex. `ENERGY` |
| `amountMode` | `"FREE" \| "IMPOSED" \| "NONE"` | montant saisi / imposé / sans montant |
| `countryCodes` | string[] | `["*"]` = partout |
| `available` | boolean | au moins une option ouverte |
| `unavailableReason` | string \| null | motif de la 1re option si tout est fermé |
| `options[]` | `OfferOption[]` | une par moyen de paiement |
| `cardTiers?` | — | détail seulement, services carte |

`OfferOption` : `fundsSource` (`QuoteFundsSource` \| null pour un service carte), `serviceSlug`, `available`,
`unavailableReason`, `limits { minAmount, maxAmount }`, `fee` (`OfferFee` \| null si `amountMode: NONE`),
`estimates?` (détail sans `amount`).

`OfferFee` : `amount`, `fee` (frais internes), `externalFee` (number \| null — null tant que le canal n'est pas
précisé), `amountDebited`, `amountCredited`, `resolved` (false ⇒ grille absente : ne pas afficher « gratuit »).

**Règles de filtrage pour un porteur** (`ServiceOfferService._refusal`) :
- Options masquées (absentes) : `MERCHANT_WALLET` ; services catalogue hors liste blanche libre-service ;
  services carte hors `CUSTOMER_ALLOWED_SERVICES` (`merchant:card:transfer`, `merchant:card:card-to-wallet` ;
  `merchant:card:wallet-to-card` apparaît sous la clé catalogue `wallet-to-card`).
- Options grisées avec motif : pays non desservi (« Non desservi pour un bénéficiaire en BJ. »), santé `DOWN`
  (« Momentanément indisponible — nos équipes travaillent au rétablissement. »), `MAINTENANCE` (« En maintenance. »),
  pas de marchand (« Aucun marchand associé à cette session. »), non souscrit (« Non activé sur votre compte. Contactez votre gestionnaire pour y souscrire. »).
- Frais calculés pour le canal `CUSTOMER_SELF_SERVICE`, au montant minimum ; **ne pas mettre en cache pour un autre acteur**.

**Exemple** :
```json
{
  "success": true,
  "count": 1,
  "data": [
    {
      "key": "electricity-prepaid",
      "label": "Électricité prépayée",
      "kind": "CATALOG",
      "category": "ENERGY",
      "amountMode": "FREE",
      "countryCodes": ["BJ"],
      "available": true,
      "unavailableReason": null,
      "options": [
        {
          "fundsSource": "CUSTOMER_CARD",
          "serviceSlug": "merchant:addon:sell-electricity-prepaid:from-card",
          "available": true,
          "unavailableReason": null,
          "limits": { "minAmount": 1000, "maxAmount": 500000 },
          "fee": { "amount": 1000, "fee": 50, "externalFee": null, "amountDebited": 1050, "amountCredited": 1000, "resolved": true }
        },
        {
          "fundsSource": "CUSTOMER_EXTERNAL_CHANNEL",
          "serviceSlug": "merchant:addon:sell-electricity-prepaid:from-bcp",
          "available": true,
          "unavailableReason": null,
          "limits": { "minAmount": 1000, "maxAmount": 500000 },
          "fee": { "amount": 1000, "fee": 50, "externalFee": null, "amountDebited": 1050, "amountCredited": 1000, "resolved": true }
        }
      ]
    }
  ]
}
```
(NB : sans `externalChannelSlug`, `externalFee` est null et `amountDebited` n'inclut pas les frais du portefeuille.)

**Erreurs** : 400 `VALIDATION_FAILED` (pays ≠ 2 lettres) ; 401.

**App** : appeler au chargement de l'écran « Payer », afficher les options `available:false` grisées avec `unavailableReason`.

---

#### 3.3 `GET /api/v1/catalog/services/{service}` — détail d'un service + frais exacts

**But** : frais exacts pour un montant saisi, ou estimations sur des montants de référence.

**Auth** : idem 3.2.

**Path** : `service` (string) — `key` rendue par la liste, ex. `electricity-prepaid`.

**Query** (`ServiceOfferDetailQueryDto`) :
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `amount` | number | non | `Type(Number)`, `IsNumber`, `IsPositive` | `5000` |
| `fundsSource` | enum | non | `IsEnum(QuoteFundsSource)` | `CUSTOMER_EXTERNAL_CHANNEL` |
| `cardTierSlug` | string | non | `MaxLength(120)` (ignoré pour `kind: CATALOG`) | — |
| `beneficiaryCountry` | string | non | `Length(2,2)` | `BJ` |
| `externalChannelSlug` | string | non | `MaxLength(60)` — `providerSlug` du portefeuille | `bmo` |
| `externalChannelCountry` | string | non | `Length(2,2)` | `BJ` |

**Réponse 200** (`ServiceOfferDetailResponseDto`) = `ServiceOffer` + `success: true` (à plat, pas sous `data`).
- Avec `amount` : `options[].fee` aux frais exacts ; l'option devient `available:false` si
  « Montant hors bornes : entre X et Y XOF. » ou « Les frais (F XOF) absorbent tout le montant : augmentez-le. ».
- Sans `amount` : `options[].estimates[]` sur min, 1 000/5 000/10 000/50 000/100 000/500 000 compris dans les bornes, max (≤ 8).
- Service à prix imposé : passer le prix lu chez le fournisseur en `amount`.

```json
{
  "success": true,
  "key": "mobile-topup",
  "label": "Recharge téléphonique",
  "kind": "CATALOG",
  "category": "TELECOM",
  "amountMode": "FREE",
  "countryCodes": ["BJ"],
  "available": true,
  "unavailableReason": null,
  "options": [
    {
      "fundsSource": "CUSTOMER_EXTERNAL_CHANNEL",
      "serviceSlug": "merchant:addon:sell-mno-airtime:from-bcp",
      "available": true,
      "unavailableReason": null,
      "limits": { "minAmount": 100, "maxAmount": 100000 },
      "fee": { "amount": 5000, "fee": 0, "externalFee": 75, "amountDebited": 5075, "amountCredited": 5000, "resolved": true }
    }
  ]
}
```

**Erreurs** : 404 `NOT_FOUND` « Service « x » inconnu. Employez une clé rendue par GET /catalog/services. » ou
« Le service « x » n'est pas disponible. » (aucune option visible pour ce porteur) ; 400 `VALIDATION_FAILED` ; 401.

**App** : appeler à chaque saisie de montant (debounce). **Le devis reste le seul prix qui engage.**

---

#### 3.4 `POST /api/v1/commerce/quotes/{quoteId}/card-consent` — NON accessible au porteur

`@AllowedActors('merchant','internal')`. Un jeton porteur reçoit **401 `UNAUTHENTICATED`** « Jeton non reconnu
pour cette route. Reconnectez-vous. » (et le service lèverait sinon 403 `ACTOR_NOT_ALLOWED` « … Dans l'application,
le porteur confirme par son code secret. »). **Ne jamais appeler depuis Konekt** : le porteur paie par carte avec son PIN.

---

#### 3.5 Consultations fournisseur (`/api/v1/catalog/lookup/...`)

Communes : `@AllowedActors('merchant','internal','customer')` (+ `@RequireMerchantPermissions('merchant:addon:read-catalogue')`,
**non contrôlée pour un porteur**). Aucun engagement, aucun devis créé, aucun plafond métier.

> ⚠️ Erreurs fournisseur : les clients B-MO lèvent `BmoSvaError` (pas une `HttpException`). Un abonné/carte
> inconnu(e) ou B-MO injoignable sort donc en **500 `INTERNAL_ERROR`** avec le message générique (et non le 404/503
> documenté dans Swagger). L'app doit traiter tout 5xx sur ces routes comme « référence introuvable ou service
> momentanément indisponible — vérifiez la saisie et réessayez ».

##### 3.5.1 `GET /api/v1/catalog/lookup/mobile/{msisdn}/products?type=…`

**But** : produits (crédit / forfaits) offerts sur une ligne.

| Param | Où | Type | Requis | Règles | Exemple |
|---|---|---|---|---|---|
| `msisdn` | path | string | oui | `normalizeMsisdn` : `+` suivi de 8–15 chiffres, `00…`, `229…` (≥ 11 chiffres) ou national `01XXXXXXXX` | `+2290196666262` |
| `type` | query | `TOPUP\|DATA\|COMBO\|MOBILE_PIN` | non | insensible à la casse, défaut `TOPUP` | `DATA` |

**Réponse 200** (`MobileProductsResponseDto`) :
```json
{
  "success": true,
  "data": [
    { "id": "17", "name": "Recharge MTN", "priceType": "RANGE", "price": null, "minPrice": 100, "maxPrice": 30000 },
    { "id": "18472", "name": "166Mo (Self Bundle) - 24Hrs", "priceType": "FIXED", "price": 100, "minPrice": 100, "maxPrice": 100 }
  ]
}
```
`id: string` (→ `input.productId`), `name: string`, `priceType: "FIXED"|"RANGE"`, `price: number|null`, `minPrice`, `maxPrice: number|null`.

**Erreurs** : 400 `REQUEST_REJECTED` « Numéro invalide. Saisissez-le au format international (+22901XXXXXXXX) ou national à dix chiffres (01XXXXXXXX). » ;
400 « type : TOPUP, DATA, COMBO ou MOBILE_PIN. » ; 500 (fournisseur) ; 401.

**App** : `type=TOPUP` pour `mobile-topup`, `type=DATA` pour `mobile-data` (le devis ne cherche **que** dans le catalogue du service demandé).

##### 3.5.2 `GET /api/v1/catalog/lookup/electricity/{customerReference}/invoices`

**But** : nom de l'abonné SBEE et factures impayées.

Path : `customerReference` (string, ex. `610201551642KA`). Pas de validation côté contrôleur.

**Réponse 200** (`ElectricityInvoicesResponseDto`) :
```json
{
  "success": true,
  "data": {
    "referenceAbonne": "610201551642KA",
    "name": "KOSSI ADJOVI",
    "invoices": [
      { "amount": 12500, "month": "09", "year": "2026", "reference": "FAC-2026-09-001" },
      { "amount": 9800, "month": "08", "year": "2026", "reference": "FAC-2026-08-014" }
    ]
  }
}
```
**Erreurs** : 500 (abonné inconnu / fournisseur) ; 401.

**App** : proposer « tout payer » (ne pas envoyer `invoiceReferences`) ou une sélection (`reference` → `input.invoiceReferences`).

##### 3.5.3 `GET /api/v1/catalog/lookup/tv/{numCard}/current`

**But** : offre Canal+ en cours et prix de reconduction.

Path : `numCard` (string, ex. `24100027499297`).

**Réponse 200** (`TvCurrentOfferResponseDto`) :
```json
{ "success": true, "data": { "numCard": "24100027499297", "amount": 5000, "currency": "XOF", "mainOfferLabel": "ACCESS" } }
```
**Erreurs** : 500 (carte inconnue / fournisseur) ; 401.

##### 3.5.4 `GET /api/v1/catalog/lookup/tv/{numCard}/offers`

**But** : bouquets disponibles, durées, options (prix **indicatifs**).

**Réponse 200** (`TvOffersResponseDto`) :
```json
{
  "success": true,
  "data": {
    "numCard": "23900032169299",
    "offersList": [
      {
        "code": "EVASION", "label": "Évasion", "amount": 10000, "currency": "XOF",
        "durationsList": [ { "code": "1", "label": "1 mois" }, { "code": "3", "label": "3 mois" } ],
        "optionsList": [ { "code": "CHR", "label": "Charme", "amount": 3000, "currency": "XOF" } ]
      }
    ]
  }
}
```
`code` → `input.mainOffer` ; `durationsList[].code` → `input.duration` (transmis tel que le fournisseur le rend) ;
`optionsList[].code` → `input.optionsList` (séparés par virgules).

**Erreurs** : 500 ; 401.

---

#### 3.6 `POST /api/v1/catalog/quote` — demander un devis

**But** : « que se passera-t-il si je confirme ? » — vérifie (compteur, abonné, carte, forfait, payeur), interroge
les fournisseurs, fige les prix pour `QUOTE_VALIDITY_MINUTES` (10 min par défaut). **Rien n'est engagé**.

**Auth** : `@AllowedActors('merchant','internal','customer','visitor')`, Bearer porteur. Pas d'idempotence (chaque
appel crée un devis, compté dans le plafond horaire). HTTP 200 (`@HttpCode(OK)`).

**Corps** (`RequestQuoteDto`) :
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `service` | string | oui | `IsString`, `IsNotEmpty` — clé du §2.1 | `"electricity-prepaid"` |
| `amount` | int | non | **déprécié** ; `IsInt`, `Min(100)`, `Max(1000000)` | — |
| `funding` | `FundingDto` | oui | `ValidateNested` | — |
| `funding.source` | enum | oui | `IsIn(QuoteFundsSource)` ; porteur : `CUSTOMER_CARD` ou `CUSTOMER_EXTERNAL_CHANNEL` | `"CUSTOMER_EXTERNAL_CHANNEL"` |
| `funding.card` | `CardFundingDto` | non | **ignoré par le devis** (non transmis au moteur) ; validé s'il est présent | — |
| `funding.card.cardCustomerId` | string | si `card` | `IsNotEmpty` | `"121436474"` |
| `funding.card.cardTierSlug` | string | non | `IsNotEmpty` si présent | — |
| `funding.card.last4` | string | non | `Matches(/^\d{4}$/)` « Quatre chiffres attendus. » | `"4589"` |
| `funding.external` | `ExternalFundingDto` | **oui si `CUSTOMER_EXTERNAL_CHANNEL`** (sinon devis refusé) | `ValidateNested` | — |
| `funding.external.channelSlug` | string | oui | `IsNotEmpty`, `MaxLength(40)`, `Matches(/^\s*[A-Za-z0-9_-]+\s*$/)` « channelSlug : lettres, chiffres, « _ » ou « - » uniquement. » — `providerSlug` de `GET /external-wallets/channels` | `"MOMO"` / `"bmo"` |
| `funding.external.payerIdentifier` | string | oui | `IsNotEmpty` — numéro du payeur (international) | `"+2290167123456"` |
| `funding.external.payerFirstName` | string | **oui sauf B-MO** (métier) | `MaxLength(80)` | `"Kossi"` |
| `funding.external.payerLastName` | string | **oui sauf B-MO** | `MaxLength(80)` | `"Adjovi"` |
| `funding.external.countryCode` | string | non | `MaxLength(2)` — grille tarifaire du prestataire | `"BJ"` |
| `input` | object | oui | `IsObject` + contrat du service (§2.2) | voir exemples |

**Exemple (électricité prépayée payée par MTN MoMo)** :
```json
{
  "service": "electricity-prepaid",
  "funding": {
    "source": "CUSTOMER_EXTERNAL_CHANNEL",
    "external": { "channelSlug": "MOMO", "payerIdentifier": "+2290167123456", "payerFirstName": "Kossi", "payerLastName": "Adjovi", "countryCode": "BJ" }
  },
  "input": { "meterNum": "01234567890", "recipientChannel": "whatsapp", "recipientContact": "+2290167123456", "amount": 5000 }
}
```

**Exemple (forfait internet payé par carte)** :
```json
{
  "service": "mobile-data",
  "funding": { "source": "CUSTOMER_CARD", "card": { "cardCustomerId": "121436474" } },
  "input": { "beneficiary": "0196666262", "productId": "18472" }
}
```

**Ordre des contrôles** (`CatalogController._applyInputContract` → `QuoteService.request`) :
1. Contrat `input` (400 `REQUEST_REJECTED`).
2. Service connu (`SellableRegistry.get`) — sinon 404 « Service « x » inconnu. Disponibles : … ».
3. `assertCanSell` : source supportée (404 « « Label » ne peut pas être payé par ce moyen. ») ; `MERCHANT_WALLET`
   interdit (403 `FUNDS_SOURCE_NOT_ALLOWED` « Le compte du marchand ne peut pas être utilisé depuis l'application. Payez avec votre carte ou votre portefeuille mobile. ») ;
   service actif (404 « « Label » n'est pas disponible actuellement. ») ; session avec marchand (403) ; marchand
   souscrit (403 `FORBIDDEN` « « Label » n'est pas activé sur votre compte. Contactez votre gestionnaire pour y souscrire. »).
4. `CustomerScopeService.assertMaySell` : liste blanche (403 `SERVICE_NOT_SELF_SERVICE`), source (403 `FUNDS_SOURCE_NOT_ALLOWED`
   « Ce moyen de paiement passe par le compte d'un marchand : adressez-vous à un point de vente. »), plafond horaire
   (403 `QUOTE_RATE_LIMIT` « Trop de demandes en peu de temps. Patientez quelques minutes. »).
5. Canal de financement (si externe) — refus en `feasible:false` (voir ci-dessous). B-MO direct : vérification du
   titulaire du numéro (`lookupCustomer`), nom masqué « Prénom I. » dans `display.payerVerifiedName`.
6. Vérifications du vendeur (`feasible:false` + `reason`).
7. Montant résolu > 0 (sinon `feasible:false` « Indiquez le montant de l'opération (input.amount). »).
8. Frais internes (404 si grille absente — §2.3), frais externes, montants, enregistrement du devis `OPEN`.

**Réponse 200** (`QuoteResponseDto`) :
| Champ | Type | Sens |
|---|---|---|
| `success` | boolean | toujours `true` sur 200 |
| `quoteId` | string | à présenter à la confirmation (aussi pour un refus — jamais honorable) |
| `feasible` | boolean | **à lire en premier** ; `false` = refus (montants à 0, ne pas les afficher) |
| `reason` | string? | motif à afficher tel quel (absent si établi) |
| `amount` | number | valeur du service (peut différer de la demande : facture, forfait, abonnement) |
| `internalFee` | number | frais plateforme |
| `externalFeeAdvanced` | number | frais prestataire ajoutés au débit |
| `externalFeeWithheld` | number | frais prestataire retenus (non ajoutés) |
| `amountDebited` | number | **ce que le porteur paiera** |
| `amountCredited` | number | ce que le bénéficiaire recevra |
| `currency` | string | `"xof"` |
| `checks[]` | `{ key, label, passed, detail? }` | vérifications ; `passed:false` désigne le champ à corriger |
| `warnings[]` | string[] | à afficher **avant** confirmation |
| `display` | object? | éléments propres au service (absent sur refus) |
| `expiresAt` | ISO date | échéance |

`display` par service (valeurs réelles produites par les vendeurs, sans projection) :
- `mobile-topup` / `mobile-data` : `productName`, `beneficiary` (normalisé), `priceType`, `price`, `priceRange` (`{min,max}` | null).
- `electricity-prepaid` : `customerName` (titulaire du compteur — **à faire confirmer**), `meterNum`, `estimatedKwh`, `arrears`, `serviceFee`.
- `electricity-postpaid` : `customerName`, `customerReference`, `invoices[] {reference, amount, period "MM/AAAA"}`, `totalDue`, `remainingUnpaid`.
- `tv-subscription` : `numCard`, `offerLabel`, `amount`, `currency`, `isRenewal` ; en changement : `duration`, `options`.
- `cash-withdrawal` : `beneficiaryContact` (masqué), `deliveryChannel`, `validityMinutes`, `expiresAt`, `pinIsProvided`.
- `wallet-to-card` : `holderName`, `cardLast4`, `cardWillReceive`, `requiresPayerApproval: true`.
- Ajoutés par le socle si `CUSTOMER_EXTERNAL_CHANNEL` : `fundingApproval` (`PAYER_APPROVAL`|`CONFIRMATION_CODE`), `payerVerifiedName` (B-MO, si vérifié).

**Exemple — devis établi** :
```json
{
  "success": true,
  "quoteId": "clq8x2k3p0001abcd",
  "feasible": true,
  "amount": 5000,
  "internalFee": 50,
  "externalFeeAdvanced": 75,
  "externalFeeWithheld": 0,
  "amountDebited": 5125,
  "amountCredited": 5000,
  "currency": "xof",
  "checks": [
    { "key": "meter", "label": "Compteur", "passed": true, "detail": "48.2 kWh" },
    { "key": "recipient", "label": "Coordonnées du bénéficiaire", "passed": true, "detail": "WhatsApp" }
  ],
  "warnings": [],
  "display": {
    "customerName": "ADJOVI KOSSI",
    "meterNum": "01234567890",
    "estimatedKwh": 48.2,
    "arrears": 0,
    "serviceFee": 100,
    "fundingApproval": "PAYER_APPROVAL"
  },
  "expiresAt": "2026-10-15T09:24:22.418Z"
}
```

**Exemple — devis refusé (200)** :
```json
{
  "success": true,
  "quoteId": "clq8x2k3p0002abcd",
  "feasible": false,
  "reason": "Ce compteur n’a pas pu être vérifié. Contrôlez le numéro — onze chiffres — et réessayez.",
  "amount": 5000, "internalFee": 0, "externalFeeAdvanced": 0, "externalFeeWithheld": 0,
  "amountDebited": 0, "amountCredited": 0, "currency": "xof",
  "checks": [ { "key": "meter", "label": "Compteur", "passed": false, "detail": "Non reconnu par le fournisseur" } ],
  "warnings": [],
  "expiresAt": "2026-10-15T09:24:22.418Z"
}
```

**Refus `feasible:false` possibles** (motif exact à afficher) :
- Canal externe : absent (« Précisez le portefeuille du payeur (canal et numéro) : c'est lui qui détermine les frais et la façon dont il validera. ») ;
  inconnu/fermé (« Ce portefeuille n'est pas disponible. Choisissez un canal de la liste des portefeuilles. ») ;
  nom manquant hors B-MO (« Le prénom et le nom du payeur sont requis pour <canal> : l'opérateur les exige. ») ;
  numéro sans compte B-MO (« Ce numéro n'a pas de compte <B-MO> : il n'y a rien à prélever… »). B-MO injoignable ⇒ devis
  établi avec l'avertissement « Le titulaire du numéro n'a pas pu être vérifié auprès de … ».
- `mobile-*` : numéro invalide, `productId` absent, opérateur injoignable, produit indisponible sur la ligne, prix/bornes
  illisibles, montant absent (RANGE : « Indiquez le montant à envoyer, entre X et Y XOF. »), hors bornes produit.
- `electricity-prepaid` : contact incohérent (« Adresse électronique invalide pour l'envoi du jeton. » / « Numéro WhatsApp invalide pour l'envoi du jeton. »), montant absent, compteur non vérifiable.
- `electricity-postpaid` : abonné introuvable, aucune facture impayée, factures désignées déjà réglées.
- `tv-subscription` : carte non vérifiable, durée manquante, combinaison indisponible.
- `cash-withdrawal` : contact incohérent, `pin` ≠ 4 chiffres, trop près de minuit (« Trop près de minuit : … Émettez le code demain matin. » — validité restante < 10 min avant 23 h 55 heure du Bénin).
- `wallet-to-card` : carte non précisée, gamme non résolue, carte ne pouvant recevoir (message émetteur).

**Avertissements typiques** : montant remplacé par le prix du forfait ; montant ajusté à la somme des factures ;
arriéré déduit (électricité) ; validité du code de retrait ; code d'accès non transmis ; « Vous recevrez un code de
<B-MO> par SMS : saisissez-le pour valider le paiement. » (B-MO, libre-service) ; « La carte ne sera créditée qu'après… ».

**Erreurs HTTP** :
| HTTP | code | Cas | Action app |
|---|---|---|---|
| 400 | `VALIDATION_FAILED` | corps invalide / champ inconnu | corriger le formulaire (`details`) |
| 400 | `REQUEST_REJECTED` | contrat `input` (« Données invalides pour le service… ») ; « Aucun marchand ne peut porter cette opération. » | corriger |
| 401 | — | session | Partie 1.6 / Partie 2 |
| 403 | `SERVICE_NOT_SELF_SERVICE` / `FUNDS_SOURCE_NOT_ALLOWED` / `QUOTE_RATE_LIMIT` / `FORBIDDEN` | périmètre libre-service, non souscrit, plafond horaire | masquer l'option / patienter |
| 403 | `FORBIDDEN` | `wallet-to-card` sur une autre carte : « Vous ne pouvez agir que sur la carte avec laquelle vous vous êtes connecté… » | forcer la carte de session |
| 404 | `NOT_FOUND` | service inconnu / indisponible / non payable par ce moyen / **grille de frais absente pour ce montant** | changer de montant ou de moyen |
| 500 | `INTERNAL_ERROR` | incident fournisseur hors vendeur | réessayer plus tard |

---

#### 3.7 `GET /api/v1/catalog/quote/{quoteId}` — relire un devis

**But** : retrouver ce qui a été annoncé (rechargement d'écran), état réel inclus, sans recalcul.

**Auth** : `@AllowedActors('merchant','internal','customer')` (pas visiteur). Seul l'auteur (`requestedBy = cid_…`) le voit.

**Path** : `quoteId` (string).

**Réponse 200** (`QuotePeekResponseDto`) : `success`, `quoteId`, `status` (`OPEN|CONSUMED|EXPIRED|REJECTED`),
`feasible` (= `status == OPEN && non expiré` — **c'est lui qui active le bouton Confirmer**), `reason` (null si non refusé),
`amount`, `internalFee`, `externalFeeAdvanced`, `externalFeeWithheld`, `amountDebited`, `amountCredited`, `currency`,
`checks`, `warnings`, `display`, `expiresAt`, `isExpired`.

```json
{
  "success": true,
  "quoteId": "clq8x2k3p0001abcd",
  "status": "OPEN",
  "feasible": true,
  "reason": null,
  "amount": 5000, "internalFee": 50, "externalFeeAdvanced": 75, "externalFeeWithheld": 0,
  "amountDebited": 5125, "amountCredited": 5000, "currency": "xof",
  "checks": [ { "key": "meter", "label": "Compteur", "passed": true, "detail": "48.2 kWh" } ],
  "warnings": [],
  "display": { "customerName": "ADJOVI KOSSI", "meterNum": "01234567890", "estimatedKwh": 48.2, "arrears": 0, "serviceFee": 100, "fundingApproval": "PAYER_APPROVAL" },
  "expiresAt": "2026-10-15T09:24:22.418Z",
  "isExpired": false
}
```
NB : `status` reste `OPEN` après l'échéance tant que personne n'a tenté de le consommer ; se fier à `feasible`/`isExpired`.

**Erreurs** : 404 `NOT_FOUND` « Devis introuvable. » (inexistant ou d'un autre) ; 401.

---

#### 3.8 `POST /api/v1/catalog/confirm` — confirmer et exécuter

**But** : honorer un devis : prélever, exécuter, livrer. Prix = ceux du devis (jamais recalculés) ; disponibilités revérifiées.

**Auth** : `@AllowedActors('merchant','internal','customer','visitor')`, Bearer porteur ; **PIN obligatoire si `funding.source = CUSTOMER_CARD`** ;
idempotence par `reference` (§2.6). HTTP 200.

**Corps** (`ConfirmQuoteDto`) :
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `quoteId` | string | oui | `IsNotEmpty` | `"clq8x2k3p0001abcd"` |
| `service` | string | oui | `IsNotEmpty` — **identique** au devis | `"electricity-prepaid"` |
| `funding` | `FundingDto` | oui | même forme qu'au devis | — |
| `funding.source` | enum | oui | doit correspondre au devis (la source effective est celle du devis) | `"CUSTOMER_CARD"` |
| `funding.card.cardCustomerId` | string | **oui si carte** | carte de **session** | `"121436474"` |
| `funding.card.last4` | string | non | 4 chiffres, comparés à l'émetteur (`CARD_MISMATCH`) | `"4589"` |
| `funding.external.*` | — | **oui si externe** | **même canal et même numéro** qu'au devis ; prénom+nom sauf B-MO | — |
| `reference` | string | non (fortement conseillé) | `MaxLength(64)` — clé d'idempotence (UUID v4) | `"5b1f0b9e-6c1e-4b8e-9b0a-2f1a3c4d5e6f"` |
| `pin` | string | **oui si carte** | `Matches(/^\d{6}$/)` « Six chiffres attendus. » | `"482915"` |
| `cardOtp` | string | non | `Matches(/^\d{6}$/)` — **ignoré pour un porteur** (réservé marchand/clé) | — |

**Exemple (carte)** :
```json
{
  "quoteId": "clq8x2k3p0003abcd",
  "service": "mobile-data",
  "funding": { "source": "CUSTOMER_CARD", "card": { "cardCustomerId": "121436474" } },
  "reference": "5b1f0b9e-6c1e-4b8e-9b0a-2f1a3c4d5e6f",
  "pin": "482915"
}
```

**Exemple (portefeuille)** :
```json
{
  "quoteId": "clq8x2k3p0001abcd",
  "service": "electricity-prepaid",
  "funding": {
    "source": "CUSTOMER_EXTERNAL_CHANNEL",
    "external": { "channelSlug": "MOMO", "payerIdentifier": "+2290167123456", "payerFirstName": "Kossi", "payerLastName": "Adjovi" }
  },
  "reference": "a3c9f2d4-1e7b-4c55-8f0e-7d2b9a6e1c30"
}
```

**Séquence serveur** (`CatalogController.confirm` → `CommerceService.execute`) :
1. `buildCardConsent` (si `funding.source = CUSTOMER_CARD`) : `pin` absent ⇒ 400 `CARD_CONSENT_REQUIRED` ; carte sans dossier
   (`kycId` nul) ⇒ 403 `CARD_CONSENT_UNAVAILABLE` « Le paiement par carte n'est pas disponible pour une carte émise hors de la plateforme. Choisissez un autre moyen de paiement. » ; `verifyPin` (§2.4).
2. Rejeu par `reference` ⇒ rend l'état de l'opération existante (voir messages de rejeu plus bas).
3. Même service que le devis ⇒ sinon 400 `QUOTE_SERVICE_MISMATCH`.
4. Même payeur externe (canal comparé sans casse, numéro comparé par chiffres, suffixe ≥ 8) ⇒ sinon 400 `QUOTE_FUNDING_MISMATCH`.
5. Nom du payeur (hors B-MO) ⇒ sinon 400 `PARTY_NAME_REQUIRED`.
6. Carte (devis carte) : résolution gamme + 4 chiffres chez l'émetteur ⇒ 400 `CARD_MISMATCH` si `last4` faux.
7. `assertConsent` : `funding.card` absent ⇒ 400 `CARD_SOURCE_REQUIRED` ; carte ≠ carte de session ⇒ 403 ; PIN non fourni
   alors que le devis est par carte ⇒ 403 `CARD_CONSENT_REQUIRED`.
   (Étapes 3 à 7 **ne consomment pas** le devis : corriger et reconfirmer.)
8. Consommation du devis : 404 « Devis introuvable. Demandez-en un nouveau. » / « Devis introuvable. » (autre auteur) ;
   400 motif du refus (devis `REJECTED`) ; 400 « Ce devis a déjà servi. Demandez-en un nouveau. » ; 400 « Ce devis a expiré.
   Les prix ont pu changer : demandez-en un nouveau. » ; 400 « Ce devis vient d'être utilisé. Demandez-en un nouveau. ».
9. Plafonds journaliers (403 `DAILY_OPERATION_LIMIT` / `DAILY_AMOUNT_LIMIT`) — **le devis est alors déjà consommé**.
10. Création de l'opération (`PENDING`, `initiationMode: CUSTOMER_SELF_SERVICE`, `createdBy: cid_…`).
11. Prélèvement :
    - Carte : débit synchrone de `amountDebited` chez l'émetteur ; refus ⇒ opération `FAILED`, 400 `REQUEST_REJECTED`
      « Débit de la carte refusé : <motif émetteur> » (solde insuffisant, carte bloquée…). Rien n'a été prélevé.
    - Portefeuille : demande d'encaissement ⇒ `PENDING` + `awaiting` ; refus net B-MO ⇒ 400 `BMO_INSUFFICIENT_FUNDS` |
      `BMO_LIMIT_EXCEEDED` | `BMO_ACCOUNT_UNAVAILABLE` | `BMO_NO_ACCOUNT` | `BMO_WRONG_CODE` | `BMO_OTHER` ; incident agrégateur ⇒ 500 « Impossible de solliciter le paiement : … ».
12. Exécution du service (carte, ou plus tard après validation du portefeuille). Échec ⇒ le socle interroge le fournisseur :
    livré ⇒ `SUCCESS` ; non livré ⇒ remboursement de la source (`REFUNDED`) et **500** « Le service n'a pas pu être rendu : … Vous avez été remboursé. » ;
    remboursement non confirmé ⇒ `FAILED` + revue, 500 « … NE LA RELANCEZ PAS, vous risqueriez de payer deux fois. » ;
    sort inconnu ⇒ `FAILED` + revue, 500 « Le sort de cette opération n'a pas pu être déterminé… NE LA RELANCEZ PAS… ».
13. Succès : `SUCCESS`, commissions, livraison du secret au bénéficiaire (jeton électricité / code de retrait), notification.

**Réponse 200** (`ConfirmQuoteResponseDto`) :
| Champ | Type | Sens |
|---|---|---|
| `success` | boolean | `true` |
| `operationId` | string | **à conserver** (suivi, code B-MO) |
| `reference` | string | notre référence lisible (à citer au support / fournisseur) |
| `merchantReference` | string \| null | votre `reference` |
| `status` | `SUCCESS` \| `PENDING` (rejeu : tout statut) | état |
| `amount`, `internalFee`, `externalFeeAdvanced`, `externalFeeWithheld`, `amountDebited`, `amountCredited` | number | figés au devis |
| `currency` | — | ⚠️ déclaré dans le DTO Swagger mais **jamais renvoyé** par `CommerceService` (ni succès, ni attente, ni rejeu) : prendre la devise du devis |
| `providerReference` | string? | référence fournisseur (absente si en attente) |
| `completed` | boolean | **décide du parcours** : `true` = service rendu ; `false` = rien de livré |
| `awaiting` | `PAYER_APPROVAL` \| `CONFIRMATION_CODE` \| `PROVIDER_SETTLEMENT` \| null | quoi faire si `completed:false` |
| `message` | string | à afficher, ne pas parser |

**Exemple — carte, succès** :
```json
{
  "success": true,
  "operationId": "clop9a1b2c3d0001",
  "reference": "ADS-20261015-091422-A7B9",
  "status": "SUCCESS",
  "merchantReference": "5b1f0b9e-6c1e-4b8e-9b0a-2f1a3c4d5e6f",
  "amount": 500, "internalFee": 0, "externalFeeAdvanced": 0, "externalFeeWithheld": 0,
  "amountDebited": 500, "amountCredited": 500,
  "providerReference": "2089709140",
  "completed": true,
  "message": "Forfait internet effectué avec succès."
}
```

**Exemple — portefeuille B-MO, en attente de code** :
```json
{
  "success": true,
  "operationId": "clop9a1b2c3d0002",
  "reference": "ADS-20261015-091530-C4D2",
  "status": "PENDING",
  "merchantReference": "a3c9f2d4-1e7b-4c55-8f0e-7d2b9a6e1c30",
  "amount": 5000, "internalFee": 50, "externalFeeAdvanced": 75, "externalFeeWithheld": 0,
  "amountDebited": 5125, "amountCredited": 5000,
  "completed": false,
  "awaiting": "CONFIRMATION_CODE",
  "message": "Demande envoyée — le client a reçu un code de confirmation. Saisissez-le pour valider le paiement."
}
```
Autres messages d'attente : `PAYER_APPROVAL` « Demande envoyée — le client doit valider le paiement sur son téléphone. » ;
`PROVIDER_SETTLEMENT` « Le prestataire n'a pas encore répondu — le sort du paiement sera établi automatiquement. Ne remettez rien et NE RELANCEZ PAS. »

Messages de rejeu (même `reference`) : SUCCESS « Opération déjà effectuée — voici son résultat, aucune seconde vente n'a eu lieu. » ;
PENDING+CONFIRMATION_CODE « … le client a reçu un code : saisissez-le. Ne la relancez pas. » ; PENDING/PROCESSING « … TOUJOURS EN COURS … » ;
REFUNDED « … elle a échoué et vous avez été remboursé. » ; FAILED ; CANCELLED ; EXPIRED.

**Règles métier par service** :
- `wallet-to-card` : toujours `completed:false` (crédit de la carte **après** la validation du portefeuille, sans nouvel appel).
- `cash-withdrawal` : code de retrait (et code d'accès s'il a été engendré) envoyés au **bénéficiaire** ; validité
  `ATM_CODE_EXPIRY_MINUTES` (défaut 60, borné 10–1440), plafonnée à 23 h 55 (heure de Porto-Novo). Non retiré à l'échéance ⇒
  annulé chez B-MO et **montant du retrait** (`amount`, hors frais) restitué automatiquement à la source (carte ou portefeuille).
- `electricity-prepaid` : jeton envoyé au bénéficiaire par WhatsApp/e-mail, jamais dans la réponse.
- Crédit, forfait, facture, abonnement : irréversibles une fois livrés.

**Erreurs HTTP récapitulées** :
| HTTP | code | Cause | Action app |
|---|---|---|---|
| 400 | `VALIDATION_FAILED` | `pin`/`cardOtp` ≠ 6 chiffres, champs | corriger |
| 400 | `CARD_CONSENT_REQUIRED` | PIN absent (carte) | demander le PIN |
| 403 | `FORBIDDEN` | PIN faux / verrouillé (message avec essais restants) | ressaisir / attendre / réinitialiser le PIN |
| 400 | `REQUEST_REJECTED` | aucun PIN défini ; devis expiré/consommé/refusé ; débit carte refusé ; référence en cours | nouveau devis / autre moyen |
| 403 | `CARD_CONSENT_UNAVAILABLE` | carte hors plateforme | proposer le portefeuille |
| 400 | `QUOTE_SERVICE_MISMATCH` / `QUOTE_FUNDING_MISMATCH` / `PARTY_NAME_REQUIRED` / `CARD_SOURCE_REQUIRED` / `CARD_MISMATCH` | incohérence avec le devis | corriger (devis intact) |
| 403 | `CARD_CONSENT_REQUIRED` | devis carte confirmé sans `source: CUSTOMER_CARD`/PIN | renvoyer avec PIN |
| 403 | `FORBIDDEN` | carte ≠ carte de session | — |
| 403 | `DAILY_OPERATION_LIMIT` / `DAILY_AMOUNT_LIMIT` | plafonds 24 h | informer ; renvoyer vers un marchand |
| 400 | `BMO_*` | refus B-MO à l'initiation | afficher le message |
| 404 | `NOT_FOUND` | devis introuvable | nouveau devis |
| 500 | `INTERNAL_ERROR` / `FUNDING_UNCERTAIN` | exécution échouée (remboursé ou en revue), sort inconnu | **ne pas relancer** ; suivre l'opération ; afficher le message |

---

#### 3.9 `POST /api/v1/commerce/operations/{operationId}/funding/confirm` — saisir le code B-MO

**But** : valider un paiement B-MO direct avec le code SMS reçu par le payeur.

**Auth** : `@AllowedActors('merchant','internal','customer','visitor')` ; **seul l'auteur** (`createdBy = cid_…`) ;
throttling 30/min par porteur ; idempotent sur le succès.

**Path** : `operationId`. **Corps** (`ConfirmFundingCodeDto`) :
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `code` | string | oui | `IsString`, `Matches(/^\d{4,8}$/)` « Le code se compose de 4 à 8 chiffres. » (garder les zéros initiaux) | `"482913"` |

**Quand** : réponse de confirmation `completed:false`, `awaiting: CONFIRMATION_CODE`.

**Réponse 200** (`ExecutionResponseDto`, même forme que la confirmation) :
```json
{
  "success": true,
  "operationId": "clop9a1b2c3d0002",
  "reference": "ADS-20261015-091530-C4D2",
  "status": "SUCCESS",
  "merchantReference": "a3c9f2d4-1e7b-4c55-8f0e-7d2b9a6e1c30",
  "amount": 5000, "internalFee": 50, "externalFeeAdvanced": 75, "externalFeeWithheld": 0,
  "amountDebited": 5125, "amountCredited": 5000,
  "providerReference": "SBEE-77812345",
  "completed": true,
  "message": "Électricité prépayée effectué avec succès."
}
```
Issue B-MO muette : `completed:false`, `awaiting: "PROVIDER_SETTLEMENT"` ⇒ **ne rien ressaisir**, suivre l'opération.

**Règles** : `BMO_CODE_MAX_ATTEMPTS` essais (défaut **3**), consommés avant l'envoi. Refus pour solde/plafond : l'essai
est rendu (le payeur peut approvisionner puis redonner le même code). Opération déjà `SUCCESS` ⇒ résultat rendu.

**Erreurs** :
| HTTP | code | Message / cas | Action |
|---|---|---|---|
| 400 | `INVALID_CONFIRMATION_CODE` | « Code refusé. N essai(s) restant(s). », `details.attemptsLeft` | ressaisir |
| 400 | `CONFIRMATION_ATTEMPTS_EXHAUSTED` | paiement annulé (ou le sera), `details.attemptsLeft: 0` | nouveau devis |
| 400 | `BMO_INSUFFICIENT_FUNDS` / `BMO_LIMIT_EXCEEDED` | `details: { attemptsLeft, recoverable: true }` | approvisionner, redonner le même code, ou annuler |
| 400 | `BMO_ACCOUNT_UNAVAILABLE` / `BMO_NO_ACCOUNT` | `recoverable: false` | annuler |
| 400 | `FUNDING_CLOSED` | « Ce paiement n'est plus valable chez B-MO (expiré ou annulé). Rien n'a été prélevé… » | nouveau devis |
| 400 | `OPERATION_NOT_PENDING` | l'opération n'attend plus rien (état X) | consulter le suivi |
| 400 | `NOT_A_CODE_PAYMENT` | pas un paiement externe / validation sur téléphone (`PAYER_APPROVAL`) | attendre |
| 404 | `NOT_FOUND` | « Opération introuvable. » (inexistante ou d'un autre) | — |
| 409 | `CONFLICT` | « Cette opération est en cours de traitement… » ; « Un code vient d'être traité pour cette opération… » | patienter, consulter l'état |
| 409 | `FUNDING_NOT_READY` | « La demande de paiement n'est pas encore parvenue à B-MO… » (aucun essai consommé) | réessayer dans quelques secondes |
| 429 | `RATE_LIMITED` | > 30 appels/min | ralentir |

(`FORBIDDEN_SERVICE` 403 ne concerne que marchands/clés.)

---

#### 3.10 `POST /api/v1/commerce/operations/{operationId}/funding/cancel` — renoncer à un paiement B-MO

**But** : annuler chez B-MO un débit en attente de code, puis l'opération (le payeur change d'avis ou ne reçoit pas le code).

**Auth** : idem 3.9 (auteur seul, 30/min). **Corps** : aucun.

**Réponse 200** (`ExecutionResponseDto`) : normalement `status: "CANCELLED"`, `completed:false`,
`message: "Opération déjà traitée : elle a été annulée."`. ⚠️ Si le payeur venait de valider, B-MO refuse l'annulation et le
service est rendu : `status: "SUCCESS"`, `completed: true`. **Toujours lire `status`.** Déjà `CANCELLED` ⇒ rendu tel quel.

**Erreurs** : 400 `OPERATION_NOT_PENDING` ; 400 `NOT_A_CODE_PAYMENT` (paiements « validation sur téléphone » non annulables : ils expirent seuls) ;
400 `FUNDING_CANCEL_REFUSED` « B-MO refuse l'annulation de ce paiement. Consultez son état avant toute autre action. » ;
409 `FUNDING_SETTLING` (code déjà transmis, verdict attendu) ; 409 `CONFLICT` (en cours) ; 404 ; 429 ;
503 `PROVIDER_UNAVAILABLE` « B-MO ne répond pas : l'annulation n'a pas pu être confirmée. Réessayez dans quelques instants. »

---

#### 3.11 `POST /api/v1/catalog/secrets/{secretId}/resend` — renvoyer un code au bénéficiaire

**But** : réexpédier un jeton d'électricité ou un code de retrait **à la coordonnée enregistrée** à l'émission.

**Auth** : `@AllowedActors('merchant','internal','customer','admin')` (permissions `merchant:addon:resend-token` /
`merchant:addon:resend-atm-code` non contrôlées pour le porteur). Périmètre porteur : secrets dont l'opération émettrice a
`createdBy = cid_…`.

**Path** : `secretId`. **Corps** (`ResendSecretDto`) : `beneficiaryContact?: string` — **à ne pas envoyer** (réservé admin ;
une valeur différente de l'originale ⇒ 403 `SECRET_CONTACT_CHANGE_FORBIDDEN`).

**Réponse 200** (`ResendSecretResponseDto`) :
```json
{ "success": true, "message": "Code renvoyé au bénéficiaire.", "deliveredTo": "+229***456", "deliveryCount": 2 }
```

**Erreurs** : 404 `NOT_FOUND` « Secret introuvable. » ; 400 « Ce code a déjà été utilisé. » / « Ce code n'est plus valable (STATUS). » / « Ce code a expiré. » ; 403 `SECRET_CONTACT_CHANGE_FORBIDDEN` ; 401.

> ⚠️ **Aucune route du périmètre (ni `GET /cards/operations/{id}`) n'expose `secretId` au porteur.** En l'état, l'app ne peut
> pas obtenir l'identifiant à passer ; prévoir une évolution backend (exposer `secretId` dans le suivi d'opération) avant d'implémenter « Renvoyer le code ».

---

### 4. Parcours détaillés

#### 4.1 Paiement par carte (synchrone) — ex. forfait internet
1. `GET /catalog/services` → vérifier `mobile-data` / option `CUSTOMER_CARD` `available:true`.
2. `GET /catalog/lookup/mobile/{msisdn}/products?type=DATA` → choisir `id`.
3. `POST /catalog/quote` `{ service: "mobile-data", funding: { source: "CUSTOMER_CARD", card: { cardCustomerId } }, input: { beneficiary, productId } }`.
4. Si `feasible:false` → afficher `reason`, mettre en évidence le `checks[].key` en échec, corriger, revenir en 3.
5. Afficher `display.productName`, `display.beneficiary` (à faire relire), `amountDebited`, `warnings`, compte à rebours `expiresAt`.
6. Saisie du PIN → `POST /catalog/confirm` avec `pin` et `reference` = UUID v4 neuf.
7. `completed:true` → reçu (`reference`, `providerReference`). Erreur réseau/timeout → rejouer **le même corps** (même `reference`, PIN) ; ne jamais créer un nouveau devis avant de connaître le sort.
8. 403 PIN → ressaisie (le devis est intact) ; 400 devis expiré → reprendre en 3.

#### 4.2 Paiement par portefeuille avec validation sur téléphone (`PAYER_APPROVAL`, agrégateur)
1. `GET /external-wallets/channels?country=BJ&operation=COLLECT` (annexe) → `providerSlug`.
2. Devis avec `funding.external` complet (prénom + nom obligatoires hors B-MO). `display.fundingApproval = "PAYER_APPROVAL"`.
3. `POST /catalog/confirm` avec **le même** `funding.external` → `completed:false`, `awaiting:"PAYER_APPROVAL"`.
4. Écran d'attente « Validez le paiement sur votre téléphone » ; suivi `GET /cards/operations/{operationId}` toutes les ~5–10 s
   jusqu'à `status ≠ PENDING` (échéance ≈ 10 min ⇒ `EXPIRED`/`FAILED`). Pas d'annulation possible côté app.
5. `SUCCESS` → reçu. `REFUNDED` → « Service non rendu, vous avez été remboursé ». `FAILED`/`EXPIRED` → afficher `reason`.

#### 4.3 Paiement B-MO direct (`CONFIRMATION_CODE`)
1. Devis avec `funding.external.channelSlug` B-MO (nom facultatif) ; avertissement « Vous recevrez un code de … par SMS ».
   Le titulaire est vérifié : `display.payerVerifiedName`.
2. Confirm → `awaiting:"CONFIRMATION_CODE"`.
3. Écran de saisie du code ; en parallèle `GET /cards/operations/{operationId}` **toutes les 10 s** (déclenche une vérification B-MO
   au plus toutes les 15 s : le payeur peut valider dans son appli B-MO sans saisir le code).
4. `POST /commerce/operations/{id}/funding/confirm { code }` → `completed:true` ; ou 400 `INVALID_CONFIRMATION_CODE` (ressaisir,
   `details.attemptsLeft`) ; ou `awaiting:"PROVIDER_SETTLEMENT"` (attendre, ≈ 35 min max, ne rien ressaisir).
5. Abandon : `POST /commerce/operations/{id}/funding/cancel` puis lire `status` (peut être `SUCCESS`).
6. Échéance ≈ 15 min sans code : opération close automatiquement.

#### 4.4 Recharge de sa carte depuis son portefeuille (`wallet-to-card`)
Devis `{ service: "wallet-to-card", funding: { source: "CUSTOMER_EXTERNAL_CHANNEL", external: {…} }, input: { cardCustomerId: <carte de session>, amount } }`
→ afficher `display.holderName`/`cardLast4`/`cardWillReceive` → confirm → toujours `completed:false` → parcours 4.2 ou 4.3.
La carte est créditée après validation ; échec net du crédit ⇒ portefeuille remboursé (`REFUNDED`) ; coupure ⇒ revue humaine.

#### 4.5 Retrait au guichet (`cash-withdrawal`)
Devis avec `deliveryChannel`, `beneficiaryContact`, `amount`, `pin` facultatif → afficher `display.expiresAt` (« valable jusqu'à HHhMM »),
`pinIsProvided` (si vrai, rappeler au porteur de communiquer lui-même le code d'accès) → confirm. Le code part au bénéficiaire.
Non retiré à l'échéance ⇒ restitution automatique du montant (hors frais) à la source.

#### 4.6 Électricité postpayée / TV
- Postpayée : lookup factures → devis (sans montant ; `invoiceReferences` facultatif) → afficher `display.invoices`, `totalDue`, `remainingUnpaid` → confirm.
- TV : `…/current` (reconduction : devis sans `mainOffer`) ou `…/offers` (changement : `mainOffer` + `duration` [+ `optionsList`]) → le devis fixe le prix (`display.amount`).

---

### 5. Suivi d'opération (hors périmètre, indispensable)

`GET /api/v1/cards/operations/{operationId}` — `@AllowedActors('merchant','internal','admin','customer')`. Accès porteur si
`createdBy = cid_…` (donc toutes ses opérations catalogue). Réponse : `operationId`, `reference`, `type`, `status`,
`initiationMode`, `amount`, `fee`, `amountDebited`, `amountCredited`, `reason` (motif d'échec/annulation), `awaiting` (si PENDING),
`cards[]`, `service {slug,label}`, `merchantName`, `parties[]`, `initiatedBy`, `createdAt`, `approvedAt`. Si `awaiting = CONFIRMATION_CODE`,
interroge B-MO (≤ 1 fois / 15 s / opération).

> ⚠️ `GET /api/v1/operations/{id}` et `GET /api/v1/operations` ne montrent au porteur que les opérations **liées à sa carte**
> (`OperationCard`). Les opérations du catalogue n'en créent pas (débit/crédit direct chez l'émetteur) : elles y sont **invisibles (404)**.
> Utiliser `GET /cards/operations/{operationId}` et conserver localement les `operationId`.

Autre solution de suivi : rejouer `POST /catalog/confirm` avec la même `reference` (pas de PIN requis pour un paiement par portefeuille).

---

---

# Partie 6 — Historique, notifications, Mobile Money, disponibilité, géographie, KYC

> Rappel : une route qui n'admet pas le porteur répond **401** et non 403 avec le jeton porteur (voir 1.6). Les routes KYC et OTP visiteur s'appellent **sans** en-tête `Authorization`.
>
> Les renvois « § » désignent les sections de cette partie ; « §0.x » renvoie à la Partie 1 (conventions) et à la Partie 2 (authentification).

### 1. Opérations — `src/operations/operations.controller.ts`

Contrôleur `@Controller('operations')`, `@UseGuards(AuthGuard)`.

Routes ouvertes au client : **`GET /operations`** et **`GET /operations/:id`**.
Routes NON ouvertes au client (→ 401 `Jeton non reconnu pour cette route`) : `GET /operations/summary`, `GET /operations/export`, `POST /operations/export/request`, `GET /operations/review`, `POST /operations/:id/review/resolve`.

#### 1.1 `GET /api/v1/operations` — Historique de mes opérations

**But** : liste paginée des opérations où figure la **carte de session**, quel que soit le marchand qui les a initiées, avec des statistiques calculées sur les filtres actifs.

**Auth** : `@AllowedActors('merchant','internal','admin','customer')`. `@RequireMerchantPermissions('merchant:operation:read')` / `@RequireAdminPermissions(...)` ne concernent pas le client. Pas de throttling.

**Cloisonnement client** (`OperationsService._accessScope`) :
```ts
{ cards: { some: { cardCustomerIdEnc: requester.id } } }   // + deletedAt: null
```
- Si `requester.id` absent → 403 `Session client incomplète.`
- Toutes les opérations où la carte figure (rôle `MAIN`, `SOURCE` ou `TARGET`) : achats faits au comptoir, par API ou en libre-service.

**Query** (`GetOperationsQueryDto`) — tous optionnels :

| Champ | Type | Règles | Défaut | Exemple | Effet |
|---|---|---|---|---|---|
| `page` | int | `@IsInt @Min(1)` | 1 | `1` | |
| `limit` | int | `@IsInt @Min(1) @Max(100)` | 20 | `20` | > 100 → 400 |
| `merchantId` | string | `@IsString` | | | ⚠️ **Pour un client, toute valeur → 403** `Vous n’avez pas accès aux opérations de ce marchand.` Ne pas l'envoyer. |
| `createdBy` | string | `@IsString` | | `cid_…` | filtre exact sur l'auteur (format d'audit) |
| `cardCustomerId` | string | `@IsString` | | `121436474` | identifiant émetteur EN CLAIR (chiffré côté serveur) ; combiné en AND avec le cloisonnement → une autre carte donne une liste vide |
| `cardLast4Digits` | string | `@IsString` | | `4589` | |
| `cardTierSlug` | string | `@IsString` | | `virtual:uba-bj:visa-prepaid-card:6-month` | |
| `serviceId` | string | `@IsString` | | `clsrv1234567890` | |
| `status` | enum `OperationStatus` | `@IsEnum` | | `SUCCESS` | voir §7.1 |
| `operationType` | enum `OperationType` | `@IsEnum` | | `WALLET_OPERATION` | filtre sur `type` |
| `initiationMode` | enum `OperationInitiationMode` | `@IsEnum` | | `CUSTOMER_SELF_SERVICE` | |
| `requiresReview` | boolean | transform `'true'`→true | | `true` | ne garde que `requiresReview=true` et non résolues (le champ n'est pas renvoyé au client) |
| `hasFallback` | boolean | idem | | | `fallbackFromMerchantId != null` |
| `currencyIsoCode` | string | `@IsString` | | `xof` | mis en minuscules |
| `minAmount` | number | `@IsNumber @Min(0)` | | `1000` | sur `amount` (gte) |
| `maxAmount` | number | `@IsNumber @Min(0)` | | `50000` | (lte) |
| `startDate` | string | `@IsDateString` | | `2026-08-01` | `createdAt >= début du jour` |
| `endDate` | string | `@IsDateString` | | `2026-08-31` | `createdAt <= fin du jour` |
| `search` | string | `@IsString` | | `WOP-20260817` | `reference` ou `idempotencyKey` contient (insensible à la casse), ou `id` exact |
| `sortBy` | enum | `createdAt:asc`, `createdAt:desc`, `amount:asc`, `amount:desc`, `updatedAt:asc`, `updatedAt:desc` | `createdAt:desc` | | |

**Réponse 200** (`PaginatedOperationsResponseDto`) :
```json
{
  "success": true,
  "data": [
    {
      "id": "clop1234567890",
      "type": "WALLET_OPERATION",
      "status": "SUCCESS",
      "reference": "WOP-20260817-091422-A7B9",
      "idempotencyKey": "KNK-6f1c2b9e-7d4e",
      "amount": 25000,
      "currencyIsoCode": "xof",
      "fee": 550,
      "amountDebited": 25550,
      "amountCredited": 25000,
      "initiationMode": "CUSTOMER_SELF_SERVICE",
      "origin": "V2",
      "cards": [
        {
          "id": "cloc1234567890",
          "cardCustomerId": "121436474",
          "cardLast4": "4589",
          "firstName": "Kossi",
          "lastName": "Adjovi",
          "holderName": "Kossi Adjovi",
          "role": "MAIN",
          "isExternal": false,
          "internalCardId": "clc1234567890",
          "cardTier": { "slug": "virtual:uba-bj:visa-prepaid-card:6-month", "label": "Virtual Standard - UBA BJ", "type": "VIRTUAL" },
          "createdAt": "2026-08-17T09:14:22.000Z"
        }
      ],
      "parties": [
        {
          "role": "BENEFICIARY",
          "name": "Afi M.",
          "identifier": "+22901****0002",
          "channelSlug": "MOMO",
          "channelLabel": "MTN Mobile Money",
          "verified": true
        }
      ],
      "serviceId": "clsrv1234567890",
      "service": { "id": "clsrv1234567890", "label": "Versement vers un portefeuille externe", "slug": "merchant:external-wallet:payout:from-card" },
      "feeId": "clf1234567890",
      "quoteId": "clq1234567890",
      "failureReason": null,
      "cancellationReason": null,
      "createdAt": "2026-08-17T09:14:22.000Z",
      "updatedAt": "2026-08-17T09:14:25.000Z",
      "approvedAt": null
    }
  ],
  "pagination": { "total": 37, "page": 1, "limit": 20, "totalPages": 2, "hasNextPage": true, "hasPreviousPage": false },
  "stats": {
    "totalOperations": 37,
    "successfulOperations": 30,
    "failedOperations": 5,
    "pendingOperations": 2,
    "todaysTotalOperations": 1,
    "totalAmount": 612000,
    "successfulAmount": 540000,
    "todaysTotalAmount": 25000,
    "currencyIsoCode": "xof"
  }
}
```

**Champs par élément (vue client)** — types :
- `id` string · `type` OperationType · `status` OperationStatus · `reference` string · `idempotencyKey` string|null (la `reference` passée à la confirmation)
- `amount` number (montant demandé) · `currencyIsoCode` string (minuscules)
- `fee` number (= `frozenFee`, frais figés au devis) · `amountDebited` number (ce qui a quitté la source — pour une carte : montant + frais) · `amountCredited` number (ce qui est parvenu au destinataire)
- `initiationMode` `MERCHANT_ASSISTED|CUSTOMER_SELF_SERVICE|API_KEY` · `origin` `'V2'|'V1'` (V1 = historique migré)
- `cards[]` (`OperationCardDto`) : `id`, `cardCustomerId` (déchiffré), `cardLast4` (déchiffré), `firstName|null`, `lastName|null`, `holderName|null`, `role` (`MAIN|SOURCE|TARGET`), `isExternal` bool, `internalCardId|null`, `cardTier` `{slug,label,type}`|null, `createdAt`. ⚠️ Plusieurs cartes pour un transfert : lisez `role`, ne prenez pas la première. Les cartes de **contrepartie** (autre porteur) y figurent aussi, numéros déchiffrés.
- `parties[]` : `role` (`PAYER|BENEFICIARY`), `name|null`, `identifier` (**masqué pour le client** : `+22901****0002`, e-mail `ab***@domaine`), `channelSlug|null`, `channelLabel|null`, `verified` bool. Nom vérifié par l'opérateur → affiché « Prénom N. ».
- `serviceId|null`, `service` `{id,label,slug}`|null, `feeId|null`, `quoteId|null`, `failureReason|null`, `cancellationReason|null`, `createdAt`, `updatedAt`, `approvedAt|null`.

**Champs ABSENTS pour le client** (clé absente, pas `null`) : `merchantId`, `merchant`, `createdBy`, `initiatedBy`, `requiresReview`, `reviewReason`, `reviewSignaledAt`, `reviewResolvedAt`, `fallbackFromMerchantId`, `fallbackFromMerchant`, `fallbackReason`, `data`, `externalFee`, `externalFeeAdvanced`, `externalFeeWithheld`.

**Règles des `stats`** (calculées sur **tous les filtres actifs**, pas sur la page) :
- `successfulOperations` = `SUCCESS` ; `failedOperations` = `FAILED + CANCELLED + EXPIRED` ; `pendingOperations` = `PENDING + PROCESSING + INITIALIZED + PENDING_APPROVAL`. `REVERSED` et `REFUNDED` ne sont comptés que dans `totalOperations`/`totalAmount`.
- `totalAmount` somme de `amount` toutes statuts ; `successfulAmount` seulement `SUCCESS`.
- `todays*` : depuis minuit **heure du serveur**.
- `currencyIsoCode` toujours `"xof"` (codé en dur).

**Erreurs** :
| HTTP | code | message |
|---|---|---|
| 400 | `VALIDATION_FAILED` | paramètre invalide/inconnu (ex. `limit` > 100, `status` hors enum) |
| 401 | voir Partie 1.6 | |
| 403 | `FORBIDDEN` | `Session client incomplète.` |
| 403 | `FORBIDDEN` | `Vous n’avez pas accès aux opérations de ce marchand.` (si `merchantId` envoyé) |

#### 1.2 `GET /api/v1/operations/:id` — Détail d'une opération

**But** : tout ce que porte l'opération + le **devis** (ce qui a été annoncé avant confirmation) + les **mouvements** financiers.

**Auth** : identique à 1.1. Même cloisonnement (carte de session) dans le `where`.

**Path** : `id` (string, cuid de l'opération, ex. `clop1234567890`). Aucune validation de format.

**Réponse 200** (`SingleOperationResponseDto` → `data: OperationDetailDto`) : tous les champs de 1.1, plus :
```json
{
  "success": true,
  "data": {
    "...": "mêmes champs que la liste",
    "quote": {
      "id": "clq1234567890",
      "amount": 25000,
      "internalFee": 550,
      "externalFeeAdvanced": 0,
      "externalFeeWithheld": 0,
      "amountDebited": 25550,
      "amountCredited": 25000,
      "checks": [{ "key": "beneficiary", "label": "Bénéficiaire", "passed": true, "detail": "Afi Mensah — +2290***02" }],
      "warnings": ["Vérifiez le numéro avant de confirmer : un versement abouti ne peut pas être repris, et nous ne pouvons pas contrôler à qui il appartient."],
      "display": { "beneficiaryName": "Afi Mensah", "beneficiaryVerified": false, "beneficiaryIdentifier": "+2290***02", "beneficiaryWillReceive": 25000, "irreversible": true },
      "requestedAt": "2026-08-17T09:13:40.000Z",
      "confirmedAt": "2026-08-17T09:14:21.000Z"
    },
    "movements": [
      { "id": "clwe1234567890", "amount": 25550, "direction": "DEBIT", "label": "…", "at": "2026-08-17T09:14:22.000Z" }
    ]
  }
}
```
- `quote` : `null` si l'opération n'a pas eu de devis (geste administratif, opérations V1, débits carte hors socle commerce…). Pour le client, `quote.internalFee`, `externalFeeAdvanced`, `externalFeeWithheld` **sont exposés** (alors qu'ils sont masqués dans le corps de l'opération).
- `movements[]` : `id`, `amount` number, `direction` (`CREDIT|DEBIT|TRANSFER`), `label` (= `refComment`, peut mentionner des noms de marchands), `at`. Triés du plus ancien au plus récent. Plusieurs lignes normales (prélèvement, versement, restitution).
- `provider` : **absent** pour le client (réservé admin).

**Erreurs** :
| HTTP | code | message |
|---|---|---|
| 404 | `NOT_FOUND` | `Opération introuvable.` (inexistante OU hors de la carte de session — indiscernables) |
| 403 | `FORBIDDEN` | `Session client incomplète.` |
| 401 | | voir Partie 1.6 |

---

### 2. Notifications (boîte in-app) — `src/notifications/notifications.controller.ts`

`@Controller('notifications')`, `@UseGuards(AuthGuard)`, `@AllowedActors('merchant','internal','admin','customer')` au niveau classe → **toutes les routes sont ouvertes au client**, sans permission, sans throttling.

**Cloisonnement** : uniquement par `recipientByString = requester.byString` (= `cid_<cardCustomerIdEnc>` pour Konekt). Aucune route n'accepte d'identifiant de destinataire. Stockage : base **logs** (`prisma-logs-db`, table `notifications`).

> ⚠️ **ÉCART (bug probable)** : `AdminInterventionService` (règlement d'une réclamation porteur, canaux `['whatsapp','sms','in-app']`) dépose le message in-app avec `recipientByString: \`cid_${params.kycId}\`` alors que le porteur connecté lit `cid_<cardCustomerIdEnc>`. Ces messages **n'apparaîtront jamais** dans la boîte Konekt tant que ce n'est pas aligné. C'est le seul émetteur in-app explicitement adressé à un porteur trouvé dans le code.
>
> ⚠️ **Push** : `NotifierService.sendPushNotification` n'est **pas implémenté** (log « message perdu »). Les jetons FCM sont collectés (`POST /auth/customer/devices/push-token`, hors périmètre de ce document) mais rien ne les emploie. → L'app doit **interroger** `GET /notifications/unread-count` (≤ 1 fois/minute) pour la pastille.
>
> Rétention : messages rangés purgés après **90 jours**, tous les autres après **365 jours** (cron 04:00).

#### Modèle `Notification` (réponse brute de la base)
La liste renvoie les lignes Prisma telles quelles (`rows as any`), donc **avec `recipientByString`** en plus des champs documentés :

| Champ | Type | Sens |
|---|---|---|
| `id` | string (cuid) | |
| `recipientByString` | string | `cid_…` (non documenté mais présent) |
| `merchantId` | string\|null | organisation concernée |
| `title` | string | prêt à afficher |
| `message` | string | prêt à afficher, ne pas reformuler |
| `kind` | `NotificationKind` | `INFO`, `SUCCESS`, `WARNING`, `ERROR`, `FINANCIAL`, `SECURITY` (défaut `INFO`) — pilote couleur/icône |
| `linkType` | string\|null | liste **ouverte** : `operation`, `card`, `kyc`, `payout-batch`, `api-key`… Valeur inconnue → pas de lien, pas d'erreur |
| `linkId` | string\|null | id de l'élément (ex. id d'opération → `GET /operations/:id`) |
| `data` | object\|null | forme libre |
| `readAt` | ISO date\|null | null = non lu (compte dans la pastille) |
| `archivedAt` | ISO date\|null | rangé (masqué par défaut) |
| `createdAt` | ISO date | |

`NotificationKind` (schéma logs) : `INFO` information sans action ; `SUCCESS` quelque chose a abouti ; `WARNING` mérite attention, non bloquant ; `ERROR` échec ou action exigée ; `FINANCIAL` argent reçu/versé ; `SECURITY` connexion, changement de code, nouvel appareil.

Canaux de notification de la plateforme (`NotificationChannel` côté notifier) : `email`, `sms`, `whatsapp`, `push` (non implémenté), `in-app`. Préférence du porteur : `PreferredNotificationChannel` = `SMS|EMAIL|WHATSAPP` (un événement = un message sur ce canal, les autres en repli) ; un message au client (`audience: 'CUSTOMER'`) part toujours via la plateforme, quel que soit le mode du marchand.

#### 2.1 `GET /api/v1/notifications` — Mes messages
**Query** (`GetNotificationsQueryDto`) :

| Champ | Type | Règles | Défaut |
|---|---|---|---|
| `page` | int | `@IsInt @Min(1)` | 1 |
| `limit` | int | `@IsInt @Min(1) @Max(50)` | 20 |
| `unreadOnly` | boolean | `'true'`→true | – (tous) |
| `kind` | `NotificationKind` | `@IsIn(Object.values(NotificationKind))` | – |
| `includeArchived` | boolean | `'true'`→true | `false` |

> ⚠️ **ÉCART** : la doc dit « une valeur > 50 est ramenée à 50 sans erreur » ; en réalité `@Max(50)` rejette avec **400 `VALIDATION_FAILED`**. N'envoyez jamais `limit` > 50.

Tri : `createdAt` décroissant.

**Réponse 200** :
```json
{
  "success": true,
  "data": [
    {
      "id": "clnot1234567890",
      "recipientByString": "cid_9f3b…",
      "merchantId": "clm1234567890",
      "title": "Réclamation réglée",
      "message": "Bonjour Kossi, 25 000 XOF ont été recrédités sur votre carte ****4589.",
      "kind": "FINANCIAL",
      "linkType": "operation",
      "linkId": "clop1234567890",
      "data": null,
      "readAt": null,
      "archivedAt": null,
      "createdAt": "2026-10-14T09:14:22.418Z"
    }
  ],
  "unreadCount": 3,
  "pagination": { "page": 1, "limit": 20, "total": 12, "totalPages": 1, "hasNextPage": false, "hasPreviousPage": false }
}
```
- `unreadCount` = non lus **et** non rangés, **indépendant des filtres** (c'est la pastille).
- `pagination.total` = messages correspondant aux filtres.

**Erreurs** : 400 `VALIDATION_FAILED` ; 401 (Partie 1.6).

#### 2.2 `GET /api/v1/notifications/unread-count` — Pastille
Réponse : `{ "success": true, "count": 7 }` (non lus et non rangés). Recommandation code : ≤ 1 appel/minute. Erreurs : 401.

#### 2.3 `POST /api/v1/notifications/read-all` — Tout marquer comme lu
Pas de body. HTTP 200. Marque `readAt=now` sur les non lus **non rangés**.
```json
{ "success": true, "message": "12 notification(s) marquée(s) comme lue(s).", "marked": 12 }
```

#### 2.4 `POST /api/v1/notifications/archive-read` — Ranger tout ce qui est lu
Pas de body. HTTP 200. Range (`archivedAt=now`) tout ce qui est lu et non rangé.
```json
{ "success": true, "message": "8 notification(s) rangée(s).", "archived": 8 }
```

#### 2.5 `POST /api/v1/notifications/:id/read` — Marquer un message lu
Path `id` (string). Pas de body. HTTP 200 → `{ "success": true, "message": "Notification marquée comme lue." }`.
Erreur : **404 `NOT_FOUND` `Notification introuvable.`** si inexistant, appartenant à un autre, **ou déjà lu** → à traiter comme anodin.

#### 2.6 `DELETE /api/v1/notifications/:id` — Ranger un message
Path `id`. HTTP 200 → `{ "success": true, "message": "Notification rangée." }`. Ne supprime pas ; pose `archivedAt` **et** `readAt`. Consultable via `includeArchived=true`.
Erreur : 404 `Notification introuvable.` si inexistant / autre destinataire / **déjà rangé**.

---

### 3. Portefeuilles externes (Mobile Money) — `src/external-wallets/external-wallets.controller.ts`

`@Controller('external-wallets')`, `@UseGuards(AuthGuard)`. Pas de throttling HTTP.

| Route | Client ? |
|---|---|
| `GET /external-wallets/channels` | ✅ |
| `POST /external-wallets/collect/quote` | ❌ (`merchant`,`internal`) → 401 pour un jeton client |
| `POST /external-wallets/payout/quote` | ✅ (avec `fromCard: true` obligatoirement, voir plus bas) |
| `POST /external-wallets/transfer/quote` | ✅ |
| `POST /external-wallets/confirm` | ✅ |

#### 3.0 Règles transverses au client (devis/confirmation)
Appliquées par `QuoteService.request` → `ServiceAccessService.assertCanSell` → `CustomerScopeService.assertMaySell`, puis `CommerceService.execute` :
1. **Marchand du devis = marchand de session** (le contrôleur passe `requester.merchantId`).
2. **Source de fonds** : `MERCHANT_WALLET` interdit au client → 403 `FUNDS_SOURCE_NOT_ALLOWED` (`Le compte du marchand ne peut pas être utilisé depuis l’application. Payez avec votre carte ou votre portefeuille mobile.`). Admises : `CUSTOMER_CARD`, `CUSTOMER_EXTERNAL_CHANNEL`.
3. **Liste blanche libre-service** (`CUSTOMER_ALLOWED_SELLABLES`) : `mobile-topup`, `mobile-data`, `electricity-prepaid`, `electricity-postpaid`, `tv-subscription`, `cash-withdrawal`, `wallet-to-card`, `payout-to-external`, `external-to-external`, `collect-from-external`. Hors liste → 403 `SERVICE_NOT_SELF_SERVICE` (`Ce service n’est pas disponible depuis votre application. Rendez-vous chez un marchand.`).
4. **Souscription du marchand de session** au service (slug) : sinon 403 `« <label> » n'est pas activé sur votre compte. Contactez votre gestionnaire pour y souscrire.` Slugs :
   - versement depuis carte : `merchant:external-wallet:payout:from-card`
   - transfert : `merchant:external-wallet:transfer`
   - (encaissement : `merchant:external-wallet:collect` — route fermée au client)
5. **Service inexistant/inactif** → 404 `« <label> » n'est pas disponible actuellement.` ; source non prévue pour le service → 404 `« <label> » ne peut pas être payé par ce moyen.`
6. **Plafond de devis** : `CUSTOMER_MAX_QUOTES_PER_HOUR` (défaut **60**/heure glissante, 0 = illimité) → 403 `QUOTE_RATE_LIMIT` `Trop de demandes en peu de temps. Patientez quelques minutes.`
7. **Plafonds journaliers à la confirmation** (24 h glissantes, opérations `SUCCESS|PENDING|PROCESSING` créées par `cid_…` de la carte de session ; 0 = illimité) :
   - `CUSTOMER_MAX_OPERATIONS_PER_DAY` (défaut **15**) → 403 `DAILY_OPERATION_LIMIT`
   - `CUSTOMER_MAX_AMOUNT_PER_DAY_XOF` (défaut **500 000**) sur `amount` → 403 `DAILY_AMOUNT_LIMIT`
   - ⚠️ Ce contrôle a lieu **après la consommation du devis** : en cas de refus, le devis est brûlé, il faut en redemander un.
8. `initiationMode` des opérations du client = `CUSTOMER_SELF_SERVICE` (tarif propre, « décote de commission »).
9. Validité du devis : `QUOTE_VALIDITY_MINUTES` (défaut **10 min**) → `expiresAt`.
10. ⚠️ **Aucun contrôle de santé (disjoncteur) n'est fait au devis ni à la confirmation** pour ces services : l'app doit elle-même griser les services `available: false` (voir §4).

#### 3.1 `GET /api/v1/external-wallets/channels` — Catalogue des opérateurs
**But** : opérateurs Mobile Money desservis, pays, **champs de formulaire** et règles de validation. À appeler au démarrage (cache serveur 10 min, non paginé).

**Auth** : `merchant`, `internal`, `customer`. Aucune permission.

**Query** (lus individuellement, non validés) :
| Champ | Type | Effet |
|---|---|---|
| `country` | string (ISO2, casse libre) | ne garde que les canaux ayant ce pays avec `isActive !== false` |
| `operation` | `COLLECT` \| `PAYOUT` | ne garde que `collectEnabled` / `payoutEnabled`. Toute autre valeur = pas de filtre |

Seuls les canaux `isActive && adminEnabled && !deletedAt` sont rendus, triés `sortOrder` puis `displayName`.

**Opérateurs semés (Bénin)** — `prisma-main-db/seeds/_defs/external-channels.ts` :
| `providerSlug` | `displayName` | passerelle | `identifierKind` | `collectApproval` | `holderVerification` |
|---|---|---|---|---|---|
| `MOMO` | MTN Mobile Money | BCP (agrégateur) | `msisdn` | `PAYER_APPROVAL` | false |
| `MOOVMONEY` | Moov Money (Flooz) | BCP | `msisdn` | `PAYER_APPROVAL` | false |
| `CELTISCASH` | Celtiis Mobile Money | BCP | `msisdn` | `PAYER_APPROVAL` | false |
| `BMO` | BestCash Money | `BMO_DIRECT` | `msisdn` | `CONFIRMATION_CODE` | **true** |

> Le slug ne se devine pas : reportez `providerSlug` tel quel dans `channelSlug`. (Les exemples Swagger montrent `momo` en minuscules ; la base contient `MOMO`. Les comparaisons serveur sont insensibles à la casse au moment de la confirmation, mais **utilisez la valeur rendue**.)

**Réponse 200** (`ExternalChannelListResponseDto`) — exemple illustratif : le contenu de `countries`, `collectFields`, `payoutFields`, `collectFlow`, `payoutFlow` vient de la synchronisation avec le prestataire, les valeurs exactes dépendent de la base :
```json
{
  "success": true,
  "data": [
    {
      "id": "clch1234567890",
      "providerSlug": "MOMO",
      "type": "MOBILE_MONEY",
      "name": "MOMO",
      "displayName": "MTN Mobile Money",
      "logo": "https://api.example/public/uploads/external-channels/3f2c….svg",
      "description": null,
      "identifierKind": "msisdn",
      "countries": [{ "iso2": "BJ", "name": "Bénin", "phoneCode": "+229", "currency": "XOF", "isActive": true }],
      "collectFields": [
        {
          "key": "phone", "label": "Numéro de téléphone", "type": "tel", "required": true, "sensitive": false,
          "validation": {
            "default": { "pattern": "^\\+\\d{8,15}$" },
            "byCountry": { "BJ": { "pattern": "^\\+22901\\d{8}$", "example": "+2290167123456", "placeholder": "+229 01 67 12 34 56", "errorMessage": "Numéro Bénin invalide (01 suivi de 8 chiffres).", "limits": { "min": 500, "max": 5000000, "currency": "XOF" } } }
          }
        }
      ],
      "payoutFields": [ "… même structure …" ],
      "collectFlow": "otp_push",
      "payoutFlow": "direct",
      "collectEnabled": true,
      "payoutEnabled": true,
      "sortOrder": 100,
      "collectApproval": "PAYER_APPROVAL",
      "holderVerification": false
    }
  ],
  "count": 4
}
```
Types : `type` ∈ `MOBILE_MONEY|BANK_CARD|BANK_ACCOUNT|CRYPTO` ; `identifierKind` ∈ `msisdn|pan|iban|email|wallet_address` ; `collectFlow`/`payoutFlow` ∈ `direct|otp_push|redirect`|null ; `collectApproval` ∈ `PAYER_APPROVAL|CONFIRMATION_CODE` ; champ `type` ∈ `tel|text|email|card_number|card_expiry|card_cvv|iban` ; `sensitive: true` = ne jamais conserver ni journaliser. `byCountry` prime sur `default`. `countries`, `collectFields`, `payoutFields` sont des JSON synchronisés depuis le prestataire (forme ci-dessus).

**Erreurs** : 401 uniquement.

#### Objet commun `ExternalPartyDto` (payeur ou bénéficiaire)
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `channelSlug` | string | oui | `@IsNotEmpty @MaxLength(40) @Matches(/^\s*[A-Za-z0-9_-]+\s*$/)` — msg `channelSlug : lettres, chiffres, « _ » ou « - » uniquement.` | `MOMO` |
| `identifier` | string | oui | `@IsNotEmpty` ; pour un téléphone : international avec indicatif | `+2290167123456` |
| `firstName` | string | **oui sauf canal B-MO** (contrôle service) | `@MaxLength(80)` | `Kossi` |
| `lastName` | string | **oui sauf canal B-MO** | `@MaxLength(80)` | `Adjovi` |
| `countryCode` | string | non (déduit du numéro sinon — à fournir) | `@MaxLength(2)` | `BJ` |

#### 3.2 `POST /api/v1/external-wallets/payout/quote` — Devis : sortir l'argent de ma carte vers un Mobile Money
**But (client)** : chiffrer un versement **depuis la carte de session** vers un portefeuille Mobile Money (le sien ou celui d'un tiers). HTTP **200**.

**Auth** : `merchant`, `internal`, `customer`. `RequireMerchantPermissions('merchant:external-wallet:payout')` ne s'applique pas au client ; c'est la **souscription du marchand de session** à `merchant:external-wallet:payout:from-card` qui compte.

**Body** (`QuotePayoutDto`) :
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `beneficiary` | `ExternalPartyDto` | oui | `@ValidateNested` | `{ "channelSlug": "MOMO", "identifier": "+2290196000002", "firstName": "Afi", "lastName": "Mensah", "countryCode": "BJ" }` |
| `amount` | int | oui | `@IsInt @Min(500) @Max(5000000)` — ce que le **bénéficiaire reçoit** ; les frais s'ajoutent sur la carte | `25000` |
| `fromCard` | boolean | **oui pour le client (=`true`)** | `@IsBoolean` ; défaut `false` | `true` |
| `reason` | string | non | `@MinLength(8)` (msg `Le motif doit faire au moins 8 caractères, ou être omis.`) `@MaxLength(120)` | `Envoi à maman` |

> ⚠️ Sans `fromCard: true`, la source est `MERCHANT_WALLET` → **403 `FUNDS_SOURCE_NOT_ALLOWED`** pour un client. Le devis ne demande PAS la carte : elle est fournie à la confirmation.

**Logique du devis** (`PayoutToExternalSellable.quote`) :
- canal inconnu/fermé/sans versement → `feasible:false`, `Ce portefeuille ne peut pas recevoir de versement pour le moment. Choisissez un canal de la liste des portefeuilles.`
- nom absent hors B-MO → `feasible:false`, `Le nom du bénéficiaire est requis — le prestataire le transmet à l'opérateur du portefeuille.`
- B-MO : vérification du titulaire ; numéro sans compte → `feasible:false`, `Ce numéro n'a pas de compte <label>. Nous ne versons qu'à un compte existant…` ; B-MO injoignable → `feasible:false` `<label> ne répond pas : le bénéficiaire ne peut pas être vérifié. Réessayez dans quelques instants.` ; trop de vérifications → `Trop de vérifications de bénéficiaires cette heure-ci. Réessayez plus tard.`
- Titulaire vérifié → le nom vérifié remplace le nom saisi ; affiché masqué « Prénom N. ».

**Réponse 200** (`QuoteResponseDto`) :
```json
{
  "success": true,
  "quoteId": "clq1234567890",
  "feasible": true,
  "amount": 25000,
  "internalFee": 550,
  "externalFeeAdvanced": 150,
  "externalFeeWithheld": 0,
  "amountDebited": 25700,
  "amountCredited": 25000,
  "currency": "xof",
  "checks": [{ "key": "beneficiary", "label": "Bénéficiaire", "passed": true, "detail": "Afi Mensah — +2290***02" }],
  "warnings": ["Vérifiez le numéro avant de confirmer : un versement abouti ne peut pas être repris, et nous ne pouvons pas contrôler à qui il appartient."],
  "display": {
    "beneficiaryName": "Afi Mensah",
    "beneficiaryVerified": false,
    "beneficiaryIdentifier": "+2290***02",
    "beneficiaryWillReceive": 25000,
    "irreversible": true
  },
  "expiresAt": "2026-10-15T09:24:22.418Z"
}
```
Devis refusé = **HTTP 200** avec `feasible: false`, `reason` (à afficher tel quel), montants à 0, `checks` indiquant le contrôle en échec. **Testez toujours `feasible`.** Afficher `amountDebited` (total prélevé sur la carte) et `amountCredited`. Ne pas additionner `externalFeeWithheld`.

**Erreurs** : 400 `VALIDATION_FAILED` ; 401 ; 403 `FUNDS_SOURCE_NOT_ALLOWED` / `SERVICE_NOT_SELF_SERVICE` / `QUOTE_RATE_LIMIT` / service non souscrit (`FORBIDDEN`) / `Vous ne pouvez pas demander un devis pour le compte d’un autre marchand.` ; 404 service indisponible/non payable par ce moyen ; 400 `Aucun marchand ne peut porter cette opération.` ; 503 `PROVIDER_UNAVAILABLE` prestataire injoignable.

#### 3.3 `POST /api/v1/external-wallets/transfer/quote` — Devis : Mobile Money → Mobile Money
**But** : transfert d'un portefeuille mobile (payeur, qui valide sur son téléphone) vers un autre, y compris inter-opérateurs. Source `CUSTOMER_EXTERNAL_CHANNEL` (admise pour le client). Le plus cher : deux passages chez le prestataire, payeur supporte les deux frais. HTTP 200.

**Body** (`QuoteTransferDto`) :
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `payer` | `ExternalPartyDto` | oui | portefeuille débité | `{ "channelSlug": "MOOVMONEY", "identifier": "+2290197000001", "firstName": "Kossi", "lastName": "Adjovi", "countryCode": "BJ" }` |
| `beneficiary` | `ExternalPartyDto` | oui | ≠ payeur | `{ "channelSlug": "MOMO", "identifier": "+2290196000002", "firstName": "Afi", "lastName": "Mensah", "countryCode": "BJ" }` |
| `amount` | int | oui | `@Min(500) @Max(5000000)` — ce que le **destinataire reçoit** | `25000` |
| `reason` | string | non | 8–120 car. | `Remboursement dîner` |

**Contrôles** : canal payeur absent → `feasible:false` (`payerAccount`) `Précisez le portefeuille du payeur (canal et numéro)…` ; canal payeur inconnu/fermé/sans encaissement → `Ce portefeuille n’est pas disponible. Choisissez un canal de la liste des portefeuilles.` ; `payer` (`Le portefeuille source doit être précisé.`), `beneficiary` (`Le portefeuille destinataire doit être précisé.`, nom requis hors B-MO, compte B-MO inexistant), `distinct` (même portefeuille → refus).
**`display`** : `payerIdentifier` (masqué), `beneficiaryName`, `beneficiaryIdentifier` (masqué), `beneficiaryWillReceive`, `requiresPayerApproval: true`, `irreversible: true`. **Warnings** à afficher (validation sur téléphone ; si payeur B-MO : `Vous recevrez un code de <label> par SMS : saisissez-le pour valider le paiement.`).
Erreurs : identiques à 3.2 (le `FUNDS_SOURCE_NOT_ALLOWED` ne se produit pas).

#### 3.4 `POST /api/v1/external-wallets/confirm` — Confirmer et exécuter
**But** : honorer un devis. Prix figés, disponibilités revérifiées. HTTP 200.

**Auth** : `merchant`, `internal`, `customer`. Aucune permission propre. Seul l'**auteur du devis** (même `byString`, donc même session-carte) peut le confirmer.

**Body** (`ConfirmExternalWalletDto`) :
| Champ | Type | Requis | Règles | Exemple |
|---|---|---|---|---|
| `quoteId` | string | oui | `@IsNotEmpty` | `clq1234567890` |
| `service` | enum | oui | `@IsIn(['collect-from-external','payout-to-external','external-to-external'])` — **identique au devis** | `payout-to-external` |
| `payer` | `ExternalPartyDto` | requis pour `external-to-external` | même canal + même numéro que le devis | |
| `card` | `CardSourceDto` | requis pour `payout-to-external` client | voir ci-dessous | |
| `reference` | string | recommandé | `@MaxLength(64)` ; idempotence | `KNK-6f1c2b9e-7d4e-4a51` |
| `pin` | string | **requis si paiement par carte (client)** | `@Matches(/^\d{6}$/)` msg `Six chiffres attendus.` | `482915` |
| `cardOtp` | string | non (marchand/clé seulement) | `^\d{6}$` | |

`CardSourceDto` : `cardCustomerId` (string, requis, **identifiant émetteur en clair de la carte de session**), `cardTierSlug` (string, optionnel), `last4` (string, optionnel, `^\d{4}$` msg `Quatre chiffres attendus.` — s'il est fourni il est comparé à l'émetteur → `CARD_MISMATCH`).

**Exemples**
```json
// Versement depuis ma carte
{ "quoteId": "clq1234567890", "service": "payout-to-external",
  "card": { "cardCustomerId": "121436474" }, "pin": "482915",
  "reference": "KNK-6f1c2b9e-7d4e-4a51-9c1e-0b7a2f3d9e11" }

// Transfert Mobile Money → Mobile Money
{ "quoteId": "clq1234567891", "service": "external-to-external",
  "payer": { "channelSlug": "MOOVMONEY", "identifier": "+2290197000001", "firstName": "Kossi", "lastName": "Adjovi", "countryCode": "BJ" },
  "reference": "KNK-0c5d…" }
```

**Ordre des contrôles** (utile pour l'UX) :
1. **PIN vérifié d'abord** (dans le contrôleur, `buildCardConsent`) si `card` est fourni : `pin` absent → 400 `CARD_CONSENT_REQUIRED` `Votre code secret est requis pour payer avec votre carte.` ; carte externe (pas de dossier KYC en session) → 403 `CARD_CONSENT_UNAVAILABLE` ; PIN faux → 403 `Code incorrect — N tentative(s) restante(s).` ; verrou → 403 `Trop de codes erronés. Votre compte est bloqué pendant <N> minutes. Vous pouvez aussi réinitialiser votre code.` / `Trop de codes erronés. Réessayez dans N minute(s), ou réinitialisez votre code.` ; aucun PIN défini → 400 `Aucun code secret n’a encore été défini pour ce compte.` (défauts : 5 essais `CUSTOMER_PIN_MAX_ATTEMPTS`, verrou 15 min `CUSTOMER_PIN_LOCK_MINUTES`).
2. **Rejeu** : si `reference` déjà utilisée pour le même `merchantId` du devis → l'opération existante est rendue telle quelle (pas de nouvelle exécution).
3. Service ≠ devis → 400 `QUOTE_SERVICE_MISMATCH`.
4. Payeur ≠ devis (canal ou numéro) → 400 `QUOTE_FUNDING_MISMATCH` (le devis reste utilisable).
5. Nom du payeur manquant hors B-MO → 400 `PARTY_NAME_REQUIRED`.
6. Devis carte sans `card` → 400 `CARD_SOURCE_REQUIRED` ; carte ≠ carte de session → 403 `Vous ne pouvez agir que sur la carte avec laquelle vous vous êtes connecté. Reconnectez-vous avec l’autre carte pour l’utiliser.` ; consentement absent → 403 `CARD_CONSENT_REQUIRED`.
7. Consommation du devis : introuvable/autre auteur → 404 `Devis introuvable.` / `Devis introuvable. Demandez-en un nouveau.` ; refusé → 400 (motif du refus) ; déjà servi → 400 `Ce devis a déjà servi. Demandez-en un nouveau.` ; expiré → 400 `Ce devis a expiré. Les prix ont pu changer : demandez-en un nouveau.` ; course → 400 `Ce devis vient d’être utilisé. Demandez-en un nouveau.`
8. Plafonds journaliers → 403 `DAILY_OPERATION_LIMIT` / `DAILY_AMOUNT_LIMIT` (devis déjà consommé).
9. Exécution (prélèvement, puis service). Référence concurrente → 400 `Une vente portant la référence « … » est déjà en cours de traitement.` ; solde carte insuffisant ou refus prestataire → erreur du module de financement (codes déclarés `INSUFFICIENT_FUNDS` / `PROVIDER_REJECTED` dans `EXTERNAL_WALLET_ERROR_CODES` ; selon le chemin, le message peut sortir en `REQUEST_REJECTED`/`PROVIDER_UNAVAILABLE`) ; issue indéterminée → **500**, l'opération part en revue : **ne pas relancer**.

**Réponse 200** (`ExecutionResponseDto`) :
```json
{
  "success": true,
  "operationId": "clop1234567890",
  "reference": "WOP-20261015-091422-A7B9",
  "status": "SUCCESS",
  "amount": 25000,
  "internalFee": 550,
  "externalFeeAdvanced": 150,
  "externalFeeWithheld": 0,
  "merchantReference": "KNK-6f1c2b9e-7d4e-4a51-9c1e-0b7a2f3d9e11",
  "amountDebited": 25700,
  "amountCredited": 25000,
  "providerReference": "BCP-TXN-8891234",
  "completed": true,
  "awaiting": null,
  "message": "Versement vers un portefeuille externe effectué avec succès."
}
```
- Versement (`payout-to-external`) → `completed: true` (abouti ou échoué).
- Transfert (`external-to-external`) → `completed: false`, `status: "PENDING"`, `awaiting` :
  - `PAYER_APPROVAL` : le payeur valide sur son téléphone → écran d'attente, suivre via `GET /operations/:id` ;
  - `CONFIRMATION_CODE` (payeur B-MO) : saisir le code via `POST /commerce/operations/{operationId}/funding/confirm` (annuler : `…/funding/cancel`) — routes du module commerce, hors de ce document ;
  - `PROVIDER_SETTLEMENT` : le prestataire n'a pas répondu → attendre, ne rien relancer.
- `message` : affichage uniquement ; décider sur `status` + `completed`.

> ⚠️ **ÉCART (sécurité / intégrité)** — l'idempotence est indexée sur le couple **(marchand du devis, `reference`)**. Pour un client, le marchand est le **marchand de session**, partagé par de nombreux porteurs, et `_findReplay` ne vérifie pas l'auteur : si deux porteurs d'un même marchand de session utilisent la même `reference`, le second reçoit **l'opération du premier** (et rien n'est exécuté). **Konekt doit générer des références globalement uniques** (UUID v4, préfixées p. ex. `KNK-`), jamais un compteur local.
>
> ⚠️ L'encaissement `collect-from-external` figure dans la liste blanche client mais la route de devis `POST /external-wallets/collect/quote` n'admet pas `customer` : le client **ne peut pas** obtenir ce devis par ce module.

---

### 4. Disponibilité des services — `src/service-health/service-health.controller.ts`

`@Controller()` sans préfixe propre. Routes `admin/*` non accessibles au client.

#### 4.1 `GET /api/v1/services/available` — Ce que je peux faire maintenant (DÉPRÉCIÉE)
**Statut** : `deprecated: true` → préférer `GET /catalog/services` (module catalog, hors de ce document), qui ajoute bornes, frais et services de carte. Cette route reste en place.

**Auth** : `@UseGuards(AuthGuard)`, `@AllowedActors('merchant','internal','customer')`. Pas de throttling.

**Query** (non validés) :
| Champ | Type | Effet |
|---|---|---|
| `beneficiaryCountry` | string ISO2 | ne garde que les services dont `countryCodes` contient ce pays ou `*` ; absent = toute l'offre |
| `availableOnly` | `'true'` | ne rend que `available: true` (déconseillé : préférer griser) |

**Logique** (`ServiceCatalogService.list`) pour un client (`merchantId` = marchand de session) :
- services existants et actifs, desservis dans la zone, **et souscrits par le marchand de session** ;
- `fundsSources` = sources dont le service est souscrit ;
- santé : seule la cible `SELLABLE_SERVICE:<key>` est lue (pas le prestataire) : `DOWN` → `available:false`, `unavailableReason: "Momentanément indisponible — nos équipes travaillent au rétablissement."` ; `MAINTENANCE` → `"En maintenance."` ; `HEALTHY`/`DEGRADED`/aucune surveillance → `available: true`.

> ⚠️ **ÉCART** : cette route n'applique **ni** la liste blanche libre-service (§3.0-3) **ni** l'exclusion de `MERCHANT_WALLET`. Un client y voit p. ex. `card-purchase` ou des `fundsSources: ["MERCHANT_WALLET"]` qui seront refusés au devis. Côté Konekt, filtrez : `key ∈ liste blanche` ET `fundsSources ∩ {CUSTOMER_CARD, CUSTOMER_EXTERNAL_CHANNEL}` non vide — ou utilisez `/catalog/services`.

**Réponse 200** (`CatalogResponseDto`) :
```json
{
  "success": true,
  "data": [
    {
      "key": "payout-to-external",
      "label": "Versement vers un portefeuille externe",
      "category": "wallet",
      "fundsSources": ["MERCHANT_WALLET", "CUSTOMER_CARD"],
      "countryCodes": ["BJ"],
      "available": true,
      "uptimePercent": 99.7
    },
    {
      "key": "electricity-prepaid",
      "label": "Électricité prépayée",
      "category": "addon",
      "fundsSources": ["CUSTOMER_CARD", "CUSTOMER_EXTERNAL_CHANNEL"],
      "countryCodes": ["BJ"],
      "available": false,
      "unavailableReason": "Momentanément indisponible — nos équipes travaillent au rétablissement."
    }
  ],
  "count": 2
}
```
Champs : `key` (clé du vendable, celle à utiliser pour les devis), `label`, `category|null`, `fundsSources: string[]`, `countryCodes: string[]` (`*` = partout), `available: boolean`, `unavailableReason?` (présent seulement si `available:false`), `uptimePercent?` (absent tant qu'aucun relevé).

**Comment l'app doit désactiver un service** : à l'ouverture de chaque parcours (pas une fois par jour), recharger le catalogue ; si `available === false`, **griser** la tuile (ne pas la masquer) et afficher `unavailableReason` tel quel ; `DEGRADED` reste utilisable. Un service absent de la liste n'est pas ouvert pour ce porteur (non souscrit par le marchand de session ou hors zone). Rappel : le serveur ne bloque pas un devis sur un service `DOWN` (§3.0-10), c'est donc à l'app de le faire.

Erreurs : 401.

#### 4.2 `GET /api/v1/status` — Page d'état publique
**Auth** : **aucune** (pas d'`AuthGuard`) — accessible sans jeton (un jeton éventuel est ignoré).

**Logique** : cibles `isMonitored = true` et `targetKind ≠ RESOURCE` (services vendables + prestataires), triées par `label`.
- `overall` : `operational` si aucune cible ≠ `HEALTHY` (y compris liste vide) ; `major_outage` si toutes ≠ `HEALTHY` ; sinon `partial_outage`. ⚠️ `DEGRADED` compte comme dégradé ici.

**Réponse 200** (`PublicStatusResponseDto`) :
```json
{
  "success": true,
  "overall": "partial_outage",
  "checkedAt": "2026-10-15T09:14:22.418Z",
  "services": [
    { "name": "Électricité prépayée", "status": "DOWN", "uptime": 97.2, "lastCheckedAt": "2026-10-15T09:10:00.000Z" },
    { "name": "Portefeuilles mobiles", "status": "HEALTHY", "uptime": 99.7, "lastCheckedAt": "2026-10-15T09:13:00.000Z" }
  ]
}
```
- `services[].name` = libellé public (aucune clé technique → **ne pas** s'en servir pour mapper un service ; utiliser 4.1 / `/catalog/services`). Usage Konekt : bannière globale « incident en cours » si `overall !== 'operational'`.
- `status` ∈ `HealthStatus` (§7.6), `uptime` number|null, `lastCheckedAt` date|null.

Erreurs : aucune spécifique.

---

### 5. Référentiel géographique — `src/geo/geo.controller.ts`

`@Controller('geo')`, `@UseGuards(AuthGuard)`, `@AllowedActors('visitor','customer','merchant','admin','internal')`. Données statiques embarquées (`geo.data.ts`, **53 pays actifs**). Pas de throttling.

**Auth** : ouvert sans jeton (visiteur). ⚠️ Si un jeton est joint, il **doit être valide** (jeton expiré → 401). Le jeton client valide est accepté.

#### 5.1 `GET /api/v1/geo/countries`
Réponse :
```json
{ "success": true, "data": [ { "code": "BJ", "name": "Benin" }, { "code": "BF", "name": "Burkina Faso" }, { "code": "TG", "name": "Togo" } ] }
```
- `code` ISO 3166-1 alpha-2 majuscule — **c'est la valeur à transmettre** (dossiers KYC, résolution du marchand régional).
- `name` : ⚠️ **ÉCART** — la doc annonce « en français » mais les noms embarqués sont **en anglais** (`Benin`, `Belgium`, `Democratic Republic of the Congo`). Tri `localeCompare(…, 'fr')`. À localiser côté app si besoin.
- Non paginé, immuable : à mettre en cache.

#### 5.2 `GET /api/v1/geo/countries/:countryCode/states`
Path `countryCode` (casse libre, espaces retirés).
```json
{ "success": true, "countryCode": "BJ", "data": [ { "code": "AL", "name": "Alibori" }, { "code": "AK", "name": "Atakora" }, { "code": "AQ", "name": "Atlantique" }, { "code": "LI", "name": "Littoral" } ] }
```
- Codes ISO 3166-2 **sans préfixe pays** (`LI`, pas `BJ-LI`). Bénin : `AL, AK, AQ, BO, CO, DO, KO, LI, MO, OU, PL, ZO`.
- Liste vide = pays sans subdivision référencée **ou** pays inconnu (indiscernables) → masquer le 2ᵉ sélecteur ; dans ce cas n'importe quel code de région est accepté par la validation.
- Erreurs : aucune (jamais 404).

---

### 6. Autres routes publiques ou utilisables par Konekt (hors cards/catalog/commerce/customer-auth/card-display)

Recherche faite sur tout `src/` (`@AllowedActors` contenant `customer` ou `visitor`, contrôleurs sans `AuthGuard`, `@Public`/`IsPublic` — **aucun décorateur `@Public` n'existe** ; la publicité d'une route = `visitor` dans `@AllowedActors` ou absence d'`AuthGuard`).

Résultat : en dehors des 5 contrôleurs ci-dessus et des modules exclus, **aucune autre route n'admet `customer`**. Les routes publiques (visiteur) pertinentes pour Konekt sont celles de l'**onboarding KYC** (inscription d'un futur porteur, avant d'avoir une carte/session).

> ⚠️ Toutes les routes §6.1–6.3 n'admettent pas `customer` : **appelez-les SANS en-tête `Authorization`** (sinon 401 `Jeton non reconnu pour cette route`).
> Pour `app-config`, `regional-defaults`, `brandings`, `webhooks` : aucune route publique ni client (admin/marchand uniquement). Le branding white-label et l'enregistrement du jeton push (`POST /auth/customer/devices/push-token`, `fcmToken`) relèvent de `customer-auth` (hors de ce document).

#### 6.1 Preuves OTP visiteur — `src/auth/customer-otp.controller.ts` (`/auth/customer-otp`)
`@UseGuards(AuthGuard, RequesterThrottlerGuard)`, `@AllowedActors('visitor','merchant','internal')`. Pour un visiteur, le throttling est **par IP**. Prérequis de tout le parcours KYC.

| Route | Throttle | Body | Réponse |
|---|---|---|---|
| `POST /api/v1/auth/customer-otp/phone/init` | 30/min | `phoneCode` (`^\+\d{1,4}$`, msg `L'indicatif doit commencer par + suivi de 1 à 4 chiffres (ex. +229).`), `phone` (`^\d{6,15}$`, msg `Le numéro doit contenir entre 6 et 15 chiffres, sans espaces.`), `displayName?` (≤80, `^[\p{L}][\p{L}\s'’.-]{0,79}$` — **ignoré pour un visiteur**), `channel?` (`SMS`\|`WHATSAPP`, défaut `SMS`) | `InitOtpResponseDto` |
| `POST /api/v1/auth/customer-otp/phone/confirm` | 60/min | `phoneCode`, `phone`, `code` (6 chiffres, msg `Six chiffres attendus.`) | `ConfirmOtpResponseDto` |
| `POST /api/v1/auth/customer-otp/email/init` | 30/min | `email` (`@IsEmail` msg `Adresse email invalide.`, ≤180), `displayName?` (ignoré visiteur) | `InitOtpResponseDto` |
| `POST /api/v1/auth/customer-otp/email/confirm` | 60/min | `email`, `code` (6 chiffres) | `ConfirmOtpResponseDto` |

```json
// InitOtpResponseDto
{ "success": true, "message": "Code OTP envoyé avec succès", "method": "SMS", "maskedContact": "+229***456", "expiresIn": 300, "attemptsLeft": 3 }
// ConfirmOtpResponseDto
{ "success": true, "message": "Code OTP vérifié avec succès", "identityToken": "idt_lxk8f2_a3b4c5d6e7f8…", "expiresIn": 1800, "tokenType": "identity_verification", "attemptsLeft": 5, "context": { "purpose": "…" } }
// context : aide au diagnostic seulement (OtpPurpose), ne pas en dépendre
```
- Code : 5 min, 3 essais. `method` peut différer du canal demandé (repli) → afficher celui-ci.
- `identityToken` téléphone (`phoneProofToken`) : **30 min, usage unique** (consommé à l'ouverture d'un dossier ou à la réutilisation ; `POST /kyc/lookup` ne le consomme pas).
- `identityToken` e-mail (`emailProofToken`) : **72 h, réutilisable** → le conserver côté app.
- Erreurs : 400 envoi impossible (opérateur) / code incorrect, expiré ou déjà utilisé ; 429 `RATE_LIMITED` (trop de codes vers ce numéro/adresse dans l'heure, ou trop d'appels) ; 401 si un jeton client est joint.

#### 6.2 Réutilisation d'identité — `src/kyc/kyc-reuse.controller.ts` (`/kyc`)
`@AllowedActors('visitor','merchant','internal')`, pas de throttling.

**`POST /api/v1/kyc/lookup`** (HTTP 200) — Body `KycLookupDto` : `phoneCode` (`^\+\d{1,4}$`), `phone` (`^\d{6,15}$`), `phoneProofToken` (string ≥16, vérifié **non consommé**).
```json
{ "success": true, "state": "REUSABLE", "reusable": true, "nextProof": "DOC_SERIAL", "requiresNewKyc": false, "resumableKycId": null, "message": "Une identité vérifiée existe pour ce numéro. Saisissez le numéro de votre pièce d’identité pour la réutiliser." }
```
`state` : `NEW` (ouvrir un dossier) · `REUSABLE` (confirmer par n° de pièce) · `RESUMABLE` (reprendre `resumableKycId`) · `IN_PROGRESS` (examen en cours) · `BLOCKED` (support). Aucune donnée personnelle renvoyée. Erreur : 403 preuve téléphone invalide/expirée.

**`POST /api/v1/kyc/reuse`** (HTTP 200) — Body `ConfirmKycReuseDto` = lookup + `docSerial` (string ≤60) + `emailProofToken?` (≥16, requis si l'e-mail du dossier n'a jamais été vérifié).
```json
{ "success": true, "message": "Identité confirmée. L’achat peut se poursuivre sans nouvelle vérification.", "data": { "kycId": "clkyc1234567890", "firstName": "Kossi", "lastName": "Adjovi", "existingCardsCount": 2 } }
```
Erreurs : 403 `Le numéro de pièce ne correspond pas à celui du dossier associé à ce téléphone…` ; 403 `L'adresse email de ce dossier n'a jamais été vérifiée. Vérifiez-la avant de poursuivre.` ; 403 `Cette validation vient d’être utilisée. Demandez un nouveau code.` ; 409 `Aucune identité réutilisable pour ce numéro. Reprenez le parcours depuis le début.`
> ⚠️ **ÉCART** : `phone/confirm` annonce « 5 tentatives sur le numéro de pièce » (`attemptsLeft: 5`), mais `confirmReuse` **consomme la preuve téléphone avant la comparaison** : **une seule tentative par code SMS**. Prévoir un nouvel OTP après un échec.

#### 6.3 Constitution du dossier KYC — `src/kyc/kyc.controller.ts` (`/kyc`)
Accès visiteur : identifié uniquement par la connaissance du `kycId`. Pas de throttling. Taille max fichier 15 Mo.

| Méthode & chemin | Acteurs | Rôle |
|---|---|---|
| `POST /api/v1/kyc/submit-complete` (202, multipart) | visitor, merchant, internal | dossier complet en un appel |
| `POST /api/v1/kyc` (201) | visitor, merchant | ouvrir (ou reprendre) un dossier |
| `POST /api/v1/kyc/:kycId/pieces/:kind` (202, multipart, champ `file`) | visitor, merchant | envoyer une pièce |
| `PATCH /api/v1/kyc/:kycId/fields` (200) | visitor, merchant | compléter/corriger |
| `GET /api/v1/kyc/:kycId/recap` (200) | visitor, merchant, internal, admin | récapitulatif |
| `GET /api/v1/kyc/:kycId/progress` (200) | visitor, merchant, internal, admin | avancement (polling 5 s) |
| `POST /api/v1/kyc/:kycId/finalize` (200) | visitor, merchant | conclure |
| `PATCH /api/v1/kyc/:kycId/record` (200) | visitor, merchant, internal, admin | actualiser les coordonnées d'un dossier **vérifié** |

**`POST /kyc`** — `CreateKycDraftDto` : `phoneCode` (`^\+\d{1,4}$`), `phone` (`^\d{6,15}$`), `email` (`@IsEmail`, ≤180, requis), `phoneProofToken` (≥16, **consommé**). Réponse : `{ "success": true, "kycId": "clkyc…", "status": "DRAFT", "resumed": false }`. Erreurs : 403 preuve téléphone invalide ; 409 dossier déjà vérifié (→ parcours réutilisation) ou nécessitant le support.

**`POST /kyc/:kycId/pieces/:kind`** — `kind` ∈ `ID_DOCUMENT|SELFIE|SIGNATURE` (`ParseEnumPipe`) ; fichier dans le champ **`file`** ; JPEG/PNG/WebP (PDF accepté pour `ID_DOCUMENT`, 1ʳᵉ page convertie) ; type réel détecté par le contenu. Réponse : `{ "success": true, "kycId": "clkyc…", "kind": "ID_DOCUMENT", "analysisPending": true }`. Erreurs : 400 `Aucun fichier reçu. Le fichier doit être envoyé dans un champ nommé « file ».` / trop lourd / format refusé ; 409 dossier déjà soumis.

**`PATCH /kyc/:kycId/fields`** — `UpdateKycFieldsDto`, tout optionnel : `countryCode` (Length 2,2), `country` (≤80), `stateCode` (≤10), `state` (≤80), `city` (≤80), `address` (≤255), `job` (≤120), `salaryRange` (`LESS_THAN_200K|FROM_200K_TO_500K|GREATER_THAN_500K`), `preferredChannel` (`SMS|EMAIL|WHATSAPP`), `firstName` (≤80), `lastName` (≤80), `gender` (`MALE|FEMALE|OTHER`), `birthday` (ISO strict `AAAA-MM-JJ`, msg `Date attendue au format AAAA-MM-JJ.`), `docType` (`NATIONAL_ID_CARD|PASSPORT|DRIVER_LICENSE|OTHER_DOCS`), `docSerial` (≤60). Codes pays/région validés contre `/geo`. Réponse : `{ "success": true, "kycId": "…", "hasManualCorrections": false }` (true = une valeur lue automatiquement a été modifiée → revue humaine). Erreurs : 400 `Pays inconnu : « X ». Un code ISO à deux lettres est attendu (ex. BJ).` / `Subdivision « X » inconnue pour <Pays>. Valeurs possibles : …` ; 503 zone non desservie (aucun marchand).

**`GET /kyc/:kycId/recap`** → `data` : `kycId, status, phoneCode, phone, email, emailVerified, firstName, lastName, gender, birthday, countryCode, country, stateCode, state, city, address, job, salaryRange, docType, docSerial, docExpiresAt, hasManualCorrections, pieces{idDocument,selfie,signature}, qualityIssues[], missingFields[], readyToFinalize, requiredActions[{kind: 'UPLOAD_PIECE'|'FILL_FIELD', target, label, blocking}]`. `requiredActions` dit exactement quel appel faire (UPLOAD_PIECE → `POST /kyc/{kycId}/pieces/{target}` ; FILL_FIELD → `PATCH /kyc/{kycId}/fields`). 404 dossier introuvable.

**`GET /kyc/:kycId/progress`** → `{ success, kycId, status, sections: { ocr, selfie, signature }, reason, emailVerified }` ; `sections.*` ∈ `NOT_SUBMITTED|PENDING|DONE|FAILED` (signature indicative) ; `reason` en clair en cas de refus/complément. Aucune donnée personnelle. 404.

**`POST /kyc/:kycId/finalize`** — `FinalizeKycDto` : `emailProofToken` (≥16, requis), `merchantCode?` (≤20, code marchand parrain, ex. `MCH_A7B9C2D4E` ; à défaut, couverture géographique). Réponse : `{ success, kycId, status, concluded, pendingSections[] }` (`concluded:false` → analyse non terminée, continuer à interroger `/progress`). Erreurs : 400 dossier incomplet ; 403 preuve e-mail invalide/expirée ; 503 zone non desservie.

**`POST /kyc/submit-complete`** (multipart) — union des trois DTO (`CreateKycDraftDto` + `UpdateKycFieldsDto` + `FinalizeKycDto`) + fichiers `idDocument` (requis), `selfie` (requis à distance), `signature`. Réponse 202 : `{ success, kycId, status, message: "Dossier reçu. L'analyse est en cours, son résultat vous sera notifié." }`. Erreurs : 400, 403, 409 (dossier existant pour ce numéro), 503.

**`PATCH /kyc/:kycId/record`** — `UpdateApprovedKycDto` : `countryCode, country, stateCode, state, city, address, job, salaryRange, preferredChannel, email` (+ `emailProofToken` requis si l'e-mail change), `phoneProofToken` (**obligatoire pour un titulaire agissant seul**). Aucun champ d'identité. Réponse : `{ success, kycId, status: "APPROVED", updatedFields: [...] }`. Erreurs : 400 preuve manquante ; 409 dossier non vérifié.
> ⚠️ Un porteur **connecté** ne peut pas appeler cette route avec son jeton (401) : il doit l'appeler sans jeton, en visiteur, avec un `phoneProofToken` frais.

`KycStatus` : `DRAFT`, `PENDING_AI`, `AI_REJECTED`, `PENDING_MERCHANT`, `APPROVED`, `EXPIRED`, `REVOKED`, `KYC_CONFLICT`.

#### 6.4 Santé et fichiers
- `GET /health` (**hors préfixe**, sans auth) → `{ "status": "ok", "at": "2026-10-15T09:14:22.418Z" }`. Sonde de disponibilité ; ne dit rien de l'état interne.
- `GET /api/v1/health/ready` (exclu de Swagger ; l'exclusion de préfixe ne vise que `/health` exact, donc cette sous-route est **sous** `/api/v1`) → `{ "status": "ready" }` ou `{ "status": "not-ready" }` (toujours HTTP 200).
- `GET /public/<chemin>` : fichiers statiques (logos des canaux, uploads). Cache 1 jour en production, `X-Robots-Tag: noindex`, pas de listage. Les URL de logos sont déjà absolues dans `/external-wallets/channels`.

#### 6.5 Routes publiques NON destinées à Konekt (pour mémoire)
- `POST /api/v1/callbacks/bcp` — rappel du prestataire de paiement (pas d'`AuthGuard`, contrôle d'origine/IP) : **ne jamais appeler depuis l'app**.
- `POST /api/v1/internal/auth/verify-api-key` — usage passerelle interne.
- `/api/v1/merchants/registration*` (`POST registration`, `GET registration/:trackingCode/status`, `GET registration/:trackingCode/edit-access`, `PATCH registration/:idOrTrackingCode/update-as-guest`, `GET registration/:idOrTrackingCode`) — inscription d'un **marchand**, sans rapport avec le porteur.

---

### 7. Énumérations utiles au front

Source : `prisma-main-db/schema.prisma` (sauf mention). Le schéma ne commente pas `OperationStatus`/`OperationType` ; les sens ci-dessous sont déduits de leur usage dans le code.

#### 7.1 `OperationStatus`
| Valeur | Sens pour le porteur | Groupe `stats` |
|---|---|---|
| `INITIALIZED` | opération créée, exécution pas encore engagée | pending |
| `PENDING` | engagée, en attente (validation du payeur sur téléphone, code B-MO, verdict prestataire) — **service pas encore rendu, ne rien relancer** | pending |
| `PENDING_APPROVAL` | débit carte en attente de l'accord du porteur (code OTP) | pending |
| `PROCESSING` | en cours de traitement chez nous/prestataire | pending |
| `SUCCESS` | abouti | successful |
| `FAILED` | échoué (motif dans `failureReason`) | failed |
| `CANCELLED` | annulé (motif dans `cancellationReason`) | failed |
| `REVERSED` | défaite/contre-passée (mouvements qui s'annulent) | total seulement |
| `REFUNDED` | échouée **et** remboursée à la source | total seulement |
| `EXPIRED` | expirée sans validation du client | failed |

#### 7.2 `OperationType` (valeurs pertinentes pour un porteur)
| Valeur | Services |
|---|---|
| `CARD_OPERATION` | opérations carte : achat de carte (`card-purchase`), recharge `wallet-to-card`, débits/crédits carte |
| `WALLET_OPERATION` | portefeuilles externes : `payout-to-external`, `external-to-external`, `collect-from-external` |
| `ADDON_SALE` | services de proximité : `mobile-topup`, `mobile-data`, `electricity-prepaid`, `electricity-postpaid`, `tv-subscription` |
| `CASH_WITHDRAWAL` | retrait au guichet (`cash-withdrawal`) |
| `REFUND` | remboursement |
| `BANK_TRANSFER`, `CARD_STOCK_OPERATION`, `COMMISSION_PAYOUT` | côté marchand/plateforme, peu probables pour un porteur |

#### 7.3 Autres énumérations d'opération
- `OperationInitiationMode` : `MERCHANT_ASSISTED` (comptoir), `CUSTOMER_SELF_SERVICE` (app Konekt), `API_KEY` (partenaire).
- `OperationCardRole` : `MAIN` (carte unique), `SOURCE` (carte débitée), `TARGET` (carte créditée).
- `EntryDirection` (mouvements) : `CREDIT`, `DEBIT`, `TRANSFER`.
- `CardType` : `VIRTUAL`, `PHYSICAL`.
- `QuoteFundsSource` : `MERCHANT_WALLET` (interdit au client), `CUSTOMER_CARD`, `CUSTOMER_EXTERNAL_CHANNEL`.
- `QuoteStatus` : `OPEN`, `CONSUMED`, `EXPIRED`, `REJECTED`.
- `awaiting` (exécution) : `PAYER_APPROVAL`, `CONFIRMATION_CODE`, `PROVIDER_SETTLEMENT`, `null`.
- Parties : `PartyRole` = `PAYER` | `BENEFICIARY`.

#### 7.4 Notifications
- `NotificationKind` (`prisma-logs-db/schema.prisma`) : `INFO`, `SUCCESS`, `WARNING`, `ERROR`, `FINANCIAL`, `SECURITY`.
- `linkType` (ouvert) : `operation`, `card`, `kyc`, `payout-batch`, `api-key`, …
- Canaux d'envoi : `email`, `sms`, `whatsapp`, `push` (non implémenté), `in-app`. Préférence porteur `PreferredNotificationChannel` / `DeliveryChannel` : `SMS`, `EMAIL`, `WHATSAPP`.

#### 7.5 Portefeuilles externes
- `ExternalChannelType` : `MOBILE_MONEY`, `BANK_CARD`, `BANK_ACCOUNT`, `CRYPTO`.
- `ExternalChannelGateway` (non exposé) : `BCP` (agrégateur), `BMO_DIRECT` (B-MO ; → `holderVerification: true`, `collectApproval: CONFIRMATION_CODE`, nom du tiers facultatif).
- `ExternalWalletService` : `collect-from-external`, `payout-to-external`, `external-to-external`.
- Codes d'erreur du module (`EXTERNAL_WALLET_ERROR_CODES`) : `CHANNEL_NOT_AVAILABLE`, `CHANNEL_COUNTRY_NOT_SERVED`, `MERCHANT_WALLET_UNAVAILABLE`, `SAME_WALLET_TRANSFER`, `PARTY_NAME_REQUIRED`, `QUOTE_EXPIRED`, `QUOTE_ALREADY_CONSUMED`, `QUOTE_SERVICE_MISMATCH`, `INSUFFICIENT_FUNDS`, `PROVIDER_REJECTED` (+ `QUOTE_FUNDING_MISMATCH`, `CARD_SOURCE_REQUIRED`, `CARD_CONSENT_REQUIRED`, `CARD_CONSENT_UNAVAILABLE`, `CARD_MISMATCH`). Note : plusieurs refus de devis/consommation (expiré, déjà servi) sont levés **sans** code dédié et sortent en `REQUEST_REJECTED` (400).
- Codes propres au libre-service : `SERVICE_NOT_SELF_SERVICE`, `FUNDS_SOURCE_NOT_ALLOWED`, `QUOTE_RATE_LIMIT`, `DAILY_OPERATION_LIMIT`, `DAILY_AMOUNT_LIMIT`.

#### 7.6 Santé
- `HealthStatus` : `HEALTHY` (tout va bien), `DEGRADED` (échecs sous le seuil — reste ouvert), `DOWN` (fermé par le disjoncteur), `MAINTENANCE` (fermé volontairement).
- `HealthTargetKind` : `SELLABLE_SERVICE`, `PROVIDER`, `RESOURCE` (exclu de `/status`).
- `overall` : `operational`, `partial_outage`, `major_outage`.

#### 7.7 KYC
- `KycStatus` : `DRAFT`, `PENDING_AI`, `AI_REJECTED`, `PENDING_MERCHANT`, `APPROVED`, `EXPIRED`, `REVOKED`, `KYC_CONFLICT`.
- `KycFileKind` : `ID_DOCUMENT`, `SELFIE`, `SIGNATURE`.
- `IdentityDocumentType` : `NATIONAL_ID_CARD`, `PASSPORT`, `DRIVER_LICENSE`, `OTHER_DOCS`.
- `Gender` : `MALE`, `FEMALE`, `OTHER`. `SalaryRange` : `LESS_THAN_200K`, `FROM_200K_TO_500K`, `GREATER_THAN_500K`.
- Lookup `state` : `NEW`, `REUSABLE`, `RESUMABLE`, `IN_PROGRESS`, `BLOCKED`.

---

---

# Partie 7 — Recettes de code prêtes à l'emploi

Les exemples sont en **TypeScript** (React Native, Expo ou web). Ils se transposent directement en
Dart/Flutter ou en Kotlin. Ils utilisent `fetch` uniquement, sans dépendance.

## 7.1 Stockage des jetons

```ts
// src/api/token-store.ts
// Mobile : remplacez par expo-secure-store / react-native-keychain. Web : mémoire + cookie httpOnly côté BFF si possible.
export interface Tokens { sessionToken: string; refreshToken: string; expiresAt: number }

let current: Tokens | null = null;

export const tokenStore = {
  get: () => current,
  set: (t: { sessionToken: string; refreshToken: string; expiresIn: number }) => {
    current = { sessionToken: t.sessionToken, refreshToken: t.refreshToken, expiresAt: Date.now() + t.expiresIn * 1000 };
    // TODO : persister de façon CHIFFRÉE (SecureStore / Keychain).
  },
  clear: () => { current = null; /* TODO : effacer le stockage sécurisé */ },
};
```

## 7.2 Client HTTP avec renouvellement automatique (un seul refresh à la fois)

```ts
// src/api/client.ts
import { tokenStore } from './token-store';

const BASE = process.env.API_BASE_URL + '/api/v1';

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string,
              public details?: Record<string, string[]>, public requestId?: string) { super(message); }
}

let refreshing: Promise<boolean> | null = null;   // ← partagé : UN seul refresh en vol

async function refreshOnce(): Promise<boolean> {
  if (!refreshing) {
    refreshing = (async () => {
      const t = tokenStore.get();
      if (!t) return false;
      const res = await fetch(`${BASE}/auth/customer/refresh`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken: t.refreshToken }),
      });
      if (!res.ok) { tokenStore.clear(); return false; }
      tokenStore.set(await res.json());              // ⚠️ remplace les DEUX jetons
      return true;
    })().finally(() => { refreshing = null; });
  }
  return refreshing;
}

export async function api<T>(path: string, init: RequestInit = {}, retried = false): Promise<T> {
  const t = tokenStore.get();
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      'Accept-Language': 'fr',
      ...(t ? { Authorization: `Bearer ${t.sessionToken}` } : {}),
      ...(init.headers ?? {}),
    },
  });

  if (res.ok) return res.json() as Promise<T>;

  const body = await res.json().catch(() => ({}));
  const err = new ApiError(res.status, body.code ?? 'UNKNOWN', body.message ?? 'Erreur réseau', body.details, body.requestId);

  // Session expirée → un refresh puis un seul rejeu
  if (res.status === 401 && err.code === 'SESSION_EXPIRED' && !retried && (await refreshOnce())) {
    return api<T>(path, init, true);
  }
  // 401 « Jeton non reconnu pour cette route » = bug d'intégration, PAS une déconnexion
  if (res.status === 401 && !/non reconnu pour cette route/i.test(err.message) && path !== '/auth/customer/login/confirm') {
    tokenStore.clear();          // → l'app bascule sur l'écran de connexion
  }
  throw err;
}
```

> ⚠️ **Paiements : ne rejouez jamais automatiquement** un `POST /catalog/confirm`,
> `/external-wallets/confirm` ou `/cards/operations/.../execute` après une coupure réseau **sans la
> même `reference`**. Le rejeu automatique ci-dessus ne concerne que le 401 `SESSION_EXPIRED`,
> quand le serveur n'a **rien** exécuté.

## 7.3 Connexion complète

```ts
// src/features/auth/login.ts
import { api } from '../../api/client';
import { tokenStore } from '../../api/token-store';

const APP_ID = process.env.KONEKT_APP_ID!;   // fourni par l'équipe backend

export const normalizeCardId = (raw: string) => raw.replace(/\s+/g, '');
export const isValidCardId = (id: string) => /^\d{6,20}$/.test(id);

export async function startLogin(cardId: string, last4: string, channel?: 'SMS' | 'WHATSAPP' | 'EMAIL') {
  const cardCustomerId = normalizeCardId(cardId);
  if (!isValidCardId(cardCustomerId)) throw new Error('Chiffres uniquement (pas la lettre O).');
  return api<{ channelsUsed: string[]; maskedContacts: string[]; expiryMinutes: number }>(
    '/auth/customer/login/init',
    { method: 'POST', body: JSON.stringify({ cardCustomerId, last4Digits: last4, doubleAuthMethod: channel, appId: APP_ID }) },
  );
}

export async function confirmLogin(cardId: string, last4: string, code: string, device: { type: string; label?: string; fcmToken?: string }, referral?: string) {
  const r = await api<any>('/auth/customer/login/confirm', {
    method: 'POST',
    body: JSON.stringify({
      cardCustomerId: normalizeCardId(cardId), last4Digits: last4, appId: APP_ID, code, device,
      ...(referral ? { merchantReferralCode: referral } : {}),
    }),
  });
  tokenStore.set(r.tokens);
  return { mustCreatePin: !r.hasPin, card: r.card, holder: r.holder, isExternalCard: r.isExternalCard };
}
```

## 7.4 Validation locale du PIN

```ts
// src/features/auth/pin-rules.ts
export function pinProblem(pin: string): string | null {
  if (!/^\d{6}$/.test(pin)) return 'Six chiffres attendus.';
  if (/^(\d)\1{5}$/.test(pin)) return 'Évitez un code composé six fois du même chiffre.';
  if ('0123456789'.includes(pin) || '9876543210'.includes(pin)) return 'Évitez une suite de chiffres consécutifs.';
  return null;
}
```

## 7.5 Paiement du catalogue : devis → confirmation → suivi

```ts
// src/features/catalog/pay.ts
import { api, ApiError } from '../../api/client';

const FINAL = ['SUCCESS', 'FAILED', 'CANCELLED', 'EXPIRED', 'REVERSED', 'REFUNDED'];
const uuid = () => crypto.randomUUID();      // RN : import 'react-native-get-random-values' + uuid

export async function buyWithCard(service: string, input: object, cardCustomerId: string, askPin: (total: number) => Promise<string>) {
  // 1. Devis
  const quote = await api<any>('/catalog/quote', {
    method: 'POST',
    body: JSON.stringify({ service, funding: { source: 'CUSTOMER_CARD', card: { cardCustomerId } }, input }),
  });
  if (!quote.feasible) throw new Error(quote.reason ?? 'Opération impossible.');   // refus = 200 + feasible:false

  // 2. PIN, en affichant le TOTAL débité (montant + frais) et les avertissements du devis
  const pin = await askPin(quote.amountDebited);

  // 3. Confirmation : une référence UNIQUE par tentative, conservée pour un éventuel rejeu
  const reference = uuid();
  const res = await api<any>('/catalog/confirm', {
    method: 'POST',
    body: JSON.stringify({ quoteId: quote.quoteId, service, funding: { source: 'CUSTOMER_CARD', card: { cardCustomerId } }, reference, pin }),
  });

  // 4. completed:true = service rendu. Sinon, suivre l'opération (paiement carte : rare).
  return res.completed ? res : pollOperation(res.operationId);
}

export async function pollOperation(operationId: string, timeoutMs = 10 * 60_000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const op = await api<any>(`/cards/operations/${operationId}`);
    if (FINAL.includes(op.status ?? op.data?.status)) return op;
    await new Promise((r) => setTimeout(r, 7000));
  }
  return { status: 'PENDING', operationId };   // « en cours de traitement », NE PAS relancer
}
```

> **Paiement par portefeuille mobile** (`CUSTOMER_EXTERNAL_CHANNEL`) : la confirmation renvoie
> `completed: false` avec `awaiting` :
> - `PAYER_APPROVAL` : afficher « Validez le paiement sur votre téléphone », puis `pollOperation` ;
> - `CONFIRMATION_CODE` (B-MO) : demander le code reçu par SMS, puis
>   `POST /commerce/operations/{operationId}/funding/confirm` (3 essais), ou `/funding/cancel`.
>
> Le détail des champs est en **Partie 5 (3.6 à 3.10)**.

## 7.6 Gestion des erreurs à l'écran

```ts
// src/ui/error-message.ts
import { ApiError } from '../api/client';

export function toUserMessage(e: unknown): { text: string; fields?: Record<string, string[]> } {
  if (!(e instanceof ApiError)) return { text: 'Connexion impossible. Vérifiez votre réseau.' };
  switch (e.code) {
    case 'VALIDATION_FAILED':   return { text: e.message, fields: e.details };
    case 'RATE_LIMITED':        return { text: 'Trop de tentatives. Patientez une minute.' };
    case 'PROVIDER_UNAVAILABLE':return { text: 'Service partenaire indisponible. Réessayez dans un instant.' };
    case 'INTERNAL_ERROR':      return { text: `Erreur inattendue. Réf. : ${e.requestId ?? '—'}` };
    default:                    return { text: e.message };   // messages métier déjà rédigés pour le porteur
  }
}
```

---

# Partie 8 — Checklist avant mise en production

**Configuration**
- [ ] `API_BASE_URL` par environnement ; `KONEKT_APP_ID` = valeur serveur `BESTCASH_SECURE_CARD_APP_ID`.
- [ ] Version web : origine ajoutée à `CORS_ALLOWED_ORIGINS` côté API.
- [ ] `CARD_DISPLAY_PAGE_URL` côté API pointe vers l'API de **production** (elle visait encore dev-api) et inclut `/api/v1/card-display`.
- [ ] Aucun appel à d'anciennes routes v1 (`/secure-card/...`).

**Sécurité**
- [ ] Jetons stockés chiffrés (Keychain / Keystore). Jamais dans les journaux, jamais dans une URL.
- [ ] Un seul refresh à la fois ; les deux jetons remplacés à chaque refresh.
- [ ] PIN : jamais stocké ni journalisé ; champ masqué ; validé localement (recette 7.4).
- [ ] Captures d'écran interdites sur l'écran d'affichage de carte (`FLAG_SECURE` Android, masque iOS).
- [ ] Le jeton porteur n'est pas envoyé aux routes `/kyc/*` et `/auth/customer-otp/*`.

**Saisie**
- [ ] Identifiant de carte : clavier numérique, espaces retirés, rejet local de toute lettre.
- [ ] Montants : virgule convertie en point ; nombres, pas chaînes.
- [ ] Dates de filtre : `startDate ≤ endDate` vérifié avant l'appel.

**Paiements**
- [ ] Toujours devis → affichage du total → PIN → confirmation.
- [ ] `reference` / `requestId` = UUID v4 neuf par tentative, conservé jusqu'au résultat.
- [ ] Suivi des statuts non finaux, sans relance automatique d'un paiement.
- [ ] Services grisés selon la disponibilité (`GET /catalog/services` / `GET /status`).

**Expérience**
- [ ] `hasPin=false` → création du PIN avant l'accueil.
- [ ] `isExternalCard=true` → offre « acheter une carte » masquée.
- [ ] `isCurrent` signalé dans la liste des appareils.
- [ ] Pastille de notifications par interrogation périodique de `unread-count` (le push n'est pas encore actif).
- [ ] `requestId` affiché dans les erreurs inattendues.

---

# Partie 9 — Points ouverts côté API

Ces écarts ont été relevés en lisant le code. Ils ne bloquent pas l'intégration, à condition que
l'app applique les contournements indiqués. Ils sont à corriger côté backend.

| # | Sujet | Risque | Contournement côté app | Correction backend suggérée |
|---|---|---|---|---|
| 1 | **Idempotence partagée entre porteurs** : clé `(marchand de session, reference/requestId)` sans contrôle de l'auteur (`/catalog/confirm`, `/external-wallets/confirm`, `/cards/*/initiate`) | Collision de référence : un porteur pourrait recevoir l'opération d'un autre | UUID v4 neuf par tentative | Inclure l'auteur (`cid_…`) dans la clé |
| 2 | `GET /cards?merchantId=…` accessible au porteur | Fuite des compteurs de cartes d'un marchand | Ne jamais envoyer `merchantId` | Interdire le paramètre au porteur |
| 3 | Notifications de règlement de réclamation adressées à `cid_<kycId>` au lieu de `cid_<cardCustomerIdEnc>` | Le porteur ne les voit jamais | — | Corriger le destinataire (`admin-intervention.service.ts`) |
| 4 | Push non implémenté | Pas d'alerte en temps réel | Interroger `unread-count` | Brancher FCM |
| 5 | Plafond d'affichage de carte compté par **marchand de session** | Des porteurs bloqués par d'autres | — | Compter par carte uniquement |
| 6 | `PATCH /cards/status` sans PIN ni code SMS | Un jeton volé peut bloquer la carte (pas la vider) | Demander le PIN localement avant l'appel (confort, pas sécurité) | Exiger le PIN |
| 7 | Carte suspendue : impossible de la déclarer perdue directement | Parcours confus | Réactiver puis déclarer perdue | Autoriser `Inactive → LostOrStolen` |
| 8 | Carte pré-active : Swagger annonce le blocage possible, le code le refuse | Incohérence de doc | Masquer l'action sur une carte pré-active | Aligner la doc ou le code |
| 9 | Pas de renvoi du code SMS d'une sortie d'argent | Porteur bloqué si le SMS se perd | Annuler (`DELETE /cards/operations/:id`) puis relancer | Route de renvoi |
| 10 | PIN vérifié **avant** les autres contrôles de `/catalog/confirm` | Un devis expiré consomme un essai de PIN | Redemander un devis si plus de ~9 min se sont écoulées | Vérifier le PIN en dernier |
| 11 | Plafonds journaliers vérifiés **après** la consommation du devis | Devis perdu en cas de refus `DAILY_*` | Redemander un devis | Vérifier avant |
| 12 | Erreurs fournisseur des `/catalog/lookup/*` en 500 | Message peu clair | Afficher « Service partenaire indisponible » | Mapper en 404/503 |
| 13 | `/services/available` (dépréciée) et `GET /catalog` (déprécié) ne filtrent pas le périmètre libre-service | Services non vendables affichés | Utiliser `GET /catalog/services` | Filtrer, ou retirer |
| 14 | `payout-to-external`, `external-to-external`, `collect-from-external` acceptés par `/catalog/quote` pour un porteur | `collect-from-external` créditerait le **marchand** | Ne **jamais** les appeler via le catalogue ; utiliser `/external-wallets/*` | Retirer de la liste blanche du catalogue |
| 15 | `secretId` non exposé au porteur | Renvoi du code au bénéficiaire impossible | — | Exposer `secretId` |
| 16 | `currency` absent des réponses de confirmation | Champ `undefined` | Supposer `XOF` | Ajouter le champ |
| 17 | `GET /notifications?limit>50` → 400 | — | `limit ≤ 50` | Ramener à 50 comme annoncé |
| 18 | Noms de pays en anglais (`/geo`) | — | Traduire localement si besoin | Noms français |
| 19 | `POST /kyc/reuse` : une seule tentative par code | — | Redemander un code après échec | Aligner sur 5 essais |
| 20 | Aucun devis d'encaissement possible pour le porteur (`collect/quote` fermé) | — | Recharge de carte via `wallet-to-card` (catalogue) | — |
| 21 | Dans l'app mobile, `surface: WEB` à `cards/display/authorize` donne un 403 (pas de `Referer`) | Affichage impossible | Ne pas envoyer `surface` en natif | — |

---

*Fin du guide. Pour toute question, joignez à votre demande le `requestId` de l'erreur, la route et
l'heure de l'appel.*
