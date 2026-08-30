enum PlayMode {
  realtime,
  async;

  static PlayMode fromJson(String value) =>
      PlayMode.values.byName(value);

  String toJson() => name;
}
