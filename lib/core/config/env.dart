/// Configuration injectée au build via `--dart-define-from-file=env/<flavor>.json`.
abstract final class Env {
  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  /// Hôte de l'API CardConnect v2 (sans `/api/v1`).
  static const apiHost = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dev-api.card-connect.bestcash.me',
  );

  /// Toutes les routes sont préfixées par `/api/v1` (guide d'intégration §1.2).
  static String get apiBaseUrl => '$apiHost/api/v1';

  /// Identifiant de l'application, fourni par l'équipe backend (`BESTCASH_SECURE_CARD_APP_ID`).
  static const appId = String.fromEnvironment('KONEKT_APP_ID', defaultValue: 'konekt-dev');

  /// Tant que le backend n'est pas branché, les appels HTTP sont servis
  /// par le faux backend en mémoire (`core/network/fake`), qui suit le même contrat.
  static const useFakeApi = bool.fromEnvironment('USE_FAKE_API', defaultValue: true);

  static const logNetwork = bool.fromEnvironment('LOG_NETWORK', defaultValue: false);

  static bool get isProd => flavor == 'prod';
}
