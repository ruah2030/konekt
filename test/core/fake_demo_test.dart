import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/transaction.dart';
import 'package:konekt/core/network/fake/fake_db.dart';

void main() {
  test('le jeu de démo contient un mois d’historique au format émetteur', () {
    final db = FakeDb.demo();
    expect(db.issuerTransactions.length, greaterThan(20));
    expect(db.operations.length, greaterThan(15));
    expect(db.hasPin, isFalse);
    expect(db.issuerTransactions.first['transactionDate'], matches(RegExp(r'^\d{2}-[A-Z]{3}-\d{4}$')));
  });

  test('le sens des mouvements se déduit du solde courant', () {
    final txs = CardTransaction.listFromIssuer(FakeDb().issuerTransactions);
    expect(txs.first.description, 'Transfert sortant');
    expect(txs.first.amount, -50440);
    expect(txs[2].amount, 100000);
    expect(txs.first.balanceAfter, 152400);
  });

  test('en démo, une session d’un lancement précédent reste valide jusqu’à révocation', () {
    final before = FakeDb.demo().issueTokens();
    final db = FakeDb.demo(savedPin: '482915');
    expect(db.hasPin, isTrue);
    expect(db.isValidSessionToken(before.session), isTrue);
    expect(db.consumeRefreshToken(before.refresh), isTrue);
    expect(db.consumeRefreshToken(before.refresh), isFalse);
    db.revokeSessionToken(before.session);
    expect(db.isValidSessionToken(before.session), isFalse);
  });

  test('hors démo, seuls les jetons émis sont valides', () {
    final t = FakeDb().issueTokens();
    expect(FakeDb().isValidSessionToken(t.session), isFalse);
  });

  test('le code secret est transmis pour être conservé', () {
    String? saved;
    final db = FakeDb.demo(onPinChanged: (p) => saved = p)..pin = '739204';
    expect(saved, '739204');
    expect(db.pin, '739204');
  });
}
