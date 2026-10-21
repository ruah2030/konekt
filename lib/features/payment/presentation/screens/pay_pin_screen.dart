import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/ticker.dart';
import '../../../../core/utils/countdown.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../providers/payment_flow.dart';
import '../widgets/screen_protection.dart';

/// Saisie du code secret (6 chiffres) pour confirmer un paiement par carte, ou du code reçu
/// par message (voie OTP d'une opération carte, quand `requiresConfirmation` est vrai).
class PayPinScreen extends ConsumerStatefulWidget {
  const PayPinScreen({super.key});

  @override
  ConsumerState<PayPinScreen> createState() => _PayPinScreenState();
}

class _PayPinScreenState extends ConsumerState<PayPinScreen> {
  String _value = '';

  @override
  void initState() {
    super.initState();
    setScreenProtection(on: true);
  }

  @override
  void dispose() {
    setScreenProtection(on: false);
    super.dispose();
  }

  Future<void> _digit(String d) async {
    final flow = ref.read(paymentFlowProvider);
    if (_value.length >= 6 || flow.submitting) return;
    setState(() => _value += d);
    if (_value.length < 6) return;
    final outcome = await ref.read(paymentFlowProvider.notifier).submitSecret(_value);
    if (!mounted) return;
    setState(() => _value = '');
    switch (outcome) {
      case SecretOutcome.submitted:
        context.go(Routes.processing);
      case SecretOutcome.requote:
        // Devis trop proche de l'échéance : retour au récapitulatif pour le refaire.
        if (context.canPop()) context.pop();
      case SecretOutcome.retry || SecretOutcome.restart:
        break;
    }
  }

  void _delete() {
    if (_value.isEmpty) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  Future<void> _requote() async {
    final ok = await ref.read(paymentFlowProvider.notifier).requote();
    if (!mounted) return;
    if (ok && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(paymentFlowProvider);
    final q = flow.quote;
    final otp = q?.requiresConfirmation ?? false;
    final now = ref.watch(nowProvider);
    final t = Theme.of(context).textTheme;
    final blocked = flow.needsRequote || flow.restartRequired;
    final otpLeft = q?.otpExpiresAt == null ? null : remaining(q!.otpExpiresAt!, now);
    return Scaffold(
      backgroundColor: KColors.surface,
      appBar: AppBar(
        backgroundColor: KColors.surface,
        leading: IconButton(
          key: const Key('pay-pin-back'),
          tooltip: 'Retour',
          icon: const Icon(Symbols.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.quote),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              otp ? 'Saisissez le code reçu' : 'Confirmer le paiement',
              key: const Key('pay-pin-title'),
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: KColors.primary),
            ),
            if (q != null) ...[
              const SizedBox(height: 8),
              Text(
                '${q.service.title} · ${formatFcfa(q.amountDebited)}',
                style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant),
              ),
              if (otp) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    'Code envoyé${q.otpChannel != null ? ' par ${q.otpChannel}' : ''}'
                        '${q.sentTo != null ? ' au ${q.sentTo}' : ''}',
                    if (otpLeft != null) otpLeft.isNegative ? 'code expiré' : 'expire dans ${mmss(otpLeft)}',
                  ].join(' · '),
                  key: const Key('pay-otp-info'),
                  style: t.bodySmall?.copyWith(color: KColors.onSurfaceVariant),
                ),
              ],
            ],
            const SizedBox(height: 28),
            PinDots(value: _value, obscure: !otp, hasError: flow.pinError != null && _value.isEmpty),
            const SizedBox(height: 16),
            if (flow.submitting)
              const Center(
                child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
              ),
            if (flow.pinError != null) ErrorBlock(flow.pinError!),
            if (flow.quoteError != null) ...[const SizedBox(height: 8), ErrorBlock(flow.quoteError!)],
            if (blocked) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('pay-pin-requote'),
                onPressed: flow.quoting ? null : _requote,
                icon: const Icon(Symbols.refresh_rounded, size: 20),
                label: Text(flow.restartRequired ? 'Recommencer' : 'Refaire le devis'),
              ),
            ],
            const SizedBox(height: 8),
            if (!otp)
              Center(
                child: TextButton(
                  key: const Key('pay-pin-forgot'),
                  onPressed: () => context.push(Routes.pinReset),
                  style: TextButton.styleFrom(foregroundColor: KColors.tertiary),
                  child: const Text('Code secret oublié ?'),
                ),
              ),
            const SizedBox(height: 8),
            NumericKeypad(onDigit: _digit, onDelete: _delete, enabled: !flow.submitting && !blocked && q != null),
          ],
        ),
      ),
    );
  }
}
