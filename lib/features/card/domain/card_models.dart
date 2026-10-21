import '../../../core/domain/card.dart';
import '../../../core/domain/json.dart';

/// Réponse de `PATCH /cards/status` (guide Partie 4 §13).
class CardStatusChangeResult {
  const CardStatusChangeResult({required this.operationId, required this.previousStatus, required this.newStatus});

  factory CardStatusChangeResult.fromJson(Json j) => CardStatusChangeResult(
    operationId: j.strOrNull('operationId') ?? '',
    previousStatus: CardStatus.fromApi(j.strOrNull('previousStatus')),
    newStatus: CardStatus.fromApi(j.strOrNull('newStatus')),
  );

  final String operationId;

  /// État constaté chez l'émetteur avant le changement.
  final CardStatus previousStatus;
  final CardStatus newStatus;
}

/// Autorisation d'affichage sécurisé (`POST /cards/display/authorize`, §14.2) :
/// adresse à usage unique, valable [expiresInSeconds] secondes.
///
/// L'app ne reçoit jamais le numéro ni le CVV : seulement cette adresse, à charger TELLE QUELLE
/// une seule fois, sans la journaliser ni la conserver.
class DisplayAuthorization {
  const DisplayAuthorization({required this.displayUrl, required this.expiresAt, required this.expiresInSeconds});

  factory DisplayAuthorization.fromJson(Json j) => DisplayAuthorization(
    displayUrl: Uri.parse(j.str('displayUrl')),
    expiresAt: j.dateOrNull('expiresAt'),
    expiresInSeconds: j.intOrNull('expiresInSeconds') ?? 60,
  );

  final Uri displayUrl;
  final DateTime? expiresAt;
  final int expiresInSeconds;

  /// Échéance locale : on se fie à la durée relative (insensible au décalage d'horloge du téléphone),
  /// bornée par [expiresAt] quand il est plus proche.
  DateTime deadlineFrom(DateTime receivedAt) {
    final relative = receivedAt.add(Duration(seconds: expiresInSeconds));
    final absolute = expiresAt;
    return absolute != null && absolute.isBefore(relative) && absolute.isAfter(receivedAt) ? absolute : relative;
  }

  /// Ne jamais afficher l'URL dans les journaux.
  @override
  String toString() => 'DisplayAuthorization(••••, expiresInSeconds: $expiresInSeconds)';
}

/// Contact du support (carte bloquée, refus d'affichage…).
const cardSupportMessage = 'Support Konekt : +229 21 00 00 00 (lun.–sam., 8h–20h)';
