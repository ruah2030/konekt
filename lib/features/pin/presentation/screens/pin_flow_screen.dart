import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../../app/router/routes.dart';
import '../../../../design_system/design_system.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/pin_flow.dart';
import '../providers/pin_flow_controller.dart';
import '../providers/pin_status_provider.dart';
import '../widgets/code_entry_view.dart';

/// Création (premier login), changement ou réinitialisation du code secret.
class PinFlowScreen extends ConsumerStatefulWidget {
  const PinFlowScreen({required this.flow, super.key});
  final PinFlow flow;

  @override
  ConsumerState<PinFlowScreen> createState() => _PinFlowScreenState();
}

class _PinFlowScreenState extends ConsumerState<PinFlowScreen> {
  @override
  void initState() {
    super.initState();
    _protect(true);
  }

  @override
  void dispose() {
    _protect(false);
    super.dispose();
  }

  static Future<void> _protect(bool on) async {
    try {
      on ? await ScreenProtector.preventScreenshotOn() : await ScreenProtector.preventScreenshotOff();
    } catch (_) {
      // Plugin indisponible (tests, web) : sans conséquence.
    }
  }

  PinFlowController get _controller => ref.read(pinFlowControllerProvider(widget.flow).notifier);

  void _onDone() {
    switch (widget.flow) {
      case PinFlow.setup:
        showToast(context, 'Code secret créé. Il confirmera chacun de vos paiements.');
        // Le routeur redirige vers l'accueil.
        ref.read(authControllerProvider.notifier).pinCreated();
      case PinFlow.change:
        showToast(context, 'Code secret modifié.');
        ref.invalidate(pinStatusProvider);
        context.go(Routes.profile);
      case PinFlow.reset:
        showToast(context, 'Code secret réinitialisé.');
        ref.invalidate(pinStatusProvider);
        context.go(Routes.profile);
    }
  }

  void _back() {
    if (_controller.back()) return;
    if (widget.flow == PinFlow.setup) return;
    context.canPop() ? context.pop() : context.go(Routes.profile);
  }

  @override
  Widget build(BuildContext context) {
    final provider = pinFlowControllerProvider(widget.flow);
    ref.listen(provider.select((s) => s.isDone), (prev, done) {
      if (done && prev != true) _onDone();
    });
    final s = ref.watch(provider);
    final setup = widget.flow == PinFlow.setup;
    final (title, subtitle, step) = switch (s.step) {
      PinVerifyStep() => (
        widget.flow == PinFlow.reset ? 'Code secret oublié' : 'Sécurisons votre compte',
        'Saisissez le code de vérification envoyé par SMS et par e-mail.',
        setup ? 'Étape 1 sur 3' : null,
      ),
      PinOldStep() => ('Code secret actuel', 'Saisissez votre code secret actuel pour continuer.', null),
      PinNewStep() || PinDoneStep() => (
        setup ? 'Choisissez votre code secret' : 'Nouveau code secret',
        '6 chiffres pour confirmer chacun de vos paiements. Évitez 123456 et les chiffres répétés.',
        setup ? 'Étape 2 sur 3' : null,
      ),
      PinConfirmStep() => (
        'Confirmez votre code secret',
        'Saisissez-le une seconde fois.',
        setup ? 'Étape 3 sur 3' : null,
      ),
    };
    final showBack = s.step is PinConfirmStep || !setup;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: KColors.surface,
        body: SafeArea(
          child: CodeEntryView(
            key: ValueKey(s.step.runtimeType),
            title: title,
            subtitle: subtitle,
            step: step,
            value: s.code,
            obscure: s.obscure,
            error: s.error,
            busy: s.busy,
            onBack: showBack ? _back : null,
            onChanged: _controller.setCode,
            onCompleted: _controller.submit,
          ),
        ),
      ),
    );
  }
}
