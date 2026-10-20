import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/pin_repository.dart';

/// Statut du code secret (existence, essais restants, verrouillage).
final pinStatusProvider = FutureProvider.autoDispose<PinStatus>((ref) => ref.watch(pinRepositoryProvider).status());
