import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/operation.dart';
import '../../../../core/domain/service_type.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../../history/presentation/providers/history_providers.dart';
import '../providers/payment_flow.dart';

/// Intervalle de suivi de l'opération (surchargeable en test).
final paymentPollIntervalProvider = Provider<Duration>((ref) => const Duration(seconds: 2));

/// Paiement en cours : stepper + suivi du statut jusqu'au résultat final.
class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  Timer? _timer;
  bool _polling = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(ref.read(paymentPollIntervalProvider), (_) => _poll());
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling || _done || !mounted) return;
    _polling = true;
    try {
      final current = ref.read(paymentFlowProvider).operation;
      final op = current != null && current.isFinal
          ? current
          : await ref.read(paymentFlowProvider.notifier).refreshOperation();
      if (!mounted || op == null || !op.isFinal) return;
      _done = true;
      _timer?.cancel();
      refreshAccountFromWidget(ref);
      invalidateHistory(ref);
      context.go(Routes.receipt(op.id));
    } catch (_) {
      // Erreur réseau ponctuelle : on réessaie au prochain tick.
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(paymentFlowProvider);
    final op = flow.operation;
    final q = flow.quote;
    final t = Theme.of(context).textTheme;
    final approval = q?.requiresUserApproval ?? op?.service == ServiceType.topup;
    final opLabel = q?.operatorLabel;
    final step = op?.step ?? OperationStep.authorized;
    final awaiting = approval && step == OperationStep.awaitingUserApproval;
    final steps = approval
        ? [
            'Prix confirmé',
            'Demande envoyée à ${opLabel ?? "l'opérateur"}',
            'Validation sur votre téléphone',
            'Carte créditée',
          ]
        : const ['Prix confirmé', 'Paiement autorisé', "Traitement chez l'émetteur"];
    final current = approval
        ? (awaiting ? 2 : 1)
        : step == OperationStep.processing
        ? 2
        : 1;
    final total = q?.total ?? op?.total ?? 0;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 64, 16, 20),
          children: [
            const Center(child: _BicolorSpinner()),
            const SizedBox(height: 28),
            Text(
              awaiting ? 'Validez sur votre téléphone' : 'Paiement en cours',
              key: const Key('processing-title'),
              textAlign: TextAlign.center,
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: KColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              awaiting
                  ? 'Une demande de ${formatFcfa(total)} est arrivée sur ${opLabel ?? 'votre Mobile Money'}. '
                        'Acceptez-la avec votre code Mobile Money.'
                  : 'Quelques secondes, nous attendons la réponse du partenaire.',
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    for (var i = 0; i < steps.length; i++) _StepRow(label: steps[i], index: i, current: current),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Ne relancez pas le paiement. Vous pouvez quitter : vous serez notifié du résultat.',
              textAlign: TextAlign.center,
              style: t.labelMedium?.copyWith(color: KColors.onSurfaceVariant, height: 1.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('processing-home'),
              onPressed: () {
                refreshAccountFromWidget(ref);
                invalidateHistory(ref);
                context.go(Routes.home);
              },
              child: const Text("Revenir à l'accueil"),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.index, required this.current});
  final String label;
  final int index;
  final int current;

  @override
  Widget build(BuildContext context) {
    final done = index < current, active = index == current;
    return Container(
      key: Key('step-$index'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: index == 0 ? null : const Border(top: BorderSide(color: KColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? KColors.success
                  : active
                  ? KColors.warning
                  : KColors.outlineVariant,
            ),
            child: Text(
              done
                  ? '✓'
                  : active
                  ? '•'
                  : '',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: index <= current ? KColors.primary : KColors.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spinner bicolore de la maquette (bleu nuit + or).
class _BicolorSpinner extends StatefulWidget {
  const _BicolorSpinner();

  @override
  State<_BicolorSpinner> createState() => _BicolorSpinnerState();
}

class _BicolorSpinnerState extends State<_BicolorSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _c,
    child: const SizedBox.square(dimension: 48, child: CustomPaint(painter: _SpinnerPainter())),
  );
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas
      ..drawArc(arc, 0, 2 * math.pi, false, p(const Color(0xFFE9EAF4)))
      ..drawArc(arc, -3 * math.pi / 4, math.pi / 2, false, p(KColors.primary))
      ..drawArc(arc, -math.pi / 4, math.pi / 2, false, p(KColors.secondary));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
