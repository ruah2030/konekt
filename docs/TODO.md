# myCard Konekt — Liste des tâches

Découpage par lots, dans l'ordre conseillé. `[x]` = implémenté et testé contre le faux backend ; reste à brancher sur l'API réelle (lot 0). Voir `ARCHITECTURE.md` pour les choix techniques. Règles métier extraites de la maquette `Card Konekt Material`.

## Lot 0 — Cadrage

- [x] Contrat d'API : guide d'intégration CardConnect v2 reçu (`docs/GUIDE-INTEGRATION-KONEKT.md`) ; l'app et le faux backend y sont alignés
- [ ] Obtenir `KONEKT_APP_ID` et les hôtes dev / staging / prod (les hôtes staging/prod dans `env/*.json` sont provisoires)
- [ ] Décider avec le produit : liste d'attente et publicités (aucune route dans l'API)
- [ ] Confirmer avec l'équipe API comment distinguer débit et crédit dans le relevé émetteur (`GET /cards/transactions`)
- [ ] Suivre les points ouverts côté API (guide Partie 9), notamment : idempotence partagée entre porteurs, `PATCH /cards/status` sans PIN, plafond d'affichage par marchand, push non implémenté
- [ ] Vérifier côté API `CARD_DISPLAY_PAGE_URL` (doit inclure `/api/v1/card-display` et viser l'environnement courant)
- [ ] Créer le projet Firebase (Android + iOS) pour les notifications push (dès que l'API les envoie)

## Lot 1 — Socle technique

- [x] `flutter create` (org `bj.bestcash`), environnements via `--dart-define-from-file` (`env/*.json`)
- [ ] Flavors natifs Android/iOS (icône et bundle id distincts par environnement)
- [x] Dépendances : riverpod 3, go_router, dio, flutter_secure_storage, shared_preferences, google_fonts, material_symbols_icons, intl, video_player, url_launcher, device_info_plus, package_info_plus
- [x] Lint strict (règles additionnelles dans `analysis_options.yaml`)
- [x] Arborescence feature-first (`app/`, `core/`, `design_system/`, `features/`)
- [x] Client dio + intercepteurs (auth/refresh, X-Request-Id, X-Device-Id, Idempotency-Key, erreurs → `ApiFailure`)
- [x] `Result<T>` + table des messages d'erreur FR
- [x] Stockage sécurisé (tokens, device id) + prefs (premier lancement, solde masqué)
- [x] Utilitaires : format FCFA fr-FR, dates relatives (« Aujourd'hui à », « Hier à »), mm:ss, validateurs (msisdn, id carte, last4, compteur)
- [x] `tickerProvider` (1 s) pour les compte-à-rebours
- [x] Localisation fr (`l10n/app_fr.arb`)
- [x] CI GitHub Actions : analyze, format, test, build

## Lot 2 — Design system

- [x] `ThemeData` M3 + `ColorScheme` Konekt + `ThemeExtension` (success, warning, teintes de catégories)
- [x] Typo Plus Jakarta Sans, formes (Stadium, champs filled rayon 18, cartes 16, dialogues 28)
- [x] Composants : bouton principal, champ texte, `PinDots`, `NumericKeypad`, `ErrorBlock` (code · Réf.), `StatusPill`, `MoneyText`, `AmountRow`, `TxTile`, `ServiceTile`, `QuickAction`, `PromoCard` (navy/gold/mint), `PromoCarousel`, `IncidentBanner`, `CountdownChip`, `ProcessingStepper`, `ConfirmDialog`, `VirtualCardView`, `EmptyState`
- [ ] Page « catalogue » de composants (debug) + tests golden

## Lot 3 — Onboarding

- [x] **Splash** : fond dégradé, logo animé (fondu + échelle), barre de progression ≈ 2,6 s, « POWERED BY BESTCASH »
- [x] Routage après splash : premier lancement → Invitation, sinon Login (ou Home si session valide)
- [x] **Invitation** : vidéo en boucle muette, champ code formaté `XXXX-XXXX` (majuscules, alphanumérique, 8 caractères), états vérification / succès (« Invitation de X acceptée ») / erreur, lien « Je n'ai pas de code »
- [x] **Obtenir une invitation** : 3 façons (proche, point marchand, liste d'attente), inscription liste d'attente (validation numéro, affichage de la position)

## Lot 4 — Authentification

- [x] **Login** : identifiant carte (6–20 chiffres, détection lettre « O »), 4 derniers chiffres, canal OTP SMS / WhatsApp (désactivable) / E-mail (SegmentedButton), bannière incident, erreurs avec Réf.
- [x] **Écran code** générique (6 cases + pavé numérique, validation auto à 6 chiffres)
- [x] Mode **OTP** : destination masquée, compte à rebours 5 min, 3 essais, renvoi (max 3/heure), retour au login
- [x] Gestion session : tokens, refresh, 401 → login, une session par carte
- [x] Redirections du router selon `AuthState`

## Lot 5 — Code secret (PIN)

- [x] Création au premier login : vérification (code SMS+e-mail) → nouveau PIN → confirmation (« Étape 1/2/3 sur 3 », pas de retour sur étape 1)
- [x] Refus PIN faible (chiffres identiques, suites croissantes/décroissantes)
- [x] Changement (PIN actuel → nouveau ≠ ancien → confirmation)
- [x] Code oublié / réinitialisation (lève le verrouillage)
- [x] PIN de paiement : 5 essais, verrouillage 15 min avec compte à rebours, lien « Code secret oublié ? »
- [x] Protection capture d'écran sur la saisie

## Lot 6 — Accueil

- [x] En-tête : avatar initiales, « Bonjour <prénom> », « Carte •••• last4 », cloche avec badge non-lus
- [x] Carte solde : montant, masquer/afficher (persisté), pastille statut carte
- [x] Comportement par statut : `Active` (normal), `Inactive` (solde « — », alerte + « Réactiver »), `PreActive` (solde 0, alerte activation chez marchand, pas de transactions), `LostOrStolen` (alerte + contacter le support) ; actions grisées (opacité 0,4) si non active
- [x] Bannière incident opérateur
- [x] Actions rapides : Envoyer, Retirer, Recharger, Ma carte (affichage sécurisé)
- [x] Carrousel promotions (rotation configurable, points, fermeture, action `url` ou `service`)
- [x] Catalogue « Payer et recharger » : Crédit téléphone, Forfait internet, Électricité, Retrait guichet, Abonnement TV (« Bientôt », indisponible)
- [x] Transactions récentes (4 dernières), « Tout voir », état vide
- [x] Pull-to-refresh (solde + transactions)
- [x] NavigationBar 4 onglets (Accueil, Historique, Ma carte, Profil)

## Lot 7 — Services & paiement

- [x] Formulaire générique piloté par configuration de service (champs, options radio, prix imposé, hint « Solde disponible »)
  - [x] Envoyer vers une carte (carte bénéficiaire ≠ sa carte, montant)
  - [x] Retirer vers Mobile Money (opérateur MTN/Moov/BestCash/Celtiis, numéro, montant, avertissement irréversible)
  - [x] Recharger ma carte (opérateur, numéro à débiter, montant — validation sur le téléphone)
  - [x] Crédit téléphone (numéro, montant, détection opérateur)
  - [x] Forfait internet (numéro, choix du forfait à prix imposé)
  - [x] Électricité prépayée (compteur, montant, canal WhatsApp/E-mail, contact)
  - [x] Retrait au guichet (montant)
- [x] Validations locales : obligatoires, montant 100 – 1 000 000, numéro, compteur ; erreurs serveur (plafond 24 h, solde insuffisant)
- [x] **Devis** : récapitulatif (montant, frais, bénéficiaire, « le bénéficiaire reçoit », total), contrôles (nom bénéficiaire, opérateur, compteur), avertissements, chip « Prix garanti mm:ss » (10 min) → « Prix expiré · Refaire le devis »
- [x] Bloquer la confirmation si aucun PIN (« Créez d'abord votre code secret »)
- [x] **Traitement** : spinner + stepper (standard : prix confirmé → autorisé → traitement émetteur ; recharge : demande envoyée → validation sur téléphone → carte créditée), « Ne relancez pas le paiement », retour accueil possible
- [x] Suivi du statut (polling/push) + notification du résultat si l'utilisateur a quitté
- [x] **Reçu** : statut (réussi / échoué / en cours), montant signé, motif d'échec, lignes, réf., informations additionnelles (code électricité, code de retrait valable 30 min), pub placement `receipt`, bouton Terminé
- [x] Rafraîchir solde, historique, notifications après succès

## Lot 8 — Historique

- [x] SliverAppBar.large + TabBar « Mouvements » / « Mes opérations »
- [x] Mouvements : relevé émetteur (dernier mois), montant signé coloré, solde après opération
- [x] Mes opérations : statut (Réussi / Échoué / En cours), tap → reçu
- [x] Pagination, pull-to-refresh, état vide, pub placement `history`

## Lot 9 — Ma carte

- [x] Visuel carte virtuelle (VISA, •••• last4, titulaire), infos (gamme, émetteur, identifiant)
- [x] Actions : voir numéro et CVV, suspendre / réactiver, déclarer perdue ou volée (définitif) — dialogues de confirmation
- [x] **Affichage sécurisé** : chargement, PAN/expiration/CVV pendant 60 s avec barre de progression, masquage à expiration, « Afficher à nouveau », protection capture

## Lot 10 — Notifications

- [x] Liste (non lu mis en avant, point orange), marquer lu au tap, « Tout marquer comme lu »
- [ ] Push FCM : enregistrement du token, réception premier plan / arrière-plan, ouverture du reçu concerné
- [x] Badge non-lus sur l'accueil

## Lot 11 — Profil & appareils

- [x] En-tête profil (initiales, nom, carte •••• last4)
- [x] Sécurité : créer/changer le PIN, code oublié, appareils connectés (nombre)
- [x] Préférence de canal : SMS / E-mail / WhatsApp / Auto
- [x] Se déconnecter ; déconnecter tous les appareils (confirmation)
- [x] **Appareils connectés** : liste (type, « actif maintenant » / « vu … »), « Cet appareil », déconnexion d'un appareil (si appareil courant → retour login)
- [x] Mention version « MYCARD KONEKT 2.0 · POWERED BY BESTCASH »

## Lot 12 — Transverse & mise en production

- [ ] Gestion hors-ligne / erreurs réseau (message + réessayer)
- [ ] Accessibilité (Semantics, tailles de police, contrastes, cibles 48 dp)
- [ ] Sécurité : FLAG_SECURE, obfuscation, certificate pinning, logs désactivés en prod
- [ ] Analytics / crash reporting (Crashlytics ou Sentry)
- [x] Icônes d'app, splash natif (`flutter_native_splash`), nom d'app
- [ ] Tests : unitaires (≥ logique métier), widgets/golden par état, intégration du parcours paiement
- [ ] Signature Android / iOS, distribution (Firebase App Distribution / TestFlight), fiches stores
