import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/card.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../data/card_repository.dart';
import '../widgets/virtual_card_view.dart';

/// Changement de statut demandé depuis « Ma carte » (textes de la maquette, askStatus).
enum CardStatusChange {
  suspend(
    title: 'Suspendre ma carte ?',
    body: "Plus aucun paiement ni retrait jusqu'à la réactivation. Vous pourrez la réactiver à tout moment.",
    cta: 'Suspendre',
    icon: Symbols.pause_circle_rounded,
    color: KColors.primary,
    to: CardStatus.inactive,
    message: 'Carte suspendue.',
  ),
  reactivate(
    title: 'Réactiver ma carte ?',
    body: 'Votre carte pourra de nouveau payer et recevoir de l’argent.',
    cta: 'Réactiver',
    icon: Symbols.play_circle_rounded,
    color: KColors.successDark,
    to: CardStatus.active,
    message: 'Carte réactivée.',
  ),
  lost(
    title: 'Déclarer perdue ou volée ?',
    body: 'Ce blocage est définitif. Vos fonds ne sont pas perdus : le support pourra les transférer sur une nouvelle carte.',
    cta: 'Déclarer perdue ou volée',
    icon: Symbols.report_rounded,
    color: KColors.error,
    to: CardStatus.lostOrStolen,
    message: 'Carte bloquée. Une alerte a été envoyée sur tous vos canaux.',
  );

  const CardStatusChange({
    required this.title,
    required this.body,
    required this.cta,
    required this.icon,
    required this.color,
    required this.to,
    required this.message,
  });

  final String title;
  final String body;
  final String cta;
  final IconData icon;
  final Color color;
  final CardStatus to;
  final String message;
}

/// Onglet « Ma carte » : visuel, infos, actions de statut et affichage sécurisé.
class CardScreen extends ConsumerStatefulWidget {
  const CardScreen({super.key});

  @override
  ConsumerState<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends ConsumerState<CardScreen> {
  bool _busy = false;

  Future<void> _changeStatus(CardStatusChange change) async {
    if (_busy) return;
    final ok = await showConfirmDialog(
      context,
      title: change.title,
      body: change.body,
      confirmLabel: change.cta,
      icon: change.icon,
      color: change.color,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(cardRepositoryProvider);
      final card = await switch (change) {
        CardStatusChange.suspend => repo.suspend(),
        CardStatusChange.reactivate => repo.reactivate(),
        CardStatusChange.lost => repo.declareLost(),
      };
      ref.read(cardProvider.notifier).setStatus(card.status);
      refreshAccountFromWidget(ref);
      if (mounted) showToast(context, change.message);
    } catch (e) {
      if (mounted) showToast(context, ApiFailure.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardAsync = ref.watch(cardProvider);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(cardProvider.notifier).refresh(),
          child: ListView(
            key: const Key('card-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Ma carte',
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, fontSize: 32),
                ),
              ),
              const SizedBox(height: 20),
              ...switch (cardAsync) {
                AsyncData(:final value) => _content(value),
                AsyncError(:final error) when !cardAsync.isLoading => [
                  ErrorView(error: error, onRetry: () => ref.invalidate(cardProvider)),
                ],
                _ => [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(CardInfo card) {
    final status = card.status;
    final active = status.isActive;
    void blocked() => showToast(context, status.blockedMessage);

    return [
      VirtualCardView(card: card),
      const SizedBox(height: 20),
      InfoRowsCard([
        InfoRow('Gamme', card.product, key: const Key('card-info-product')),
        InfoRow('Émetteur', card.issuer, key: const Key('card-info-issuer')),
        InfoRow('Identifiant', card.id, key: const Key('card-info-id')),
      ]),
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _ActionTile(
                key: const Key('card-action-view'),
                label: 'Voir numéro et CVV',
                sub: 'Affichage sécurisé, 1 minute',
                icon: Symbols.visibility_rounded,
                tint: KColors.primaryContainer,
                color: KColors.primary,
                enabled: active,
                onTap: active ? () => context.push(Routes.cardDisplay) : blocked,
              ),
              const Divider(height: 1, color: KColors.divider),
              if (status == CardStatus.inactive)
                _ActionTile(
                  key: const Key('card-action-reactivate'),
                  label: 'Réactiver ma carte',
                  sub: 'Elle pourra de nouveau payer',
                  icon: Symbols.play_circle_rounded,
                  tint: KColors.successContainer,
                  color: KColors.success,
                  enabled: true,
                  onTap: () => _changeStatus(CardStatusChange.reactivate),
                )
              else
                _ActionTile(
                  key: const Key('card-action-suspend'),
                  label: 'Suspendre ma carte',
                  sub: 'Blocage temporaire, réversible',
                  icon: Symbols.pause_circle_rounded,
                  tint: KColors.secondaryContainer,
                  color: KColors.primary,
                  enabled: active,
                  onTap: active ? () => _changeStatus(CardStatusChange.suspend) : blocked,
                ),
              const Divider(height: 1, color: KColors.divider),
              _ActionTile(
                key: const Key('card-action-lost'),
                label: 'Déclarer perdue ou volée',
                sub: 'Blocage définitif',
                icon: Symbols.report_rounded,
                tint: KColors.errorContainer,
                color: KColors.error,
                enabled: status != CardStatus.lostOrStolen,
                onTap: status == CardStatus.lostOrStolen ? blocked : () => _changeStatus(CardStatusChange.lost),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.sub,
    required this.icon,
    required this.tint,
    required this.color,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final String sub;
  final IconData icon;
  final Color tint;
  final Color color;

  /// Indisponible : opacité 0,4 (le tap affiche la raison).
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.4,
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        label,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
      ),
      subtitle: Text(
        sub,
        style: const TextStyle(fontSize: 12, color: KColors.onSurfaceVariant, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Symbols.chevron_right_rounded, color: KColors.outline),
    ),
  );
}
