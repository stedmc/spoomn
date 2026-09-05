import 'package:spoomn_core/spoomn_core.dart';
import 'package:test/test.dart';

void main() {
  group('LoanTerms maths', () {
    test('flat interest is applied to the principal', () {
      const t = LoanTerms(amount: 500, turns: 5, interestRate: 0.2);
      expect(t.totalRepayable, 600);
      expect(t.totalInterest, 100);
      expect(t.instalment, 120);
    });

    test('zero interest repays exactly the principal', () {
      const t = LoanTerms(amount: 300, turns: 3, interestRate: 0.0);
      expect(t.totalRepayable, 300);
      expect(t.totalInterest, 0);
      expect(t.instalment, 100);
    });

    test('interest is free of floating-point noise', () {
      // 100 * 1.1 evaluates to 110.00000000000001 as a double.
      const t = LoanTerms(amount: 100, turns: 3, interestRate: 0.1);
      expect(t.totalInterest, 10);
      expect(t.totalRepayable, 110);
      expect(t.instalment, 37); // ceil(110 / 3)
    });

    test('single-turn loan repays the whole total at once', () {
      const t = LoanTerms(amount: 250, turns: 1, interestRate: 0.15);
      expect(t.instalment, t.totalRepayable);
      expect(t.instalment, 288); // 250 + round(37.5)
    });
  });

  group('LoanTerms.tryParse', () {
    test('parses a well-formed leg loan object', () {
      final t = LoanTerms.tryParse({
        'amount': 400,
        'turns': 8,
        'interest_rate': 0.125,
      });
      expect(t, isNotNull);
      expect(t!.amount, 400);
      expect(t.turns, 8);
      expect(t.interestRate, 0.125);
    });

    test('returns null for non-map input', () {
      expect(LoanTerms.tryParse(null), isNull);
      expect(LoanTerms.tryParse('loan'), isNull);
      expect(LoanTerms.tryParse(42), isNull);
    });

    test('returns null when amount or turns are non-positive', () {
      expect(LoanTerms.tryParse({'amount': 0, 'turns': 5}), isNull);
      expect(LoanTerms.tryParse({'amount': 100, 'turns': 0}), isNull);
      expect(LoanTerms.tryParse({'amount': -100, 'turns': 5}), isNull);
    });

    test('clamps negative interest to zero', () {
      final t = LoanTerms.tryParse({
        'amount': 100,
        'turns': 2,
        'interest_rate': -0.5,
      });
      expect(t, isNotNull);
      expect(t!.interestRate, 0.0);
      expect(t.totalRepayable, 100);
    });

    test('defaults a missing interest_rate to zero', () {
      final t = LoanTerms.tryParse({'amount': 100, 'turns': 2});
      expect(t, isNotNull);
      expect(t!.interestRate, 0.0);
    });

    test('round-trips through toLeg', () {
      const original = LoanTerms(amount: 750, turns: 6, interestRate: 0.1);
      final parsed = LoanTerms.tryParse(original.toLeg());
      expect(parsed, isNotNull);
      expect(parsed!.amount, original.amount);
      expect(parsed.turns, original.turns);
      expect(parsed.interestRate, original.interestRate);
    });
  });
}
