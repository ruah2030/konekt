/// Durée restante au format `m:ss` (arrondi supérieur, jamais négatif).
String mmss(Duration d) {
  final s = d.isNegative ? 0 : (d.inMilliseconds / 1000).ceil();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

Duration remaining(DateTime expiresAt, DateTime now) => expiresAt.difference(now);
