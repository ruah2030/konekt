import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/security/screen_security.dart';
import '../../../../core/providers/ticker.dart';
import '../../../../core/utils/countdown.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../domain/card_models.dart';
import '../providers/secure_display_controller.dart';

/// « Données de ma carte » (guide Partie 4 §14) : l'autorisation n'est demandée qu'au tap sur « Afficher »,
/// la page sécurisée de l'émetteur est chargée une seule fois puis détruite à l'expiration ou à la fermeture.
/// Captures d'écran interdites (FLAG_SECURE / masquage iOS).
class SecureDisplayScreen extends ConsumerStatefulWidget {
  const SecureDisplayScreen({super.key});

  @override
  ConsumerState<SecureDisplayScreen> createState() => _SecureDisplayScreenState();
}

class _SecureDisplayScreenState extends ConsumerState<SecureDisplayScreen> {
  static const _background = Color(0xFF0B0838);

  @override
  void initState() {
    super.initState();
    _protect(on: true);
  }

  @override
  void dispose() {
    _protect(on: false);
    super.dispose();
  }

  Future<void> _protect({required bool on}) async {
    await ScreenSecurity.set(on: on);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(secureDisplayProvider);
    final status = ref.watch(cardStatusProvider);
    final notifier = ref.read(secureDisplayProvider.notifier);
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          key: const Key('display-close'),
          tooltip: 'Fermer',
          icon: const Icon(Symbols.close_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.card),
        ),
        title: const Text(
          'Données de ma carte',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const Align(alignment: Alignment.centerLeft, child: _IssuerChip()),
            const SizedBox(height: 20),
            if (status != null && status.isTerminal)
              _Blocked(message: status.blockedMessage)
            else
              switch (state) {
                SecureDisplayIdle() => _Intro(onShow: notifier.authorize),
                SecureDisplayLoading() => const _Loading(),
                SecureDisplayShown() => _Shown(state: state),
                SecureDisplayExpired() => _Expired(onRetry: notifier.authorize),
                SecureDisplayError() => _Failure(state: state, onRetry: notifier.authorize),
              },
          ],
        ),
      ),
    );
  }
}

const _muted = Color(0xFFB8BCE8);

class _IssuerChip extends StatelessWidget {
  const _IssuerChip();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('display-issuer-chip'),
    height: 32,
    padding: const EdgeInsets.only(left: 8, right: 12),
    decoration: BoxDecoration(
      color: KColors.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: KColors.outlineVariant),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Symbols.verified_user_rounded, size: 18, color: KColors.success, fill: 1),
        SizedBox(width: 6),
        Text(
          "Affichage sécurisé de l'émetteur",
          style: TextStyle(fontSize: 12.5, color: Color(0xFF334155), fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onShow});
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('display-intro'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Symbols.credit_card_rounded, size: 48, color: KColors.secondary),
      const SizedBox(height: 16),
      const Text(
        'Votre numéro de carte, sa date d’expiration et son CVV s’affichent pendant une minute, '
        'directement depuis le coffre sécurisé de l’émetteur.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: _muted, height: 1.5),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        key: const Key('display-show'),
        style: FilledButton.styleFrom(
          backgroundColor: KColors.secondary,
          foregroundColor: KColors.primary,
          minimumSize: const Size.fromHeight(48),
        ),
        onPressed: onShow,
        icon: const Icon(Symbols.visibility_rounded),
        label: const Text('Afficher'),
      ),
      const SizedBox(height: 16),
      const Text(
        "Ne faites pas de capture d'écran et ne communiquez jamais votre CVV.",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: _muted, height: 1.5),
      ),
    ],
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    key: Key('display-loading'),
    padding: EdgeInsets.symmetric(vertical: 60),
    child: Column(
      children: [
        CircularProgressIndicator(color: KColors.secondary),
        SizedBox(height: 16),
        Text(
          'Ouverture sécurisée…',
          style: TextStyle(color: _muted, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _Shown extends ConsumerWidget {
  const _Shown({required this.state});
  final SecureDisplayShown state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final left = state.deadline.difference(now);
    final total = state.authorization.expiresInSeconds * 1000;
    final progress = total <= 0 ? 0.0 : (left.inMilliseconds / total).clamp(0.0, 1.0);
    final viewBuilder = ref.watch(cardDisplayViewBuilderProvider);

    return Column(
      key: const Key('display-shown'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Clé par autorisation : une nouvelle autorisation crée une vue neuve, jamais un rechargement.
        KeyedSubtree(
          key: ValueKey('display-view-${state.generation}'),
          child: viewBuilder(context, state.authorization.displayUrl),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  key: const Key('display-progress'),
                  value: progress,
                  minHeight: 4,
                  color: KColors.warning,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              mmss(left),
              key: const Key('display-countdown'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          "Lien à usage unique, valable une minute. Ne faites pas de capture d'écran et ne communiquez jamais "
          'votre CVV.',
          style: TextStyle(fontSize: 13, color: _muted, height: 1.5),
        ),
      ],
    );
  }
}

class _Expired extends StatelessWidget {
  const _Expired({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('display-expired'),
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Affichage expiré', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const Text(
            'Pour votre sécurité, les données ont été masquées.',
            style: TextStyle(fontSize: 14, color: KColors.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('display-again'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: onRetry,
              child: const Text('Afficher à nouveau'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.state, required this.onRetry});
  final SecureDisplayError state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ErrorBlock(state.failure),
      const SizedBox(height: 12),
      if (state.canRetry)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('display-retry'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: onRetry,
            icon: const Icon(Symbols.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        )
      else ...[
        // Refus métier (plafond du jour, volume inhabituel, carte bloquée) : bouton désactivé.
        const FilledButton(key: Key('display-show-disabled'), onPressed: null, child: Text('Afficher')),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('display-support'),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: () => showToast(context, cardSupportMessage),
          child: const Text('Contacter le support'),
        ),
      ],
    ],
  );
}

class _Blocked extends StatelessWidget {
  const _Blocked({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('display-blocked'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ErrorBlock(ApiFailure.local(ErrorCodes.forbidden, message)),
      const SizedBox(height: 12),
      TextButton(
        key: const Key('display-support'),
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        onPressed: () => showToast(context, cardSupportMessage),
        child: const Text('Contacter le support'),
      ),
    ],
  );
}
