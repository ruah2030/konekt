import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_prefs.dart';
import '../domain/invite_code.dart';

/// Source des liens qui ouvrent l'app : lien de lancement + liens reçus pendant que l'app tourne.
abstract interface class InviteLinkSource {
  /// Lien qui a lancé l'app (démarrage à froid), s'il y en a un.
  Future<Uri?> initialLink();

  /// Liens reçus ensuite (l'implémentation peut aussi y renvoyer le lien initial : il est dédoublonné).
  Stream<Uri> get links;
}

/// Source fixe : tests, et plateformes sans liens (hôte de test, web, bureau).
class StaticInviteLinkSource implements InviteLinkSource {
  StaticInviteLinkSource({this._initial, this._links});

  final Uri? _initial;
  final Stream<Uri>? _links;

  @override
  Future<Uri?> initialLink() async => _initial;

  @override
  Stream<Uri> get links => _links ?? const Stream<Uri>.empty();
}

/// Liens Android (App Links + schéma `konekt`) et iOS (liens universels + schéma) via `app_links`.
class AppLinksInviteLinkSource implements InviteLinkSource {
  final _appLinks = AppLinks();

  @override
  Future<Uri?> initialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get links => _appLinks.uriLinkStream;
}

/// Code d'invitation reçu par un lien. [atLaunch] : le lien a lancé l'app (pas de toast).
/// Égalité par identité : deux réceptions du même code sont deux événements.
@immutable
class ReceivedInviteCode {
  const ReceivedInviteCode(this.code, {required this.atLaunch});
  final String code;
  final bool atLaunch;

  @override
  String toString() => 'ReceivedInviteCode($code, atLaunch: $atLaunch)';
}

/// Lit le code d'invitation des liens `https://konekt.app/invite?code=…` et `konekt://invite?code=…`
/// (guide Partie 3, écran 2 : « code d'invitation lu depuis le lien d'installation »), puis l'enregistre
/// dans les préférences : il partira dans `login/confirm` comme `merchantReferralCode`.
///
/// Ne touche jamais à la session : un code reçu alors que la personne est connectée sert à la prochaine connexion.
class InviteLinkService {
  InviteLinkService({required this._source, required this._prefs});

  final InviteLinkSource _source;
  final AppPrefs _prefs;
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  static const webHost = 'konekt.app';
  static const scheme = 'konekt';
  static const invitePath = 'invite';

  /// Code valide porté par [uri], sinon `null` (autre lien, code absent, invalide ou trop long).
  static String? parse(Uri uri) {
    final s = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    final bool isInvite;
    if (s == 'https') {
      isInvite = (host == webHost || host == 'www.$webHost') && segments.length == 1 && segments.first == invitePath;
    } else if (s == scheme) {
      // konekt://invite?code=… (hôte « invite ») ou konekt:///invite?code=…
      isInvite =
          (host == invitePath && segments.isEmpty) ||
          (host.isEmpty && segments.length == 1 && segments.first == invitePath);
    } else {
      isInvite = false;
    }
    if (!isInvite) return null;
    final raw = uri.queryParameters['code']?.trim();
    if (raw == null || raw.isEmpty || raw.length > InviteCode.maxLength) return null;
    final code = raw.toUpperCase();
    return InviteCode.isValid(code) ? code : null;
  }

  /// Traite le lien initial puis écoute les suivants. [onCode] est appelé après l'enregistrement du code.
  Future<void> start(void Function(ReceivedInviteCode received) onCode) async {
    if (_started) return;
    _started = true;
    Uri? initial;
    try {
      initial = await _source.initialLink();
    } catch (e) {
      debugPrint('[Konekt] Lien de lancement illisible : $e');
    }
    if (initial != null) await _handle(initial, atLaunch: true, onCode: onCode);

    // `app_links` renvoie aussi le lien de lancement dans le flux : on ne le traite qu'une fois.
    var skipInitial = initial;
    try {
      _sub = _source.links.listen((uri) {
        if (skipInitial != null && uri == skipInitial) {
          skipInitial = null;
          return;
        }
        skipInitial = null;
        unawaited(_handle(uri, atLaunch: false, onCode: onCode));
      }, onError: (Object e) => debugPrint('[Konekt] Lien illisible : $e'));
    } catch (e) {
      debugPrint('[Konekt] Liens indisponibles : $e');
    }
  }

  Future<void> _handle(Uri uri, {required bool atLaunch, required void Function(ReceivedInviteCode) onCode}) async {
    final code = parse(uri);
    if (code == null) return;
    await _prefs.setReferralCode(code);
    onCode(ReceivedInviteCode(code, atLaunch: atLaunch));
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}

/// Source des liens. Surchargée dans les tests ; aucun lien hors Android / iOS (y compris sous `flutter test`).
final inviteLinkSourceProvider = Provider<InviteLinkSource>((ref) {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) return AppLinksInviteLinkSource();
  return StaticInviteLinkSource();
});

/// Dernier code reçu par un lien (`null` tant qu'aucun). Le service démarre à la première lecture
/// (widget racine `InviteLinkListener`) et vit autant que l'app.
final inviteLinkProvider = NotifierProvider<InviteLinkController, ReceivedInviteCode?>(InviteLinkController.new);

class InviteLinkController extends Notifier<ReceivedInviteCode?> {
  @override
  ReceivedInviteCode? build() {
    final service = InviteLinkService(source: ref.watch(inviteLinkSourceProvider), prefs: ref.watch(appPrefsProvider));
    ref.onDispose(service.dispose);
    unawaited(
      service.start((received) {
        if (ref.mounted) state = received;
      }),
    );
    return null;
  }
}
