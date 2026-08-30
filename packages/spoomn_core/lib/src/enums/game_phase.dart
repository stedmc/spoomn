enum GamePhase {
  roll,
  move,
  action,
  trade,
  auction,
  bankruptcyNegotiation,
  finished;

  static GamePhase fromJson(String value) =>
      GamePhase.values.byName(value);

  String toJson() => name;
}
