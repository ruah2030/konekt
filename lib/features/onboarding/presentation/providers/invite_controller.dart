import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../../auth/data/auth_repository.dart';

enum InviteStatus { idle, checking, accepted }

class InviteState {
  const InviteState({this.status = InviteStatus.idle, this.error, this.inviterName});
  final InviteStatus status;

  /// Message d'erreur inline.
  final String? error;
  final String? inviterName;
}

final inviteControllerProvider = NotifierProvider.autoDispose<InviteController, InviteState>(InviteController.new);

/// Vérification du code d'invitation : `idle → checking → accepted | idle(erreur)`.
class InviteController extends Notifier<InviteState> {
  static const lengthMessage = 'Le code compte 8 caractères.';

  @override
  InviteState build() => const InviteState();

  /// Toute modification du code efface l'erreur.
  void edited() {
    if (state.status == InviteStatus.idle && state.error != null) state = const InviteState();
  }

  /// Renvoie `true` si l'invitation est acceptée.
  Future<bool> submit(String formatted) async {
    if (state.status != InviteStatus.idle) return false;
    final raw = formatted.replaceAll('-', '');
    if (raw.length < 8) {
      state = const InviteState(error: lengthMessage);
      return false;
    }
    state = const InviteState(status: InviteStatus.checking);
    try {
      final name = await ref.read(authRepositoryProvider).verifyInvitation(raw);
      if (!ref.mounted) return false;
      state = InviteState(status: InviteStatus.accepted, inviterName: name);
      return true;
    } catch (e) {
      if (ref.mounted) state = InviteState(error: ApiFailure.from(e).message);
      return false;
    }
  }
}
