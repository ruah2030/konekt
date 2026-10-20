import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Horloge partagée (1 s) pour tous les compte-à-rebours : OTP, devis,
/// affichage sécurisé, verrouillage PIN, rotation des publicités.
/// Toujours calculer `expiresAt - now` plutôt que décrémenter un compteur.
final tickerProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

/// Heure courante (mise à jour chaque seconde).
final nowProvider = Provider.autoDispose<DateTime>((ref) => ref.watch(tickerProvider).value ?? DateTime.now());
