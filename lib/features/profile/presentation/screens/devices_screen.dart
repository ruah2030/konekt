import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/storage/secure_store.dart';
import '../../../../core/utils/relative_date.dart';
import '../../../../design_system/design_system.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/profile_models.dart';
import '../providers/profile_providers.dart';

/// « Appareils connectés » : liste et déconnexion appareil par appareil.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  Future<void> _disconnect(BuildContext context, WidgetRef ref, Device d) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Déconnecter « ${d.label} » ?',
      body: d.current
          ? 'C’est l’appareil que vous utilisez : vous reviendrez à l’écran de connexion.'
          : 'La session de cet appareil est fermée immédiatement.',
      confirmLabel: 'Déconnecter',
      icon: Symbols.logout_rounded,
      color: KColors.error,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(devicesProvider.notifier).remove(d.id);
      if (d.current) {
        // Le serveur a révoqué cette session : on oublie aussi les jetons locaux.
        await ref.read(secureStoreProvider).clearTokens();
        ref.read(authControllerProvider.notifier).sessionEnded();
        return;
      }
      if (context.mounted) showToast(context, 'Appareil déconnecté.');
    } catch (e) {
      if (context.mounted) showToast(context, ApiFailure.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('devices-back'),
          tooltip: 'Retour',
          icon: const Icon(Symbols.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.profile),
        ),
        title: const Text('Appareils connectés'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(devicesProvider.notifier).refresh(),
        child: switch (devices) {
          AsyncData(:final value) when value.isEmpty => ListView(
            children: const [EmptyState(message: 'Aucun appareil connecté.', icon: Symbols.devices_rounded)],
          ),
          AsyncData(:final value) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) =>
                _DeviceCard(device: value[i], onDisconnect: () => _disconnect(context, ref, value[i])),
          ),
          AsyncError(:final error) when !devices.isLoading => ListView(
            children: [ErrorView(error: error, onRetry: () => ref.invalidate(devicesProvider))],
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onDisconnect});
  final Device device;
  final VoidCallback onDisconnect;

  IconData get _icon => switch (device.platform) {
    DevicePlatform.android => Symbols.smartphone_rounded,
    DevicePlatform.ios => Symbols.phone_iphone_rounded,
    DevicePlatform.web => Symbols.language_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final seen = device.current ? 'actif maintenant' : 'vu ${relativeDate(device.lastSeenAt).toLowerCase()}';
    return Card(
      key: Key('device-${device.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(_icon, color: KColors.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(device.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      if (device.current)
                        Container(
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: KColors.successContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Cet appareil',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: KColors.successDark),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${device.platform.label} · $seen',
                    style: const TextStyle(fontSize: 12, color: KColors.onSurfaceVariant, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: Key('device-disconnect-${device.id}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KColors.error,
                side: const BorderSide(color: Color(0xFFF3D4D4)),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              onPressed: onDisconnect,
              child: const Text('Déconnecter'),
            ),
          ],
        ),
      ),
    );
  }
}
