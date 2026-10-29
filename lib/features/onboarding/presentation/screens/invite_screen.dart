import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/storage/app_prefs.dart';
import '../../../../design_system/design_system.dart';
import '../../data/invite_link_service.dart';
import '../providers/invite_controller.dart';

/// Normalise la saisie : majuscules, lettres, chiffres, `-` et `_`, 40 caractères au plus.
class InviteCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = InviteController.normalize(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Premier lancement : saisie du code d'invitation du marchand (transmis à la connexion).
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key});

  static const acceptedDelay = Duration(milliseconds: 1500);

  static int _visible = 0;

  /// L'écran est affiché (un code reçu par lien s'y affiche, sans toast).
  static bool get isShowing => _visible > 0;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _code = TextEditingController();
  Timer? _leaveTimer;

  @override
  void initState() {
    super.initState();
    InviteScreen._visible++;
    _code.addListener(() => setState(() {}));
    // Code reçu par le lien qui a lancé l'app (ou pendant le splash).
    final received = ref.read(inviteLinkProvider);
    if (received != null) Future.microtask(() => _acceptFromLink(received.code));
  }

  @override
  void dispose() {
    InviteScreen._visible--;
    _leaveTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final ok = await ref.read(inviteControllerProvider.notifier).submit(_code.text);
    if (!ok || !mounted) return;
    _leaveTimer = Timer(InviteScreen.acceptedDelay, () {
      if (mounted) context.go(Routes.login);
    });
  }

  /// Code lu depuis un lien d'invitation : champ pré-rempli et état « enregistré », puis connexion.
  Future<void> _acceptFromLink(String code) async {
    if (!mounted) return;
    final ok = await ref.read(inviteControllerProvider.notifier).acceptFromLink(code);
    if (!ok || !mounted) return;
    _code.text = code;
    _leaveTimer?.cancel();
    _leaveTimer = Timer(InviteScreen.acceptedDelay, () {
      if (mounted) context.go(Routes.login);
    });
  }

  /// « skipInvite » de la maquette : la personne a déjà une carte.
  Future<void> _skip() async {
    final prefs = ref.read(appPrefsProvider);
    await prefs.setReferralCode(null);
    await prefs.setFirstLaunchDone();
    if (mounted) context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(inviteControllerProvider);
    ref.listen<ReceivedInviteCode?>(inviteLinkProvider, (_, next) {
      if (next != null) _acceptFromLink(next.code);
    });
    final complete = _code.text.length >= InviteController.minLength;
    final t = Theme.of(context).textTheme;
    final borderColor = s.error != null
        ? KColors.error
        : s.status == InviteStatus.accepted
        ? KColors.success
        : complete
        ? KColors.primary
        : KColors.outlineVariant;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: borderColor, width: 1.5),
    );

    return Scaffold(
      backgroundColor: KColors.surface,
      body: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: IntrinsicHeight(
              child: Stack(
                children: [
                  const Positioned(top: 0, left: 0, right: 0, height: 380, child: _OnboardingVideo()),
                  Column(
                    children: [
                      const SizedBox(height: 352),
                      Expanded(
                        child: Container(
                          decoration: const BoxDecoration(
                            color: KColors.surface,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                          ),
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                          child: SafeArea(
                            top: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'SUR INVITATION',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.76,
                                    color: Color(0xFFB87A0E),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Votre carte vous attend',
                                  style: t.headlineMedium?.copyWith(
                                    fontSize: 28,
                                    height: 1.15,
                                    letterSpacing: -0.56,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Entrez le code d'invitation reçu de votre marchand ou d'un proche pour continuer.",
                                  style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant, height: 1.5),
                                ),
                                const SizedBox(height: 20),
                                TextField(
                                  key: const Key('invite-code'),
                                  controller: _code,
                                  enabled: s.status == InviteStatus.idle,
                                  textAlign: TextAlign.center,
                                  textCapitalization: TextCapitalization.characters,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  inputFormatters: [InviteCodeFormatter()],
                                  onChanged: (_) => ref.read(inviteControllerProvider.notifier).edited(),
                                  onSubmitted: (_) => complete ? _submit() : null,
                                  style: const TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 3,
                                    color: KColors.primary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'CODE MARCHAND',
                                    contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
                                    border: border,
                                    enabledBorder: border,
                                    disabledBorder: border,
                                    focusedBorder: border.copyWith(
                                      borderSide: BorderSide(
                                        color: s.error != null ? KColors.error : KColors.primary,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                if (s.error != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Symbols.error_rounded, size: 16, color: KColors.error),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            s.error!,
                                            key: const Key('invite-error'),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              height: 1.4,
                                              color: KColors.error,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (s.status == InviteStatus.accepted)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Center(
                                      child: Container(
                                        key: const Key('invite-accepted'),
                                        constraints: const BoxConstraints(minHeight: 32),
                                        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                                        decoration: BoxDecoration(
                                          color: KColors.successContainer,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Symbols.check_circle_rounded,
                                              size: 18,
                                              fill: 1,
                                              color: KColors.successDark,
                                            ),
                                            SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                "Code d'invitation enregistré",
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: KColors.successDark,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                const SizedBox(height: 20),
                                FilledButton(
                                  key: const Key('invite-submit'),
                                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                                  onPressed: complete && s.status == InviteStatus.idle ? _submit : null,
                                  child: Text(switch (s.status) {
                                    InviteStatus.saving => 'Enregistrement…',
                                    InviteStatus.accepted => 'Bienvenue',
                                    InviteStatus.idle => 'Continuer',
                                  }),
                                ),
                                const SizedBox(height: 4),
                                TextButton(
                                  key: const Key('invite-no-code'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: KColors.primary,
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  onPressed: () => context.push(Routes.requestInvite),
                                  child: const Text("Je n'ai pas de code d'invitation"),
                                ),
                                TextButton(
                                  key: const Key('invite-skip'),
                                  style: TextButton.styleFrom(foregroundColor: KColors.onSurfaceVariant),
                                  onPressed: s.status == InviteStatus.idle ? _skip : null,
                                  child: const Text("J'ai déjà une carte"),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'POWERED BY BESTCASH CARDS BÉNIN',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.33,
                                    color: KColors.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// Vidéo d'onboarding muette en boucle, avec fond de remplacement si elle ne peut pas être lue.
class _OnboardingVideo extends StatefulWidget {
  const _OnboardingVideo();

  @override
  State<_OnboardingVideo> createState() => _OnboardingVideoState();
}

class _OnboardingVideoState extends State<_OnboardingVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.asset(
        'assets/video/onboarding-card.mp4',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = c;
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(true);
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // Plugin absent (tests) ou lecture impossible : on garde le fond de remplacement.
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      try {
        unawaited(c.dispose().catchError((_) {}));
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_ready && c != null && c.value.isInitialized) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
        ),
      );
    }
    return Container(
      key: const Key('invite-video-fallback'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [KColors.splashTop, KColors.splashBottom],
        ),
      ),
      alignment: Alignment.center,
      child: Image.asset('assets/images/logo-konekt.png', width: 140),
    );
  }
}
