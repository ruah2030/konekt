import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/storage/app_prefs.dart';
import '../../../../design_system/design_system.dart';
import '../../../auth/domain/auth_models.dart';
import '../../../auth/presentation/providers/auth_controller.dart';

/// Écran de lancement : logo animé, barre de progression, puis routage selon la session.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  static const progressDuration = Duration(milliseconds: 2600);
  static const minDisplay = Duration(milliseconds: 2900);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this, duration: SplashScreen.progressDuration)
    ..forward();
  Timer? _timer;
  bool _timeUp = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SplashScreen.minDisplay, () {
      _timeUp = true;
      _maybeLeave();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _maybeLeave() {
    if (!mounted || _navigated || !_timeUp) return;
    final auth = ref.read(authControllerProvider);
    if (auth.status == AuthStatus.unknown) return;
    _navigated = true;
    if (auth.isAuthenticated) {
      // Le routeur redirige vers la création du code secret si nécessaire.
      context.go(Routes.home);
    } else {
      context.go(ref.read(appPrefsProvider).firstLaunchDone ? Routes.login : Routes.invite);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, _) => _maybeLeave());
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [KColors.splashTop, KColors.splashBottom],
            ),
          ),
          // Le logo reprend exactement la place et la taille du splash natif
          // (flutter_native_splash.yaml) : pas de saut à la transition.
          child: Stack(
            children: [
              Center(
                child: Image.asset(
                  'assets/images/logo-konekt.png',
                  key: const Key('splash-logo'),
                  width: 160,
                  semanticLabel: 'Konekt',
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 204,
                        height: 4,
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (context, _) => FractionallySizedBox(
                            key: const Key('splash-progress'),
                            widthFactor: _progress.value,
                            heightFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: KColors.warning, borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'POWERED BY BESTCASH',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.4,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
