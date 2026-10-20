const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

/// « Aujourd'hui à 14:05 », « Hier à 09:12 », « 12 oct. à 18:30 ».
String relativeDate(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(d, n)) return "Aujourd'hui à $hm";
  if (sameDay(d, n.subtract(const Duration(days: 1)))) return 'Hier à $hm';
  return '${d.day} ${_months[d.month - 1]} à $hm';
}
