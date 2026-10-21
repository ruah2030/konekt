import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/app_prefs.dart';

enum InviteStatus { idle, saving, accepted }

class InviteState {
  const InviteState({this.status = InviteStatus.idle, this.error});
  final InviteStatus status;

  /// Message d'erreur inline (format).
  final String? error;
}

final inviteControllerProvider = NotifierProvider.autoDispose<InviteController, InviteState>(InviteController.new);

/// Code d'invitation du marchand. L'API n'a pas de route de vérification : le code est seulement
/// contrôlé localement puis enregistré ; il part dans `login/confirm` comme `merchantReferralCode`
/// (≤ 40 caractères ; un code inconnu ne bloque pas la connexion, guide §2.4).
class InviteController extends Notifier<InviteState> {
  static const minLength = 4;
  static const maxLength = 40;
  static const formatMessage = 'Code invalide : 4 à 40 lettres ou chiffres.';

  /// Majuscules, lettres, chiffres, `-` et `_`.
  static String normalize(String input) {
    final v = input.toUpperCase().replaceAll(RegExp('[^A-Z0-9_-]'), '');
    return v.length > maxLength ? v.substring(0, maxLength) : v;
  }

  static bool isValid(String code) => RegExp(r'^[A-Z0-9][A-Z0-9_-]{3,39}$').hasMatch(code);

  @override
  InviteState build() => const InviteState();

  /// Toute modification du code efface l'erreur.
  void edited() {
    if (state.status == InviteStatus.idle && state.error != null) state = const InviteState();
  }

  /// Renvoie `true` si le code est enregistré.
  Future<bool> submit(String input) async {
    if (state.status != InviteStatus.idle) return false;
    final code = normalize(input.trim());
    if (!isValid(code)) {
      state = const InviteState(error: formatMessage);
      return false;
    }
    state = const InviteState(status: InviteStatus.saving);
    final prefs = ref.read(appPrefsProvider);
    await prefs.setReferralCode(code);
    await prefs.setFirstLaunchDone();
    if (ref.mounted) state = const InviteState(status: InviteStatus.accepted);
    return true;
  }
}
