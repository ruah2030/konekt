import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../design_system/design_system.dart';
import '../providers/waitlist_controller.dart';

/// « Obtenir une invitation » : trois façons d'obtenir un code, dont la liste d'attente.
class RequestInviteScreen extends ConsumerStatefulWidget {
  const RequestInviteScreen({super.key});

  static const ways = [
    ('Auprès d’un proche', 'Chaque membre Konekt peut inviter jusqu’à 5 personnes depuis son application.'),
    ('Chez un point marchand', 'Votre marchand BestCash vous remet un code à l’achat de votre carte.'),
    ('Liste d’attente', 'Inscrivez votre numéro ci-dessous, nous vous écrivons dès qu’une place se libère.'),
  ];

  @override
  ConsumerState<RequestInviteScreen> createState() => _RequestInviteScreenState();
}

class _RequestInviteScreenState extends ConsumerState<RequestInviteScreen> {
  final _phone = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    FocusScope.of(context).unfocus();
    final valid = await ref.read(waitlistControllerProvider.notifier).join(_phone.text);
    if (!valid && mounted) showToast(context, WaitlistController.invalidPhoneMessage);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(waitlistControllerProvider);
    final t = Theme.of(context).textTheme;
    final position = s.position;

    return Scaffold(
      backgroundColor: KColors.surface,
      appBar: AppBar(
        leading: IconButton(
          key: const Key('request-invite-back'),
          tooltip: 'Retour',
          icon: const Icon(Symbols.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.invite),
        ),
        title: const Text('Obtenir une invitation'),
        titleTextStyle: t.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.22),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                "Konekt ouvre progressivement. Trois façons d'obtenir votre code :",
                style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant, height: 1.5),
              ),
            ),
            const SizedBox(height: 20),
            Card.outlined(
              color: KColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: KColors.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final (i, (title, body)) in RequestInviteScreen.ways.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: KColors.secondaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: KColors.onSecondaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    body,
                                    style: const TextStyle(fontSize: 14, height: 1.43, color: KColors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              decoration: BoxDecoration(color: KColors.primary, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Rejoindre la liste d'attente",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Nous vous envoyons un code par SMS dès qu'une place se libère.",
                    style: TextStyle(fontSize: 14, height: 1.43, color: Color(0xFFB8BCE8)),
                  ),
                  const SizedBox(height: 16),
                  if (position != null)
                    Row(
                      key: const Key('waitlist-done'),
                      children: [
                        const Icon(Symbols.check_circle_rounded, size: 22, fill: 1, color: KColors.success),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Inscrit. Vous êtes n° $position sur la liste.',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    TextField(
                      key: const Key('waitlist-phone'),
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _join(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                      cursorColor: KColors.secondary,
                      decoration: InputDecoration(
                        hintText: '+229 01 00 00 00 00',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: KColors.secondary),
                        ),
                      ),
                    ),
                    if (s.error != null) ...[const SizedBox(height: 12), ErrorBlock(s.error!)],
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('waitlist-submit'),
                      style: FilledButton.styleFrom(
                        backgroundColor: KColors.secondary,
                        foregroundColor: KColors.primary,
                        minimumSize: const Size.fromHeight(48),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      onPressed: s.busy ? null : _join,
                      child: s.busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: KColors.primary),
                            )
                          : const Text("M'inscrire"),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
