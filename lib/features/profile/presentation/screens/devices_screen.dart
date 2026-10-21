import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/utils/relative_date.dart';
import '../../../../design_system/design_system.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/profile_models.dart';
import '../providers/profile_providers.dart';

/// « Appareils connectés » : liste et déconnexion appareil par appareil.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  /// Confirmation systématique ; obligatoire pour l'appareil courant (retour à l'écran de connexion).
  Future<void> _disconnect(BuildContext context, WidgetRef ref, Device d) async {
    final ok = await showConfirmDialog(
      context,
      title: d.isCurrent ? 'Déconnecter cet appareil ?' : 'Déconnecter « ${d.label} » ?',
      body: d.isCurrent
          ? 'C’est l’appareil que vous utilisez : votre session sera fermée et vous reviendrez à l’écran de connexion.'
          : 'Les sessions de cet appareil sont fermées immédiatement.',
      confirmLabel: 'Déconnecter',
      icon: Symbols.logout_rounded,
      color: KColors.error,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(devicesProvider.notifier).disconnect(d.deviceId);
      if (d.isCurrent) {
        // Le serveur a révoqué la session appelante : on efface la session locale.
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
            itemBuilder: (_, i) => _DeviceCard(
              device: value[i],
              onDisconnect: value[i].hasActiveSession ? () => _disconnect(context, ref, value[i]) : null,
            ),
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

  /// `null` : aucune session active sur cet appareil.
  final VoidCallback? onDisconnect;

  IconData get _icon => switch (device.type) {
    DeviceType.android => Symbols.smartphone_rounded,
    DeviceType.ios => Symbols.phone_iphone_rounded,
    DeviceType.web => Symbols.language_rounded,
    DeviceType.other => Symbols.devices_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final lastSeen = device.lastSeenAt;
    final seen = device.isCurrent
        ? 'actif maintenant'
        : lastSeen == null
        ? null
        : 'vu ${relativeDate(lastSeen).toLowerCase()}';
    final details = [
      device.type.label,
      ?seen,
      if (device.lastIpAddress != null) 'IP ${device.lastIpAddress}',
    ].join(' · ');
    final first = device.firstSeenAt;
    const meta = TextStyle(fontSize: 12, color: KColors.onSurfaceVariant, fontWeight: FontWeight.w500);
    return Card(
      key: Key('device-${device.deviceId}'),
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
                      if (device.isCurrent)
                        Container(
                          key: const Key('device-current-badge'),
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
                  Text(details, style: meta),
                  if (first != null) Text('Première connexion : ${relativeDate(first).toLowerCase()}', style: meta),
                  Text(
                    [
                      if (!device.hasActiveSession) 'Session fermée',
                      device.notificationsEnabled ? 'Notifications activées' : 'Notifications désactivées',
                    ].join(' · '),
                    style: meta,
                  ),
                ],
              ),
            ),
            if (onDisconnect != null) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                key: Key('device-disconnect-${device.deviceId}'),
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
          ],
        ),
      ),
    );
  }
}
