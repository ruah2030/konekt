import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../design_system/design_system.dart';
import '../../../auth/domain/auth_models.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/profile_models.dart';
import '../providers/profile_providers.dart';

/// Onglet « Profil » : sécurité, canal des messages, session.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    // Après une déconnexion, l'écran reste monté le temps que le routeur redirige :
    // on n'observe plus les données de compte (évite des rechargements sans session).
    if (auth.status != AuthStatus.authenticated) return const Scaffold();
    final hasPin = auth.hasPin;
    final devices = ref.watch(devicesProvider).value;
    final version = ref.watch(displayVersionProvider).value ?? '2.0';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(channelPreferenceProvider);
            await ref.read(devicesProvider.notifier).refresh();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              const _Header(),
              const SizedBox(height: 22),
              const _SectionTitle('Sécurité'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _RowTile(
                        key: const Key('profile-pin'),
                        icon: Symbols.password_rounded,
                        label: hasPin ? 'Changer mon code secret' : 'Créer mon code secret',
                        onTap: () => context.push(hasPin ? Routes.pinChange : Routes.pinSetup),
                      ),
                      const Divider(height: 1, color: KColors.divider),
                      _RowTile(
                        key: const Key('profile-pin-reset'),
                        icon: Symbols.lock_reset_rounded,
                        label: 'Code secret oublié',
                        sub: 'Lève aussi un éventuel verrouillage',
                        onTap: () => context.push(Routes.pinReset),
                      ),
                      const Divider(height: 1, color: KColors.divider),
                      _RowTile(
                        key: const Key('profile-devices'),
                        icon: Symbols.devices_rounded,
                        label: 'Appareils connectés',
                        sub: devices == null
                            ? null
                            : '${devices.where((d) => d.hasActiveSession).length} appareil(s) connecté(s)',
                        onTap: () => context.push(Routes.devices),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const _SectionTitle('Recevoir mes messages par'),
              const _ChannelPicker(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Un seul message par événement. Une carte déclarée perdue est signalée sur tous les canaux.',
                  style: TextStyle(
                    fontSize: 12,
                    color: KColors.onSurfaceVariant,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const _SectionTitle('Session'),
              const _SessionCard(),
              const SizedBox(height: 22),
              Text(
                'KONEKT $version · POWERED BY BESTCASH',
                key: const Key('profile-version'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: KColors.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(cardSessionProvider);
    final last4 = session?.last4;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [KColors.navIndicator, KColors.secondary, Color(0xFFB87A0E)],
                stops: [0, 0.6, 1],
              ),
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: Colors.transparent,
              foregroundColor: KColors.primary,
              child: Text(session?.initials ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session?.fullName ?? '',
                  key: const Key('profile-name'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                ),
                const SizedBox(height: 2),
                Text(
                  key: const Key('profile-card'),
                  last4 == null || last4.isEmpty ? '' : 'Carte •••• $last4',
                  style: const TextStyle(fontSize: 13, color: KColors.onSurfaceVariant, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KColors.tertiary),
    ),
  );
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.icon, required this.label, required this.onTap, this.sub, super.key});
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.only(left: 16, right: 8),
    leading: Icon(icon, color: KColors.onSurfaceVariant),
    title: Text(
      label,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: KColors.primary),
    ),
    subtitle: sub == null
        ? null
        : Text(
            sub!,
            style: const TextStyle(fontSize: 12, color: KColors.onSurfaceVariant, fontWeight: FontWeight.w500),
          ),
    trailing: const Icon(Symbols.chevron_right_rounded, color: KColors.outline),
  );
}

class _ChannelPicker extends ConsumerWidget {
  const _ChannelPicker();

  Future<void> _select(BuildContext context, WidgetRef ref, MessageChannel channel) async {
    try {
      await ref.read(channelPreferenceProvider.notifier).select(channel);
      if (context.mounted) showToast(context, 'Préférence enregistrée.');
    } catch (e) {
      if (context.mounted) showToast(context, ApiFailure.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pref = ref.watch(channelPreferenceProvider);
    final selected = pref.value;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<MessageChannel>(
        key: const Key('profile-channel'),
        showSelectedIcon: true,
        emptySelectionAllowed: true,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: KColors.secondaryContainer,
          selectedForegroundColor: KColors.primary,
          foregroundColor: KColors.primary,
          side: const BorderSide(color: KColors.outline),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          minimumSize: const Size(0, 44),
        ),
        segments: [
          for (final c in MessageChannel.values)
            ButtonSegment(
              value: c,
              label: Text(c.label, key: Key('channel-${c.name}'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        selected: {?selected},
        onSelectionChanged: selected == null
            ? null
            : (s) {
                if (s.isEmpty || s.first == selected) return;
                _select(context, ref, s.first);
              },
      ),
    );
  }
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard();

  Future<void> _logout(WidgetRef ref) async {
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } catch (_) {
      // La session locale est fermée même si l'appel serveur échoue.
    }
  }

  Future<void> _logoutAll(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Déconnecter tous les appareils ?',
      body: 'Toutes vos sessions seront fermées, y compris celle-ci. Il faudra vous reconnecter avec votre carte.',
      confirmLabel: 'Tout déconnecter',
      icon: Symbols.phonelink_erase_rounded,
      color: KColors.error,
    );
    if (!ok || !context.mounted) return;
    // L'écran disparaît après la déconnexion (redirection) : on garde le messenger racine.
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final n = await ref.read(authControllerProvider.notifier).logoutAll();
      message = '$n sessions fermées.';
    } catch (e) {
      message = ApiFailure.from(e).message;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 2600)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          ListTile(
            key: const Key('profile-logout'),
            onTap: () => _logout(ref),
            leading: const Icon(Symbols.logout_rounded, color: KColors.onSurfaceVariant),
            title: const Text(
              'Se déconnecter',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: KColors.primary),
            ),
          ),
          const Divider(height: 1, color: KColors.divider),
          ListTile(
            key: const Key('profile-logout-all'),
            onTap: () => _logoutAll(context, ref),
            leading: const Icon(Symbols.phonelink_erase_rounded, color: KColors.error),
            title: const Text(
              'Déconnecter tous mes appareils',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: KColors.error),
            ),
            subtitle: const Text(
              'En cas de téléphone perdu',
              style: TextStyle(fontSize: 12, color: KColors.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    ),
  );
}
