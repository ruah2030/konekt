import '../../../domain/card.dart';
import '../fake_api.dart';

/// Statut de la carte : suspension, réactivation, perte/vol, affichage sécurisé PAN/CVV.
void registerCardHandlers(FakeApi api) {
  final db = api.db;

  FakeResponse reject(String message) => FakeResponse.error(422, 'REQUEST_REJECTED', message);

  api.on('POST', '/v1/card/suspend', (_) {
    switch (db.cardStatus) {
      case 'ACTIVE':
        db.cardStatus = 'INACTIVE';
        return FakeResponse.ok(db.cardJson());
      case 'INACTIVE':
        return reject('Votre carte est déjà suspendue.');
      case 'PRE_ACTIVE':
        return reject("Votre carte n'est pas encore activée : elle ne peut pas être suspendue.");
      default:
        return reject('Carte déclarée perdue ou volée : ce blocage est définitif.');
    }
  });

  api.on('POST', '/v1/card/reactivate', (_) {
    switch (db.cardStatus) {
      case 'INACTIVE':
        db.cardStatus = 'ACTIVE';
        return FakeResponse.ok(db.cardJson());
      case 'ACTIVE':
        return reject('Votre carte est déjà active.');
      case 'PRE_ACTIVE':
        return reject("Votre carte n'est pas encore activée. Rendez-vous chez votre marchand pour l'activer.");
      default:
        return reject('Carte déclarée perdue ou volée : elle ne peut pas être réactivée. Contactez le support.');
    }
  });

  api.on('POST', '/v1/card/lost', (_) {
    if (db.cardStatus == 'LOST_OR_STOLEN') return reject('Votre carte est déjà déclarée perdue ou volée.');
    db
      ..cardStatus = 'LOST_OR_STOLEN'
      ..addNotification(
        'Carte bloquée',
        'Votre carte •••• ${db.last4} a été déclarée perdue ou volée. Le support peut transférer vos fonds.',
      );
    return FakeResponse.ok(db.cardJson());
  });

  api.on('POST', '/v1/card/sensitive-display', (_) {
    final status = CardStatus.fromApi(db.cardStatus);
    final message = status.isActive ? null : status.blockedMessage;
    if (message != null) return FakeResponse.error(403, 'FORBIDDEN', message);
    return FakeResponse.ok({
      'pan': '4532 1180 7741 ${db.last4}',
      'expiry': '04/27',
      'cvv': '318',
      'expiresAt': db.now().add(const Duration(seconds: 60)).toIso8601String(),
    });
  });
}
