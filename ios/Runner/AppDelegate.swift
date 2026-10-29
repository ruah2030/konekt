import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KonektScreenSecurity") {
      ScreenSecurity.shared.attach(messenger: registrar.messenger())
    }
  }
}

/// Protection des écrans sensibles (affichage de carte, code secret) — canal `konekt/screen_security`,
/// voir lib/core/security/screen_security.dart.
///
/// iOS ne permet pas d'interdire une capture d'écran. Quand la protection est active :
/// - l'app est recouverte d'un cache dans le sélecteur d'applications (passage en arrière-plan) ;
/// - elle est recouverte pendant un enregistrement ou une recopie d'écran (AirPlay…) ;
/// - une capture d'écran est signalée à Flutter (`screenshotTaken`) pour avertir l'utilisateur.
final class ScreenSecurity: NSObject {
  static let shared = ScreenSecurity()

  private var channel: FlutterMethodChannel?
  private var enabled = false
  private var cover: UIView?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "konekt/screen_security", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "enable":
        self?.setEnabled(true)
        result(nil)
      case "disable":
        self?.setEnabled(false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel

    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(willResignActive),
                       name: UIApplication.willResignActiveNotification, object: nil)
    center.addObserver(self, selector: #selector(didBecomeActive),
                       name: UIApplication.didBecomeActiveNotification, object: nil)
    center.addObserver(self, selector: #selector(captureChanged),
                       name: UIScreen.capturedDidChangeNotification, object: nil)
    center.addObserver(self, selector: #selector(screenshotTaken),
                       name: UIApplication.userDidTakeScreenshotNotification, object: nil)
  }

  private func setEnabled(_ on: Bool) {
    enabled = on
    if on && isCaptured { showCover() } else if !on { removeCover() }
  }

  @objc private func willResignActive() {
    if enabled { showCover() }
  }

  @objc private func didBecomeActive() {
    if !(enabled && isCaptured) { removeCover() }
  }

  @objc private func captureChanged() {
    if enabled && isCaptured { showCover() } else { removeCover() }
  }

  @objc private func screenshotTaken() {
    if enabled { channel?.invokeMethod("screenshotTaken", arguments: nil) }
  }

  private var keyWindow: UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  /// Enregistrement d'écran ou recopie (AirPlay) en cours.
  private var isCaptured: Bool {
    keyWindow?.windowScene?.screen.isCaptured ?? false
  }

  private func showCover() {
    guard cover == nil, let window = keyWindow else { return }
    let view = UIView(frame: window.bounds)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // Bleu nuit Konekt (#140A72) et symbole de la marque.
    view.backgroundColor = UIColor(red: 20 / 255, green: 10 / 255, blue: 114 / 255, alpha: 1)
    if let logo = UIImage(named: "LaunchImage") {
      let image = UIImageView(image: logo)
      image.contentMode = .scaleAspectFit
      image.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
      image.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
      image.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
      view.addSubview(image)
    }
    window.addSubview(view)
    cover = view
  }

  private func removeCover() {
    cover?.removeFromSuperview()
    cover = nil
  }
}
