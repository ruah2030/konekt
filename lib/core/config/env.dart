/// Configuration injectée au build via `--dart-define-from-file=env/<flavor>.json`.
abstract final class Env {
  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api.dev.konekt.bj');

  /// Tant que le backend n'est pas disponible, les appels HTTP sont servis
  /// par le faux backend en mémoire (`core/network/fake`).
  static const useFakeApi = bool.fromEnvironment('USE_FAKE_API', defaultValue: true);

  static const logNetwork = bool.fromEnvironment('LOG_NETWORK', defaultValue: false);

  static bool get isProd => flavor == 'prod';
}
