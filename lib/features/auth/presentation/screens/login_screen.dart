import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../domain/auth_models.dart';
import '../providers/auth_controller.dart';
import '../providers/login_controller.dart';

/// Connexion par carte : identifiant + 4 derniers chiffres, puis code à usage unique.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _cardId = TextEditingController();
  final _last4 = TextEditingController();

  @override
  void dispose() {
    _cardId.dispose();
    _last4.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final c = await ref.read(loginControllerProvider.notifier).submit(cardId: _cardId.text, last4: _last4.text);
    if (c == null || !mounted) return;
    ref.read(loginChallengeProvider.notifier).set(c);
    unawaited(context.push(Routes.otp));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(loginControllerProvider);
    final ctrl = ref.read(loginControllerProvider.notifier);
    final incidents = ref.watch(incidentsProvider).value ?? const [];
    final t = Theme.of(context).textTheme;
    const labelStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155));

    return Scaffold(
      backgroundColor: KColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Image.asset('assets/images/logo-mark.png', width: 64),
                      ),
                      if (incidents.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        IncidentBanner(incidents.first.message),
                      ],
                      const SizedBox(height: 28),
                      Text(
                        'Connectez votre carte',
                        style: t.headlineMedium?.copyWith(
                          fontSize: 30,
                          height: 1.12,
                          letterSpacing: -0.75,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Aucun mot de passe. Un code à usage unique confirme que c'est bien vous.",
                        style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant, height: 1.5),
                      ),
                      const SizedBox(height: 28),
                      const Text('Identifiant de la carte', style: labelStyle),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('login-card-id'),
                        controller: _cardId,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        maxLength: 24,
                        onChanged: (_) => ctrl.clearError(),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: 0.7),
                        decoration: const InputDecoration(hintText: 'Au dos de la carte', counterText: ''),
                      ),
                      const SizedBox(height: 22),
                      const Text('4 derniers chiffres du numéro', style: labelStyle),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 150,
                          child: TextField(
                            key: const Key('login-last4'),
                            controller: _last4,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            onChanged: (_) => ctrl.clearError(),
                            onSubmitted: (_) => _submit(),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 6.4),
                            decoration: const InputDecoration(hintText: '••••'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Recevoir le code par',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<OtpChannel>(
                        key: const Key('login-channel'),
                        segments: [
                          for (final ch in OtpChannel.values)
                            ButtonSegment(
                              value: ch,
                              label: Text(ch.label, key: Key('channel-${ch.api}'), overflow: TextOverflow.ellipsis),
                              enabled: !LoginController.disabledChannels.contains(ch),
                            ),
                        ],
                        selected: {s.channel},
                        onSelectionChanged: s.busy ? null : (v) => ctrl.selectChannel(v.first),
                        showSelectedIcon: true,
                        selectedIcon: const Icon(Symbols.check_rounded, size: 18),
                      ),
                      if (LoginController.disabledChannels.contains(OtpChannel.whatsapp)) ...[
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'WhatsApp momentanément indisponible',
                            style: TextStyle(
                              fontSize: 12,
                              color: KColors.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      if (s.error != null) ...[const SizedBox(height: 22), ErrorBlock(s.error!)],
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          key: const Key('login-submit'),
                          onPressed: s.busy ? null : _submit,
                          child: s.busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: KColors.onPrimary),
                                )
                              : const Text('Recevoir mon code'),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Une session par carte. Pour une autre carte, reconnectez-vous avec elle.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: KColors.onSurfaceVariant, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
