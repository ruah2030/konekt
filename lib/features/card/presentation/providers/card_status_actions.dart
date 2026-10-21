import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/card.dart';
import '../../../account/presentation/account_providers.dart';
import '../../data/card_repository.dart';
import '../../domain/card_models.dart';

/// Changements d'état de la carte de session (guide Partie 4 §13), avec mise à jour de l'état local.
final cardStatusActionsProvider = Provider<CardStatusActions>(CardStatusActions.new);

class CardStatusActions {
  CardStatusActions(this._ref);
  final Ref _ref;

  CardRepository get _repo => _ref.read(cardRepositoryProvider);

  /// Active → Inactive (réversible).
  Future<CardStatusChangeResult> suspend() => _change(CardStatus.inactive);

  /// Inactive → Active.
  Future<CardStatusChangeResult> reactivate() => _change(CardStatus.active);

  /// → LostOrStolen (définitif), à appeler APRÈS l'avertissement explicite.
  ///
  /// Une carte suspendue ne peut pas être déclarée perdue directement (écart 2, point ouvert n°7) :
  /// elle est d'abord réactivée, puis déclarée perdue (deux appels). Si le second échoue, la carte
  /// reste active et l'erreur est relancée.
  Future<CardStatusChangeResult> declareLost({required CardStatus current}) async {
    if (current == CardStatus.inactive) await _change(CardStatus.active);
    return _change(CardStatus.lostOrStolen, acknowledgeIrreversible: true);
  }

  Future<CardStatusChangeResult> _change(CardStatus target, {bool acknowledgeIrreversible = false}) async {
    final id = requireCardId(_ref);
    final result = await _repo.changeStatus(id, target, acknowledgeIrreversible: acknowledgeIrreversible);
    _ref.read(cardProvider.notifier).setStatus(result.newStatus);
    _ref
      ..invalidate(balanceProvider)
      ..invalidate(recentTransactionsProvider)
      ..invalidate(notificationsProvider)
      ..invalidate(unreadCountProvider);
    return result;
  }
}
