import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../../history/presentation/providers/history_providers.dart';
import '../../domain/payment_models.dart';
import '../providers/payment_flow.dart';

/// Intervalle de suivi de l'opération (guide : toutes les 5 à 10 s ; surchargeable en test).
final paymentPollIntervalProvider = Provider<Duration>((ref) => const Duration(seconds: 5));

/// Durée maximale du suivi : au-delà, « vous serez notifié », sans jamais relancer le paiement.
final paymentTrackingTimeoutProvider = Provider<Duration>((ref) => const Duration(minutes: 10));

/// Paiement en cours : stepper, validation sur le téléphone, saisie du code B-MO, ou
/// « en vérification » ; suivi de `GET /cards/operations/:id` jusqu'à un statut final.
class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  Timer? _timer;
  bool _polling = false;
  bool _done = false;
  bool _timedOut = false;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(ref.read(paymentPollIntervalProvider), (_) => _poll());
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling || _done || _timedOut || !mounted) return;
    final flow = ref.read(paymentFlowProvider);
    if (flow.operationId == null) return;
    _polling = true;
    try {
      final op = await ref.read(paymentFlowProvider.notifier).refreshOperation();
      if (!mounted || op == null) return;
      if (op.isFinal) {
        _finish(op.id);
        return;
      }
      final since = ref.read(paymentFlowProvider).trackingSince;
      final now = ref.read(paymentClockProvider)();
      if (since != null && now.difference(since) >= ref.read(paymentTrackingTimeoutProvider)) {
        _timer?.cancel();
        setState(() => _timedOut = true);
      }
    } catch (_) {
      // Erreur réseau ponctuelle : on réessaie au prochain tick.
    } finally {
      _polling = false;
    }
  }

  void _finish(String operationId) {
    _done = true;
    _timer?.cancel();
    _refreshAccount();
    context.go(Routes.receipt(operationId));
  }

  void _refreshAccount() {
    refreshAccountFromWidget(ref);
    invalidateHistory(ref);
  }

  Future<void> _submitCode() async {
    final code = _code.text.trim();
    final failure = await ref.read(paymentFlowProvider.notifier).submitFundingCode(code);
    if (!mounted) return;
    if (failure == null) _code.clear();
    final op = ref.read(paymentFlowProvider).operation;
    if (op != null && op.isFinal && !_done) _finish(op.id);
  }

  Future<void> _cancelFunding() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Annuler le paiement ?',
      body: 'La demande de paiement sera annulée chez BestCash Money. Rien ne sera prélevé.',
      confirmLabel: 'Annuler le paiement',
      icon: Icons.close_rounded,
      color: KColors.error,
    );
    if (!ok || !mounted) return;
    await ref.read(paymentFlowProvider.notifier).cancelFunding();
    if (!mounted) return;
    final op = ref.read(paymentFlowProvider).operation;
    if (op != null && op.isFinal && !_done) _finish(op.id);
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(paymentFlowProvider);
    final q = flow.quote;
    final t = Theme.of(context).textTheme;
    final awaiting = flow.awaiting;
    final external = q?.isExternal ?? false;
    final wallet = flow.request?.walletLabel;
    final total = q?.amountDebited ?? flow.operation?.amountDebited ?? 0;
    final review = flow.review;
    final codeEntry = awaiting == ExecutionResult.confirmationCode && review == null && !_timedOut;

    final (String title, String body) = _timedOut
        ? (
            'Opération en cours de traitement',
            'Le partenaire n’a pas encore répondu. Vous serez notifié du résultat : ne relancez pas le paiement.',
          )
        : review != null
        ? ('Paiement en vérification', review.message)
        : codeEntry
        ? (
            'Saisissez le code reçu',
            'Un code de confirmation a été envoyé par SMS au payeur${wallet != null ? ' ($wallet)' : ''}. '
                'Saisissez-le pour valider le paiement de ${formatFcfa(total)}.',
          )
        : awaiting == ExecutionResult.payerApproval
        ? (
            'Validez sur votre téléphone',
            'Une demande de ${formatFcfa(total)} est arrivée sur ${wallet ?? 'votre Mobile Money'}. '
                'Acceptez-la avec votre code Mobile Money.',
          )
        : awaiting == ExecutionResult.providerSettlement
        ? (
            'Paiement en attente du partenaire',
            'Le prestataire n’a pas encore répondu : le sort du paiement sera établi automatiquement. Ne relancez pas.',
          )
        : ('Paiement en cours', 'Quelques secondes, nous attendons la réponse du partenaire.');

    final steps = external
        ? [
            'Prix confirmé',
            'Demande envoyée à ${wallet ?? "l'opérateur"}',
            awaiting == ExecutionResult.confirmationCode ? 'Code de confirmation' : 'Validation sur votre téléphone',
            'Carte créditée',
          ]
        : const ['Prix confirmé', 'Paiement autorisé', 'Traitement chez le partenaire'];
    const current = 2;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
          children: [
            if (review == null && !_timedOut) const Center(child: _BicolorSpinner()),
            if (review != null || _timedOut)
              const Center(child: Icon(Icons.hourglass_top_rounded, size: 48, color: KColors.warning)),
            const SizedBox(height: 28),
            Text(
              title,
              key: const Key('processing-title'),
              textAlign: TextAlign.center,
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: KColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              key: const Key('processing-body'),
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant, height: 1.5),
            ),
            if (review != null && (review.ref != null || flow.reference != null)) ...[
              const SizedBox(height: 8),
              Text(
                'Réf. ${review.ref ?? flow.reference}',
                textAlign: TextAlign.center,
                style: t.labelSmall?.copyWith(color: KColors.onSurfaceVariant),
              ),
            ],
            if (codeEntry) ...[
              const SizedBox(height: 24),
              TextField(
                key: const Key('funding-code'),
                controller: _code,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 6),
                decoration: const InputDecoration(hintText: 'Code'),
              ),
              if (flow.codeError != null) ...[const SizedBox(height: 12), ErrorBlock(flow.codeError!)],
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('funding-submit'),
                onPressed: flow.submitting ? null : _submitCode,
                child: const Text('Valider le paiement'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('funding-cancel'),
                onPressed: flow.submitting ? null : _cancelFunding,
                child: const Text('Annuler le paiement'),
              ),
            ],
            if (review == null && !_timedOut) ...[
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
            ],
            const SizedBox(height: 28),
            Text(
              'Ne relancez pas le paiement. Vous pouvez quitter : vous serez notifié du résultat.',
              textAlign: TextAlign.center,
              style: t.labelMedium?.copyWith(color: KColors.onSurfaceVariant, height: 1.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            if (review != null && flow.operationId == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton(
                  key: const Key('processing-history'),
                  onPressed: () {
                    _refreshAccount();
                    context.go(Routes.history);
                  },
                  child: const Text('Voir mes opérations'),
                ),
              ),
            OutlinedButton(
              key: const Key('processing-home'),
              onPressed: () {
                _refreshAccount();
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
