import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/design_system.dart';
import '../../data/invite_link_service.dart';
import '../screens/invite_screen.dart';

/// Widget racine léger (placé dans `MaterialApp.builder`) : démarre la lecture des liens d'invitation
/// et signale discrètement un code reçu pendant que l'app est ouverte.
class InviteLinkListener extends ConsumerWidget {
  const InviteLinkListener({required this.child, super.key});

  static const savedMessage = "Code d'invitation enregistré";

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ReceivedInviteCode?>(inviteLinkProvider, (_, next) {
      // L'écran d'invitation affiche lui-même l'état « enregistré ».
      if (next == null || next.atLaunch || InviteScreen.isShowing) return;
      showToast(context, savedMessage);
    });
    return child;
  }
}
