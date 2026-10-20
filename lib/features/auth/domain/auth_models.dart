import '../../../core/domain/json.dart';

enum OtpChannel {
  sms('SMS', 'SMS'),
  whatsapp('WHATSAPP', 'WhatsApp'),
  email('EMAIL', 'E-mail');

  const OtpChannel(this.api, this.label);
  final String api;
  final String label;
}

/// Défi OTP en cours après `POST /v1/auth/login`.
class LoginChallenge {
  const LoginChallenge({
    required this.challengeId,
    required this.channel,
    required this.maskedDestination,
    required this.expiresAt,
    required this.sendsLeft,
  });

  factory LoginChallenge.fromJson(Json j) => LoginChallenge(
    challengeId: j.str('challengeId'),
    channel: OtpChannel.values.firstWhere((c) => c.api == j.str('channel'), orElse: () => OtpChannel.sms),
    maskedDestination: j.str('maskedDestination'),
    expiresAt: j.date('expiresAt'),
    sendsLeft: j.integer('sendsLeft'),
  );

  final String challengeId;
  final OtpChannel channel;
  final String maskedDestination;
  final DateTime expiresAt;
  final int sendsLeft;
}

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  const AuthState(this.status, {this.hasPin = false});
  const AuthState.unknown() : this(AuthStatus.unknown);
  const AuthState.unauthenticated() : this(AuthStatus.unauthenticated);

  final AuthStatus status;

  /// Faux tant que le code secret n'a pas été créé (flux `setup` obligatoire).
  final bool hasPin;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}
