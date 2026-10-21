import '../fake_api.dart';
import 'account_handlers.dart';

/// Plafond d'affichages par carte sur 24 h glissantes (`CARD_DISPLAY_MAX_PER_CARD_PER_DAY`, défaut 20).
const fakeDisplayMaxPerCardPerDay = 20;

/// Hôte fictif des pages d'affichage sécurisé du faux backend : l'app y substitue un rendu de démonstration.
const fakeCardDisplayHost = 'fake.konekt.local';

/// Statut de carte (guide Partie 4 §13) et affichage sécurisé (§14).
void registerCardHandlers(FakeApi api) {
  final db = api.db;

  // Jetons d'affichage émis, par carte (24 h glissantes).
  final displayIssued = <String, List<DateTime>>{};

  // ---- §13 PATCH /cards/status ----
  api.on(
    'PATCH',
    '/cards/status',
    (r) {
      final b = r.body;
      final errors = <String, List<String>>{};
      final rawId = b['cardCustomerId'];
      if (rawId is! String) errors['cardCustomerId'] = ['cardCustomerId must be a string'];
      final newStatus = b['newStatus'];
      if (newStatus is! String || !const {'Active', 'Inactive', 'LostOrStolen'}.contains(newStatus)) {
        errors['newStatus'] = ['newStatus must be one of the following values: Active, Inactive, LostOrStolen'];
      }
      final ack = b['acknowledgeIrreversible'];
      if (ack != null && ack is! bool) {
        errors['acknowledgeIrreversible'] = ['acknowledgeIrreversible must be a boolean value'];
      }
      for (final k in const ['cardTierSlug', 'phoneCountryCode', 'phoneNumber']) {
        if (b[k] != null && b[k] is! String) errors[k] = ['$k must be a string'];
      }
      if (errors.isNotEmpty) return FakeResponse.validation(errors);
      final target = newStatus! as String;

      final refused = assertSessionCard(db, rawId as String?);
      if (refused != null) return refused;
      // Carte connue en base comme perdue/désactivée : refus avant tout appel émetteur.
      if (db.cardStatus == 'LostOrStolen' || db.cardStatus == 'Deactivated') return cardStateRefusal(db)!;

      final transition = _transitionRefusal(db.cardStatus, target);
      if (transition != null) return transition;
      if (target == 'LostOrStolen' && ack != true) {
        return FakeResponse.error(
          400,
          'REQUEST_REJECTED',
          'Cette déclaration est DÉFINITIVE : la carte ne pourra plus jamais être remise en service, même retrouvée. '
              'Confirmez en posant « acknowledgeIrreversible » après avoir averti le porteur.',
        );
      }

      final previous = db.cardStatus;
      final op = db.newOperation(
        type: 'CARD_OPERATION',
        status: 'SUCCESS',
        serviceSlug: 'merchant:card:update-status',
        serviceLabel: switch (target) {
          'Inactive' => 'Suspension de la carte',
          'Active' => 'Réactivation de la carte',
          _ => 'Déclaration de perte ou de vol',
        },
        amount: 0,
      );
      db.operations.insert(0, op);
      db.cardStatus = target;
      if (target == 'LostOrStolen') {
        db.addNotification(
          'Carte déclarée perdue ou volée',
          'Votre carte •••• ${db.last4} est bloquée définitivement. Vos fonds ne sont pas perdus : '
              'contactez le support pour les transférer sur une nouvelle carte.',
          kind: 'SECURITY',
          linkType: 'operation',
          linkId: op['id'] as String,
        );
      }
      return FakeResponse.ok({
        'success': true,
        'operationId': op['id'],
        'previousStatus': previous,
        'newStatus': target,
      });
    },
    fields: const {
      'cardCustomerId',
      'cardTierSlug',
      'newStatus',
      'phoneCountryCode',
      'phoneNumber',
      'acknowledgeIrreversible',
    },
  );

  // ---- §14.2 POST /cards/display/authorize ----
  api.on('POST', '/cards/display/authorize', (r) {
    final b = r.body;
    final id = b['cardCustomerId'];
    if (id is! String || id.isEmpty) {
      return FakeResponse.validation({
        'cardCustomerId': ['cardCustomerId should not be empty'],
      });
    }
    final surface = b['surface'];
    if (surface != null) {
      final kind = surface is Map ? surface['kind'] : null;
      if (kind != 'WEB' && kind != 'NATIVE_APP') {
        return FakeResponse.validation({
          'surface.kind': ['kind must be one of the following values: WEB, NATIVE_APP'],
        });
      }
    }
    // Pas de normalisation : comparaison exacte avec l'identifiant de session.
    if (id != db.sessionCardId) {
      return FakeResponse.error(403, 'FORBIDDEN', 'Vous ne pouvez afficher que votre propre carte.');
    }
    final now = db.now();
    final issued = displayIssued.putIfAbsent(id, () => [])
      ..removeWhere((t) => now.difference(t) >= const Duration(hours: 24));
    if (issued.length >= fakeDisplayMaxPerCardPerDay) {
      return FakeResponse.error(
        403,
        'FORBIDDEN',
        'Cette carte a été consultée trop de fois aujourd’hui. Réessayez demain.',
      );
    }
    if (db.cardStatus == 'LostOrStolen' || db.cardStatus == 'Deactivated') {
      return FakeResponse.error(
        403,
        'FORBIDDEN',
        'Les données de cette carte ne peuvent plus être affichées : elle a été bloquée.',
      );
    }
    issued.add(now);
    final expiresAt = now.add(const Duration(seconds: 60));
    return FakeResponse.ok({
      'success': true,
      'displayUrl': 'https://$fakeCardDisplayHost/api/v1/card-display?t=${db.id('', 43)}',
      'expiresAt': db.iso(expiresAt),
      'expiresInSeconds': 60,
    });
  }, fields: const {'cardCustomerId', 'cardTierSlug', 'surface'});
}

/// Matrice `ALLOWED` (guide §13) : `null` si la transition est acceptée.
FakeResponse? _transitionRefusal(String current, String target) {
  FakeResponse reject(String m) => FakeResponse.error(400, 'REQUEST_REJECTED', m);
  if (current == target) return reject('Cette carte est déjà dans l’état demandé.');
  return switch (current) {
    'Active' => null,
    'Inactive' when target == 'Active' => null,
    'Inactive' => reject(
      'Cette carte est suspendue. Réactivez-la d’abord : tant qu’elle est suspendue, aucune autre opération '
      'n’est possible.',
    ),
    'PreActive' => reject(
      'Cette carte n’a pas encore été activée. Rechargez-la une première fois pour commencer à l’utiliser.',
    ),
    'LostOrStolen' => reject(
      'Une carte déclarée perdue ou volée ne peut plus être remise en service, même retrouvée. '
      'Contactez le support : vos fonds peuvent être transférés sur une nouvelle carte.',
    ),
    _ => reject('Cette carte a été désactivée. Seul le support peut intervenir.'),
  };
}

/// Vrai si [url] est une page d'affichage fictive du faux backend (aucune page VGS réelle derrière).
bool isFakeCardDisplayUrl(Uri url) => url.scheme == 'data' || url.host == fakeCardDisplayHost;
