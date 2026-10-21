import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/card.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/card_models.dart';
import '../providers/card_status_actions.dart';
import '../widgets/virtual_card_view.dart';

/// Changement de statut demandé depuis « Ma carte ».
enum CardStatusChange {
  suspend(
    title: 'Suspendre ma carte ?',
    body: "Plus aucun paiement ni retrait jusqu'à la réactivation. Vous pourrez la réactiver à tout moment.",
    cta: 'Suspendre',
    icon: Symbols.pause_circle_rounded,
    color: KColors.primary,
    message: 'Carte suspendue.',
  ),
  reactivate(
    title: 'Réactiver ma carte ?',
    body: 'Votre carte pourra de nouveau payer et recevoir de l’argent.',
    cta: 'Réactiver',
    icon: Symbols.play_circle_rounded,
    color: KColors.successDark,
    message: 'Carte réactivée.',
  ),
  lost(
    title: 'Déclarer perdue ou volée ?',
    body:
        'Cette déclaration est DÉFINITIVE : votre carte ne pourra plus jamais être utilisée, même si vous la '
        'retrouvez.\n\nVos fonds ne sont pas perdus : le support pourra les transférer sur une nouvelle carte.',
    cta: 'Oui, déclarer perdue',
    icon: Symbols.report_rounded,
    color: KColors.error,
    message: 'Carte déclarée perdue. Vos fonds ne sont pas perdus : contactez le support pour les récupérer.',
  );

  const CardStatusChange({
    required this.title,
    required this.body,
    required this.cta,
    required this.icon,
    required this.color,
    required this.message,
  });

  final String title;
  final String body;
  final String cta;
  final IconData icon;
  final Color color;
  final String message;
}

/// Texte ajouté à l'avertissement quand la carte est suspendue : l'API impose deux appels
/// (réactivation, puis déclaration de perte — point ouvert n°7).
const lostFromSuspendedNotice =
    'Votre carte est suspendue : elle sera d’abord réactivée un court instant, puis aussitôt déclarée perdue.';

/// Onglet « Ma carte » : visuel, infos, actions de statut (guide §13) et accès à l'affichage sécurisé (§14).
class CardScreen extends ConsumerStatefulWidget {
  const CardScreen({super.key});

  @override
  ConsumerState<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends ConsumerState<CardScreen> {
  bool _busy = false;

  /// L'API n'exige ni PIN ni code pour changer l'état (point ouvert n°6) : confirmation explicite obligatoire.
  Future<void> _changeStatus(CardStatusChange change, CardStatus current) async {
    if (_busy) return;
    final twoSteps = change == CardStatusChange.lost && current == CardStatus.inactive;
    final ok = await showConfirmDialog(
      context,
      title: change.title,
      body: twoSteps ? '${change.body}\n\n$lostFromSuspendedNotice' : change.body,
      confirmLabel: change.cta,
      icon: change.icon,
      color: change.color,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final actions = ref.read(cardStatusActionsProvider);
    try {
      await switch (change) {
        CardStatusChange.suspend => actions.suspend(),
        CardStatusChange.reactivate => actions.reactivate(),
        CardStatusChange.lost => actions.declareLost(current: current),
      };
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
    final session = ref.watch(cardSessionProvider);
    // PreActive et Inactive restent affichables ; LostOrStolen / Deactivated non (§14.2).
    final canDisplay = !status.isTerminal;

    return [
      VirtualCardView(card: card),
      const SizedBox(height: 20),
      InfoRowsCard([
        InfoRow('Gamme', card.product, key: const Key('card-info-product')),
        InfoRow('Émetteur', card.issuer, key: const Key('card-info-issuer')),
        if (card.holderName.isNotEmpty) InfoRow('Titulaire', card.holderName, key: const Key('card-info-holder')),
        InfoRow('Statut', status.label, key: const Key('card-info-status')),
        InfoRow('Identifiant', session?.cardCustomerId ?? card.cardCustomerId, key: const Key('card-info-id')),
      ]),
      const SizedBox(height: 20),
      if (status.isTerminal) ...[
        _StatusNotice(
          key: const Key('card-terminal-notice'),
          message: status.blockedMessage,
          action: TextButton(
            key: const Key('card-support'),
            onPressed: () => showToast(context, cardSupportMessage),
            child: const Text('Contacter le support'),
          ),
        ),
        const SizedBox(height: 20),
      ],
      if (status == CardStatus.preActive) ...[
        _StatusNotice(key: const Key('card-preactive-notice'), message: status.blockedMessage),
        const SizedBox(height: 20),
      ],
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
                enabled: canDisplay,
                onTap: canDisplay
                    ? () => context.push(Routes.cardDisplay)
                    : () => showToast(context, status.blockedMessage),
              ),
              // Carte pré-active : l'API refuse tout changement d'état (point ouvert n°8) → actions masquées.
              // Carte perdue/désactivée : plus aucune action possible.
              if (status == CardStatus.active) ...[
                const Divider(height: 1, color: KColors.divider),
                _ActionTile(
                  key: const Key('card-action-suspend'),
                  label: 'Suspendre ma carte',
                  sub: 'Blocage temporaire, réversible',
                  icon: Symbols.pause_circle_rounded,
                  tint: KColors.secondaryContainer,
                  color: KColors.primary,
                  enabled: !_busy,
                  onTap: () => _changeStatus(CardStatusChange.suspend, status),
                ),
              ],
              if (status == CardStatus.inactive) ...[
                const Divider(height: 1, color: KColors.divider),
                _ActionTile(
                  key: const Key('card-action-reactivate'),
                  label: 'Réactiver ma carte',
                  sub: 'Elle pourra de nouveau payer',
                  icon: Symbols.play_circle_rounded,
                  tint: KColors.successContainer,
                  color: KColors.success,
                  enabled: !_busy,
                  onTap: () => _changeStatus(CardStatusChange.reactivate, status),
                ),
              ],
              if (status == CardStatus.active || status == CardStatus.inactive) ...[
                const Divider(height: 1, color: KColors.divider),
                _ActionTile(
                  key: const Key('card-action-lost'),
                  label: 'Déclarer perdue ou volée',
                  sub: 'Blocage définitif',
                  icon: Symbols.report_rounded,
                  tint: KColors.errorContainer,
                  color: KColors.error,
                  enabled: !_busy,
                  onTap: () => _changeStatus(CardStatusChange.lost, status),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }
}

class _StatusNotice extends StatelessWidget {
  const _StatusNotice({required this.message, this.action, super.key});
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Symbols.info_rounded, size: 22, color: KColors.warning),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: const TextStyle(fontSize: 14, height: 1.5))),
            ],
          ),
          if (action != null) Align(alignment: Alignment.centerRight, child: action),
          if (action == null) const SizedBox(height: 8),
        ],
      ),
    ),
  );
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
