import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/domain/service_type.dart';
import '../../features/auth/domain/auth_models.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/card/presentation/screens/card_screen.dart';
import '../../features/card/presentation/screens/secure_display_screen.dart';
import '../../features/history/presentation/screens/history_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/onboarding/presentation/screens/invite_screen.dart';
import '../../features/onboarding/presentation/screens/request_invite_screen.dart';
import '../../features/onboarding/presentation/screens/splash_screen.dart';
import '../../features/payment/presentation/screens/pay_pin_screen.dart';
import '../../features/payment/presentation/screens/processing_screen.dart';
import '../../features/payment/presentation/screens/quote_screen.dart';
import '../../features/payment/presentation/screens/receipt_screen.dart';
import '../../features/payment/presentation/screens/service_form_screen.dart';
import '../../features/pin/domain/pin_flow.dart';
import '../../features/pin/presentation/screens/pin_flow_screen.dart';
import '../../features/profile/presentation/screens/devices_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/shell/main_shell.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Règles de redirection (pures, testables) :
/// - session inconnue : on reste sur le splash ;
/// - non connecté sur une route protégée → login ;
/// - connecté sans code secret → création obligatoire du PIN ;
/// - connecté sur une route publique (hors splash) → accueil.
String? authRedirect(AuthState auth, String location) {
  final isPublic = Routes.public.contains(location);
  switch (auth.status) {
    case AuthStatus.unknown:
      return location == Routes.splash ? null : Routes.splash;
    case AuthStatus.unauthenticated:
      return isPublic ? null : Routes.login;
    case AuthStatus.authenticated:
      if (!auth.hasPin) return location == Routes.pinSetup ? null : Routes.pinSetup;
      if (location == Routes.pinSetup) return Routes.home;
      if (isPublic && location != Routes.splash) return Routes.home;
      return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref
    ..listen(authControllerProvider, (_, next) => refresh.value = next)
    ..onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => authRedirect(ref.read(authControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.invite, builder: (_, _) => const InviteScreen()),
      GoRoute(path: Routes.requestInvite, builder: (_, _) => const RequestInviteScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.otp, builder: (_, _) => const OtpScreen()),
      GoRoute(
        path: Routes.pinSetup,
        builder: (_, _) => const PinFlowScreen(flow: PinFlow.setup),
      ),
      GoRoute(
        path: Routes.pinChange,
        builder: (_, _) => const PinFlowScreen(flow: PinFlow.change),
      ),
      GoRoute(
        path: Routes.pinReset,
        builder: (_, _) => const PinFlowScreen(flow: PinFlow.reset),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.history, builder: (_, _) => const HistoryScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.card, builder: (_, _) => const CardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),
      GoRoute(path: Routes.cardDisplay, builder: (_, _) => const SecureDisplayScreen()),
      GoRoute(path: Routes.devices, builder: (_, _) => const DevicesScreen()),
      GoRoute(path: Routes.notifications, builder: (_, _) => const NotificationsScreen()),
      // Routes fixes avant le paramètre `:type`.
      GoRoute(path: Routes.quote, builder: (_, _) => const QuoteScreen()),
      GoRoute(path: Routes.payPin, builder: (_, _) => const PayPinScreen()),
      GoRoute(path: Routes.processing, builder: (_, _) => const ProcessingScreen()),
      GoRoute(
        path: '/pay/:type',
        redirect: (_, state) => ServiceType.tryParse(state.pathParameters['type']) == null ? Routes.home : null,
        builder: (_, state) => ServiceFormScreen(type: ServiceType.tryParse(state.pathParameters['type'])!),
      ),
      GoRoute(
        path: '/receipt/:id',
        builder: (_, state) => ReceiptScreen(
          operationId: state.pathParameters['id']!,
          fromHistory: state.uri.queryParameters['from'] == 'history',
        ),
      ),
    ],
  );
});
