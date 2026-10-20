import 'package:intl/intl.dart';

const _nbsp = ' ';
final _fr = NumberFormat.decimalPattern('fr_FR');

/// `152400` → `152 400` (espaces insécables).
String formatNumber(num n) => _fr.format(n.round()).replaceAll(' ', _nbsp).replaceAll(' ', _nbsp);

/// `152400` → `152 400 FCFA`.
String formatFcfa(num n) => '${formatNumber(n)}${_nbsp}FCFA';

/// Montant signé : `+ 100 000 FCFA` / `− 50 440 FCFA` (vrai signe moins).
String formatSignedFcfa(num n) => '${n > 0 ? '+' : '−'}$_nbsp${formatFcfa(n.abs())}';

/// Extrait un entier d'une saisie libre (`25 000` → 25000).
int? parseAmount(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}
