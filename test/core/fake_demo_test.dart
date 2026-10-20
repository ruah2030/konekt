import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/fake/fake_db.dart';

void main() {
  test('le jeu de démo contient un mois d’historique', () {
    final db = FakeDb.demo();
    expect(db.transactions.length, greaterThan(20));
    expect(db.operations.length, greaterThan(15));
    expect(db.hasPin, isFalse);
  });

  test('en démo, une session d’un lancement précédent reste valide jusqu’à révocation', () {
    final before = FakeDb.demo().issueTokens();
    final db = FakeDb.demo(savedPin: '482915');
    expect(db.hasPin, isTrue);
    expect(db.isValidAccessToken(before.access), isTrue);
    expect(db.consumeRefreshToken(before.refresh), isTrue);
    expect(db.consumeRefreshToken(before.refresh), isFalse);
    db.revokeAccessToken(before.access);
    expect(db.isValidAccessToken(before.access), isFalse);
  });

  test('hors démo, seuls les jetons émis sont valides', () {
    final t = FakeDb().issueTokens();
    expect(FakeDb().isValidAccessToken(t.access), isFalse);
  });

  test('le code secret est transmis pour être conservé', () {
    String? saved;
    final db = FakeDb.demo(onPinChanged: (p) => saved = p)..pin = '739204';
    expect(saved, '739204');
    expect(db.pin, '739204');
  });
}
