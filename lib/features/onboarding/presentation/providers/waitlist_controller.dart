import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../core/utils/validators.dart';
import '../../data/waitlist_repository.dart';

class WaitlistState {
  const WaitlistState({this.busy = false, this.position, this.error});
  final bool busy;

  /// Position sur la liste une fois inscrit.
  final int? position;
  final ApiFailure? error;
}

final waitlistControllerProvider = NotifierProvider.autoDispose<WaitlistController, WaitlistState>(
  WaitlistController.new,
);

class WaitlistController extends Notifier<WaitlistState> {
  static const invalidPhoneMessage = 'Numéro de téléphone invalide.';

  @override
  WaitlistState build() => const WaitlistState();

  /// Renvoie `false` si le numéro est invalide localement (message affiché en toast).
  Future<bool> join(String msisdn) async {
    if (state.busy) return true;
    if (!Validators.isMsisdn(msisdn)) return false;
    state = const WaitlistState(busy: true);
    try {
      final position = await ref.read(waitlistRepositoryProvider).join(msisdn.replaceAll(RegExp(r'[\s-]'), ''));
      if (ref.mounted) state = WaitlistState(position: position);
    } catch (e) {
      if (ref.mounted) state = WaitlistState(error: ApiFailure.from(e));
    }
    return true;
  }
}
