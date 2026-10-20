import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/providers/ticker.dart';
import '../../../../core/utils/countdown.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../domain/sensitive_card_data.dart';
import '../providers/secure_display_controller.dart';
import '../widgets/virtual_card_view.dart';

/// « Données de ma carte » : PAN / expiration / CVV pendant 60 s, capture d'écran interdite.
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
    try {
      if (on) {
        await ScreenProtector.preventScreenshotOn();
      } else {
        await ScreenProtector.preventScreenshotOff();
      }
    } catch (_) {
      // Plugin indisponible (tests, web) : on continue sans protection native.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(secureDisplayProvider);
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
          onPressed: () => context.go(Routes.card),
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
            switch (state) {
              SecureDisplayLoading() => const _Loading(),
              SecureDisplayShown(:final data) => _Shown(data: data),
              SecureDisplayExpired() => _Expired(onRetry: () => ref.read(secureDisplayProvider.notifier).open()),
              SecureDisplayError(:final failure) => _Failure(
                failure: failure,
                onRetry: () => ref.read(secureDisplayProvider.notifier).open(),
              ),
            },
          ],
        ),
      ),
    );
  }
}

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
          style: TextStyle(color: Color(0xFFB8BCE8), fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _Shown extends ConsumerWidget {
  const _Shown({required this.data});
  final SensitiveCardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final left = data.expiresAt.difference(now);
    final total = SensitiveCardData.validity.inMilliseconds;
    final progress = (left.inMilliseconds / total).clamp(0.0, 1.0);
    final holder = ref.watch(cardProvider).value?.holderName ?? '';
    const label = TextStyle(fontSize: 12, color: Color(0xFFB8BCE8), fontWeight: FontWeight.w600);

    return Column(
      key: const Key('display-shown'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: kCardGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Numéro de carte', style: label),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  data.pan,
                  key: const Key('display-pan'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Expire fin', style: label),
                      const SizedBox(height: 5),
                      Text(
                        data.expiry,
                        key: const Key('display-expiry'),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(width: 44),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CVV', style: label),
                      const SizedBox(height: 5),
                      Text(
                        data.cvv,
                        key: const Key('display-cvv'),
                        style: const TextStyle(color: KColors.navIndicator, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
              if (holder.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  holder.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFD7D9F5),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ],
          ),
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
          style: TextStyle(fontSize: 13, color: Color(0xFFB8BCE8), height: 1.5),
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
  const _Failure({required this.failure, required this.onRetry});
  final ApiFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ErrorBlock(failure),
      // Carte non active : réessayer ne changerait rien.
      if (failure.code != ErrorCodes.forbidden) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('display-retry'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: onRetry,
            icon: const Icon(Symbols.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ),
      ],
    ],
  );
}
