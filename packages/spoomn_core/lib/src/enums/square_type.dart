enum SquareType {
  go,
  property,
  communityChest,
  tax,
  station,
  chance,
  jail,
  utility,
  freeParking,
  goToJail;

  static SquareType fromJson(String value) =>
      SquareType.values.byName(value);

  String toJson() => name;
}
