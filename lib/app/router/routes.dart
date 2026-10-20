import '../../core/domain/service_type.dart';

/// Chemins de navigation (go_router).
abstract final class Routes {
  static const splash = '/splash';
  static const invite = '/invite';
  static const requestInvite = '/invite/request';
  static const login = '/login';
  static const otp = '/otp';

  /// `/pin/setup`, `/pin/change`, `/pin/reset`
  static const pinSetup = '/pin/setup';
  static const pinChange = '/pin/change';
  static const pinReset = '/pin/reset';

  // Onglets (NavigationBar)
  static const home = '/home';
  static const history = '/history';
  static const card = '/card';
  static const profile = '/profile';

  static const cardDisplay = '/card/display';
  static const devices = '/profile/devices';
  static const notifications = '/notifications';

  // Paiement
  static String service(ServiceType t) => '/pay/${t.id}';
  static const quote = '/pay/quote';
  static const payPin = '/pay/pin';
  static const processing = '/pay/processing';

  /// Reçu d'une opération. `from=history` pour revenir à l'historique.
  static String receipt(String operationId, {bool fromHistory = false}) =>
      '/receipt/$operationId${fromHistory ? '?from=history' : ''}';

  /// Routes accessibles sans session.
  static const public = {splash, invite, requestInvite, login, otp};
}
