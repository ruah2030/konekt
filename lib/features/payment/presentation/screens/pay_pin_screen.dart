import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/providers/ticker.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../providers/payment_flow.dart';
import '../widgets/screen_protection.dart';

/// Saisie du code secret pour confirmer un paiement.
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
    final ok = await ref.read(paymentFlowProvider.notifier).submitPin(_value);
    if (!mounted) return;
    setState(() => _value = '');
    if (ok) context.go(Routes.processing);
  }

  void _delete() {
    if (_value.isEmpty) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(paymentFlowProvider);
    final now = ref.watch(nowProvider);
    final locked = flow.isPinLocked(now);
    final q = flow.quote;
    final t = Theme.of(context).textTheme;
    final error = locked
        ? ApiFailure(
            code: ErrorCodes.forbidden,
            message:
                'Réessayez dans ${(flow.pinLockedUntil!.difference(now).inSeconds / 60).ceil()} minute(s), '
                'ou réinitialisez votre code secret.',
            ref: flow.pinError?.ref,
          )
        : flow.pinError;
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
              locked ? 'Paiements verrouillés' : 'Confirmer le paiement',
              key: const Key('pay-pin-title'),
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: KColors.primary),
            ),
            if (q != null) ...[
              const SizedBox(height: 8),
              Text(
                '${q.service.title} · ${formatFcfa(q.total)}',
                style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 28),
            PinDots(value: _value, obscure: true, hasError: error != null && _value.isEmpty),
            const SizedBox(height: 16),
            if (flow.submitting)
              const Center(
                child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
              ),
            if (error != null) ErrorBlock(error),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                key: const Key('pay-pin-forgot'),
                onPressed: () => context.push(Routes.pinReset),
                style: TextButton.styleFrom(foregroundColor: KColors.tertiary),
                child: const Text('Code secret oublié ?'),
              ),
            ),
            const SizedBox(height: 8),
            NumericKeypad(onDigit: _digit, onDelete: _delete, enabled: !locked && !flow.submitting && q != null),
          ],
        ),
      ),
    );
  }
}
