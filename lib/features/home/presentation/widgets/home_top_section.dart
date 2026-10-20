import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/card.dart';
import '../../../../core/domain/service_type.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../../payment/presentation/open_service.dart';

/// Montant et unité affichés dans la carte solde selon le statut de la carte.
({String amount, String unit}) balanceDisplay({
  required CardStatus? status,
  required int? balance,
  required bool hidden,
}) => switch (status) {
  CardStatus.preActive => (amount: '0', unit: 'FCFA'),
  CardStatus.inactive || CardStatus.lostOrStolen => (amount: '—', unit: ''),
  _ when hidden => (amount: '••• •••', unit: 'FCFA'),
  _ => (amount: balance == null ? '…' : formatNumber(balance), unit: 'FCFA'),
};

/// Partie haute (fond blanc) : salutation, solde, actions rapides.
class HomeTopSection extends StatelessWidget {
  const HomeTopSection({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: KColors.surface,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -120,
            top: -60 + top,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x1AF0B23A), Color(0x00F0B23A)], stops: [0, 0.7]),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, 44),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_Header(), SizedBox(height: 24), _BalanceBlock(), SizedBox(height: 24), _QuickActions()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holder = ref.watch(holderProvider).value;
    final last4 = ref.watch(cardProvider).value?.last4;
    final unread = ref.watch(unreadCountProvider);
    return Row(
      children: [
        Container(
          key: const Key('home-avatar'),
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [KColors.navIndicator, KColors.secondary, Color(0xFFB87A0E)],
              stops: [0, 0.6, 1],
            ),
          ),
          child: Text(
            holder?.initials ?? '',
            style: const TextStyle(color: KColors.primary, fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                holder == null ? 'Bonjour' : 'Bonjour ${holder.firstName}',
                key: const Key('home-greeting'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.44,
                  color: KColors.primary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                last4 == null ? 'Carte' : 'Carte •••• $last4',
                style: const TextStyle(fontSize: 12, color: KColors.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('home-notifications'),
          tooltip: 'Notifications',
          onPressed: () => context.push(Routes.notifications),
          icon: Badge(
            key: const Key('unread-badge'),
            isLabelVisible: unread > 0,
            backgroundColor: KColors.warning,
            label: Text('$unread', key: const Key('unread-count')),
            child: const Icon(Symbols.notifications_rounded, color: KColors.primary),
          ),
        ),
      ],
    );
  }
}

class _BalanceBlock extends ConsumerWidget {
  const _BalanceBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(cardStatusProvider);
    final hidden = ref.watch(hideBalanceProvider);
    final balance = ref.watch(balanceProvider).value;
    final display = balanceDisplay(status: status, balance: balance, hidden: hidden);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Votre solde',
              style: TextStyle(fontSize: 14, color: KColors.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            if (status != null) StatusPill.card(status, key: const Key('home-card-status')),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        display.amount,
                        key: const Key('home-balance'),
                        style: const TextStyle(
                          fontSize: 38,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.1,
                          color: KColors.primary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (display.unit.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Text(
                          display.unit,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: KColors.secondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (status == CardStatus.active)
                IconButton(
                  key: const Key('toggle-balance'),
                  tooltip: hidden ? 'Afficher le solde' : 'Masquer le solde',
                  onPressed: () => ref.read(hideBalanceProvider.notifier).toggle(),
                  icon: Icon(
                    hidden ? Symbols.visibility_off_rounded : Symbols.visibility_rounded,
                    color: KColors.primary,
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(cardStatusProvider);
    final active = status == null || status.isActive;
    void openDisplay() {
      if (status != null && !status.isActive) {
        showToast(context, status.blockedMessage);
        return;
      }
      context.push(Routes.cardDisplay);
    }

    final items = [
      ('transfer', 'Envoyer', Symbols.north_east_rounded, () => openService(context, ref, ServiceType.transfer)),
      ('payout', 'Retirer', Symbols.south_west_rounded, () => openService(context, ref, ServiceType.payout)),
      ('topup', 'Recharger', Symbols.add_rounded, () => openService(context, ref, ServiceType.topup)),
      ('card', 'Ma carte', Symbols.visibility_rounded, openDisplay),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 3, right: i == items.length - 1 ? 0 : 3),
              child: _QuickAction(
                key: Key('quick-${items[i].$1}'),
                label: items[i].$2,
                icon: items[i].$3,
                onTap: items[i].$4,
                primary: i == 0,
                enabled: active,
              ),
            ),
          ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.primary,
    required this.enabled,
    super.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.4,
    child: Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: primary ? KColors.primary : KColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: primary
                      ? const [BoxShadow(color: Color(0x38140A72), blurRadius: 20, offset: Offset(0, 8))]
                      : null,
                ),
                child: Icon(icon, size: 24, color: primary ? KColors.onPrimary : KColors.primary),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.25, fontWeight: FontWeight.w700, color: KColors.primary),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
