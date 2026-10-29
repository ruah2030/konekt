import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/card.dart';
import '../../../../core/domain/service_type.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../../account/presentation/widgets/activity_tiles.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../history/presentation/providers/history_providers.dart';
import '../../data/home_card_repository.dart';
import 'home_services.dart';

const supportMessage = 'Support Konekt : +229 21 00 00 00 (lun.–sam., 8h–20h)';

/// Ombre M3 « niveau 1 » teintée primaire, commune aux surfaces blanches de l'accueil.
const homeSurfaceShadow = [
  BoxShadow(color: Color(0x1A140A72), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0D140A72), blurRadius: 3, spreadRadius: 1, offset: Offset(0, 1)),
];

BoxDecoration homeSurface() =>
    BoxDecoration(color: KColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: homeSurfaceShadow);

/// Titre de section (« Payer et recharger », « Transactions récentes »).
class HomeSectionTitle extends StatelessWidget {
  const HomeSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.18, color: KColors.primary),
  );
}

/// Bannière d'incident (`GET /status`, `overall != operational`) ; aucune si l'appel échoue.
class HomeIncidents extends ConsumerWidget {
  const HomeIncidents({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(platformStatusProvider).value;
    if (status == null || !status.hasIncident) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 24), child: IncidentBanner(status.message));
  }
}

/// Alerte quand la carte n'est pas active : réactivation (suspendue), recharge (à activer)
/// ou support (perdue/volée, désactivée).
class CardStatusAlert extends ConsumerWidget {
  const CardStatusAlert({super.key});

  Future<void> _reactivate(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Réactiver ma carte ?',
      body: 'Votre carte pourra de nouveau payer et recevoir de l’argent.',
      confirmLabel: 'Réactiver',
      icon: Symbols.play_circle_rounded,
      color: KColors.successDark,
    );
    if (!ok) return;
    final cardId = ref.read(cardSessionProvider)?.cardCustomerId;
    if (cardId == null) return;
    final result = await ref.read(homeCardRepositoryProvider).reactivate(cardId);
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        ref.read(cardProvider.notifier).setStatus(CardStatus.active);
        ref
          ..invalidate(balanceProvider)
          ..invalidate(recentTransactionsProvider);
        invalidateHistory(ref);
        showToast(context, 'Carte réactivée.');
      },
      err: (f) => showToast(context, f.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(cardStatusProvider);
    if (status == null || status.isActive) return const SizedBox.shrink();
    final (label, onPressed) = switch (status) {
      CardStatus.inactive => ('Réactiver ma carte', () => _reactivate(context, ref)),
      // Une carte à activer s'active par une première recharge (seul crédit accepté).
      CardStatus.preActive => (
        'Recharger ma carte',
        () => serviceAvailable(ref, ServiceType.topup)
            ? context.push(Routes.service(ServiceType.topup))
            : openHomeService(context, ref, ServiceType.topup),
      ),
      _ => ('Contacter le support', () => showToast(context, supportMessage)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        key: const Key('card-alert'),
        padding: const EdgeInsets.all(16),
        decoration: homeSurface(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Symbols.info_rounded, size: 22, color: KColors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status.blockedMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('card-alert-cta'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                onPressed: onPressed,
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Catalogue « Payer et recharger » (grille de 3 colonnes). Les services `available: false` de
/// `GET /catalog/services` sont grisés (pas masqués) ; au tap, leur motif s'affiche.
class ServiceCatalog extends ConsumerWidget {
  const ServiceCatalog({super.key});

  static const _items = [
    (ServiceType.airtime, 'Crédit téléphone', Symbols.smartphone_rounded, 'phone'),
    (ServiceType.data, 'Forfait internet', Symbols.wifi_rounded, 'data'),
    (ServiceType.elec, 'Électricité', Symbols.bolt_rounded, 'bolt'),
    (ServiceType.elecBill, 'Facture d’électricité', Symbols.receipt_long_rounded, 'elecBill'),
    (ServiceType.cash, 'Retrait guichet', Symbols.payments_rounded, 'cash'),
    (ServiceType.tv, 'Abonnement TV', Symbols.live_tv_rounded, 'card'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(cardStatusProvider);
    final active = status == null || status.isActive;
    final rows = <List<Widget>>[];
    for (var i = 0; i < _items.length; i += 3) {
      rows.add([
        for (var j = i; j < i + 3; j++)
          Expanded(
            child: j < _items.length
                ? _CatalogTile(
                    type: _items[j].$1,
                    label: _items[j].$2,
                    icon: _items[j].$3,
                    tint: kindTint(_items[j].$4),
                    unavailable: !serviceAvailable(ref, _items[j].$1),
                    opacity: active && serviceAvailable(ref, _items[j].$1) ? 1 : 0.4,
                    onTap: () => openHomeService(context, ref, _items[j].$1),
                  )
                : const SizedBox.shrink(),
          ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: HomeSectionTitle('Payer et recharger')),
        const SizedBox(height: 12),
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var k = 0; k < rows[r].length; k++) ...[if (k > 0) const SizedBox(width: 8), rows[r][k]],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    required this.type,
    required this.label,
    required this.icon,
    required this.tint,
    required this.unavailable,
    required this.opacity,
    required this.onTap,
  });
  final ServiceType type;
  final String label;
  final IconData icon;
  final ({Color bg, Color fg}) tint;
  final bool unavailable;
  final double opacity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: DecoratedBox(
      decoration: homeSurface(),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('catalog-${type.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: tint.bg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 22, color: tint.fg),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: KColors.primary,
                  ),
                ),
                if (unavailable) ...[
                  const SizedBox(height: 2),
                  const Text(
                    'Indisponible',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

bool _statementRefused(Object error) {
  final f = ApiFailure.from(error);
  return f.statusCode == 400 && f.code == ErrorCodes.requestRejected;
}

/// « Transactions récentes » : 4 derniers mouvements + « Tout voir ».
class RecentTransactions extends ConsumerWidget {
  const RecentTransactions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(recentTransactionsProvider);
    final Widget body;
    if (txs.hasValue) {
      final items = txs.value!;
      body = items.isEmpty
          ? const Padding(
              key: Key('recent-empty'),
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                "Aucune transaction pour l'instant.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: KColors.onSurfaceVariant),
              ),
            )
          : Column(children: [for (var i = 0; i < items.length; i++) TransactionTile(items[i], showDivider: i > 0)]);
    } else if (txs.hasError && _statementRefused(txs.error!)) {
      // Carte suspendue, perdue ou désactivée : relevé non lisible (400), l'alerte de statut explique déjà.
      body = const Padding(
        key: Key('recent-unavailable'),
        padding: EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        child: Text(
          'Mouvements indisponibles tant que la carte n’est pas active.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: KColors.onSurfaceVariant),
        ),
      );
    } else if (txs.hasError) {
      body = ErrorView(error: txs.error!, onRetry: () => ref.invalidate(recentTransactionsProvider));
    } else {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              const Expanded(child: HomeSectionTitle('Transactions récentes')),
              TextButton(
                key: const Key('see-all'),
                style: TextButton.styleFrom(
                  foregroundColor: KColors.tertiary,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                onPressed: () => context.go(Routes.history),
                child: const Text('Tout voir'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          clipBehavior: Clip.antiAlias,
          decoration: homeSurface(),
          child: body,
        ),
      ],
    );
  }
}
