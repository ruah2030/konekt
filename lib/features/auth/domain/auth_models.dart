import '../../../core/domain/json.dart';
import '../../../core/domain/session.dart';

enum OtpChannel {
  sms('SMS', 'SMS'),
  whatsapp('WHATSAPP', 'WhatsApp'),
  email('EMAIL', 'E-mail');

  const OtpChannel(this.api, this.label);
  final String api;
  final String label;

  static OtpChannel? fromApi(String? v) => values.where((c) => c.api == v).firstOrNull;
}

/// `GET /auth/customer/channels` : ne proposer que les canaux disponibles, présélectionner le défaut.
class ChannelAvailability {
  const ChannelAvailability({required this.available, required this.defaultChannel});
  factory ChannelAvailability.fromJson(Json j) => ChannelAvailability(
    available: {
      for (final c in j.list('channels'))
        if (OtpChannel.fromApi(c['channel'] as String?) != null)
          OtpChannel.fromApi(c['channel'] as String?)!: c['available'] == true,
    },
    defaultChannel: OtpChannel.fromApi(j.strOrNull('defaultChannel')),
  );

  /// Tous les canaux, disponibles ou non (un canal en panne est grisé).
  static const fallback = ChannelAvailability(
    available: {OtpChannel.sms: true, OtpChannel.whatsapp: true, OtpChannel.email: true},
    defaultChannel: OtpChannel.sms,
  );

  final Map<OtpChannel, bool> available;
  final OtpChannel? defaultChannel;

  bool isAvailable(OtpChannel c) => available[c] ?? false;
}

/// Code de connexion envoyé (`POST /auth/customer/login/init`). Garde l'identifiant et les
/// 4 chiffres saisis : `login/confirm` exige les mêmes valeurs.
class LoginChallenge {
  const LoginChallenge({
    required this.cardCustomerId,
    required this.last4Digits,
    required this.channelsUsed,
    required this.maskedContacts,
    required this.expiresAt,
    this.channel,
  });

  factory LoginChallenge.fromInit(
    Json j, {
    required String cardCustomerId,
    required String last4Digits,
    OtpChannel? channel,
    DateTime? now,
  }) => LoginChallenge(
    cardCustomerId: cardCustomerId,
    last4Digits: last4Digits,
    channel: channel,
    channelsUsed: j.strings('channelsUsed').map(OtpChannel.fromApi).whereType<OtpChannel>().toList(),
    maskedContacts: j.strings('maskedContacts'),
    expiresAt: (now ?? DateTime.now()).add(Duration(minutes: j.intOrNull('expiryMinutes') ?? 5)),
  );

  final String cardCustomerId;
  final String last4Digits;

  /// Canal demandé (null = le serveur choisit, éventuellement plusieurs).
  final OtpChannel? channel;
  final List<OtpChannel> channelsUsed;
  final List<String> maskedContacts;
  final DateTime expiresAt;

  /// « +229****456 par SMS ».
  String get destinationLabel {
    final via = channelsUsed.map((c) => c == OtpChannel.email ? 'e-mail' : c.label).join(' et ');
    return [maskedContacts.join(', '), if (via.isNotEmpty) 'par $via'].join(' ');
  }
}

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  const AuthState(this.status, {this.session});
  const AuthState.unknown() : this(AuthStatus.unknown);
  const AuthState.unauthenticated() : this(AuthStatus.unauthenticated);
  const AuthState.authenticated(CardSession session) : this(AuthStatus.authenticated, session: session);

  final AuthStatus status;

  /// Carte de la session (présente si authentifié).
  final CardSession? session;

  /// Faux tant que le code secret n'a pas été créé (création obligatoire avant tout le reste).
  bool get hasPin => session?.hasPin ?? false;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}
