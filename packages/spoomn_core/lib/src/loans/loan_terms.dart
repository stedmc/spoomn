/// The terms of a player-to-player loan struck inside a trade.
///
/// The lender transfers [amount] to the borrower when the trade is accepted.
/// The borrower then repays [totalRepayable] (principal plus flat interest) in
/// equal [instalment]s, one collected on each of the borrower's turns, for
/// [turns] turns.
class LoanTerms {
  const LoanTerms({
    required this.amount,
    required this.turns,
    required this.interestRate,
  });

  /// Principal handed to the borrower up front.
  final int amount;

  /// Repayment length, measured in the borrower's turns.
  final int turns;

  /// Flat interest rate applied to the principal (0.1 == 10%).
  final double interestRate;

  /// Interest charged on the principal, rounded to the nearest pound. Computed
  /// separately from [totalRepayable] to keep it clear of floating-point noise
  /// (e.g. `100 * 1.1` is not exactly `110`).
  int get totalInterest => (amount * interestRate).round();

  /// Total the borrower repays over the life of the loan.
  int get totalRepayable => amount + totalInterest;

  /// Amount collected from the borrower on each of their turns, rounded up.
  /// The final instalment is implicitly smaller when the total does not divide
  /// evenly (the repayment plan stops once the balance is cleared).
  int get instalment => (totalRepayable + turns - 1) ~/ turns;

  bool get isValid => amount > 0 && turns > 0 && interestRate >= 0;

  /// Parse a trade-leg `loan` object. Returns `null` when the value is absent,
  /// the wrong shape, or describes an invalid loan (non-positive amount/turns).
  static LoanTerms? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final amount = (map['amount'] as num?)?.round() ?? 0;
    final turns = (map['turns'] as num?)?.round() ?? 0;
    var rate = (map['interest_rate'] as num?)?.toDouble() ?? 0.0;
    if (rate < 0) rate = 0.0;
    final terms = LoanTerms(amount: amount, turns: turns, interestRate: rate);
    return terms.isValid ? terms : null;
  }

  /// Serialise back to the trade-leg `loan` object shape.
  Map<String, dynamic> toLeg() => {
        'amount': amount,
        'turns': turns,
        'interest_rate': interestRate,
      };

  @override
  String toString() =>
      'LoanTerms(amount: $amount, turns: $turns, interestRate: $interestRate)';
}
