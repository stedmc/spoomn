class CardDefinition {
  const CardDefinition({
    required this.id,
    required this.label,
    required this.effect,
    this.keep = false,
  });

  final String id;
  final String label;
  final Map<String, dynamic> effect;
  final bool keep;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'effect': effect,
        'keep': keep,
      };
}

class Cards {
  static const List<CardDefinition> defaultCommunityChest = [
    CardDefinition(id: 'cc_00', label: 'Advance to Go. Collect \u00a3200.',
        effect: {'type': 'move_to', 'square': 0}),
    CardDefinition(id: 'cc_01', label: 'Bank error in your favour. Collect \u00a3200.',
        effect: {'type': 'collect', 'amount': 200}),
    CardDefinition(id: 'cc_02', label: "Doctor's fees. Pay \u00a350.",
        effect: {'type': 'pay', 'amount': 50}),
    CardDefinition(id: 'cc_03', label: 'From sale of stock you get \u00a350.',
        effect: {'type': 'collect', 'amount': 50}),
    CardDefinition(id: 'cc_04', label: 'Get Out of Jail Free. Keep this card until needed or sold.',
        effect: {'type': 'keep_goojf'}, keep: true),
    CardDefinition(id: 'cc_05', label: 'Go to Jail. Go directly to Jail. Do not pass Go. Do not collect \u00a3200.',
        effect: {'type': 'go_to_jail'}),
    CardDefinition(id: 'cc_06', label: 'Grand Opera Night. Collect \u00a350 from every player.',
        effect: {'type': 'collect_from_each', 'amount': 50}),
    CardDefinition(id: 'cc_07', label: 'Holiday Fund matures. Receive \u00a3100.',
        effect: {'type': 'collect', 'amount': 100}),
    CardDefinition(id: 'cc_08', label: 'Income tax refund. Collect \u00a320.',
        effect: {'type': 'collect', 'amount': 20}),
    CardDefinition(id: 'cc_09', label: 'It is your birthday! Collect \u00a310 from every player.',
        effect: {'type': 'collect_from_each', 'amount': 10}),
    CardDefinition(id: 'cc_10', label: 'Life insurance matures. Collect \u00a3100.',
        effect: {'type': 'collect', 'amount': 100}),
    CardDefinition(id: 'cc_11', label: 'Pay hospital fees of \u00a3100.',
        effect: {'type': 'pay', 'amount': 100}),
    CardDefinition(id: 'cc_12', label: 'Pay school fees of \u00a3150.',
        effect: {'type': 'pay', 'amount': 150}),
    CardDefinition(id: 'cc_13', label: 'Receive consultancy fee. Collect \u00a325.',
        effect: {'type': 'collect', 'amount': 25}),
    CardDefinition(id: 'cc_14', label: 'You are assessed for street repairs. Pay \u00a340 per house and \u00a3115 per hotel.',
        effect: {'type': 'pay_per_building', 'house_amount': 40, 'hotel_amount': 115}),
    CardDefinition(id: 'cc_15', label: 'You have won second prize in a beauty contest. Collect \u00a310.',
        effect: {'type': 'collect', 'amount': 10}),
  ];

  static const List<CardDefinition> defaultChance = [
    CardDefinition(id: 'ch_00', label: 'Advance to Go. Collect \u00a3200.',
        effect: {'type': 'move_to', 'square': 0}),
    CardDefinition(id: 'ch_01', label: 'Advance to Trafalgar Square. If you pass Go, collect \u00a3200.',
        effect: {'type': 'move_to', 'square': 24}),
    CardDefinition(id: 'ch_02', label: 'Advance to Mayfair.',
        effect: {'type': 'move_to', 'square': 39}),
    CardDefinition(id: 'ch_03', label: 'Advance to the nearest Station. If owned, pay double the normal rent.',
        effect: {'type': 'move_to_nearest', 'square_type': 'station', 'rent_multiplier': 2.0}),
    CardDefinition(id: 'ch_04', label: 'Advance to the nearest Station. If owned, pay double the normal rent.',
        effect: {'type': 'move_to_nearest', 'square_type': 'station', 'rent_multiplier': 2.0}),
    CardDefinition(id: 'ch_05', label: 'Advance to the nearest Utility. If owned, throw dice and pay owner 10 times the amount thrown.',
        effect: {'type': 'move_to_nearest', 'square_type': 'utility', 'rent_multiplier': 10.0}),
    CardDefinition(id: 'ch_06', label: 'Bank pays you a dividend of \u00a350.',
        effect: {'type': 'collect', 'amount': 50}),
    CardDefinition(id: 'ch_07', label: 'Get Out of Jail Free. Keep this card until needed or sold.',
        effect: {'type': 'keep_goojf'}, keep: true),
    CardDefinition(id: 'ch_08', label: 'Go back three spaces.',
        effect: {'type': 'move_relative', 'squares': -3}),
    CardDefinition(id: 'ch_09', label: 'Go to Jail. Go directly to Jail. Do not pass Go. Do not collect \u00a3200.',
        effect: {'type': 'go_to_jail'}),
    CardDefinition(id: 'ch_10', label: 'Make general repairs on all your property. Pay \u00a325 per house and \u00a3100 per hotel.',
        effect: {'type': 'pay_per_building', 'house_amount': 25, 'hotel_amount': 100}),
    CardDefinition(id: 'ch_11', label: 'Pay poor tax of \u00a315.',
        effect: {'type': 'pay', 'amount': 15}),
    CardDefinition(id: 'ch_12', label: "Take a trip to King's Cross Station. If you pass Go, collect \u00a3200.",
        effect: {'type': 'move_to', 'square': 5}),
    CardDefinition(id: 'ch_13', label: 'Take a walk on the Old Kent Road. If you pass Go, collect \u00a3200.',
        effect: {'type': 'move_to', 'square': 1}),
    CardDefinition(id: 'ch_14', label: 'You have been elected Chairman of the Board. Pay each player \u00a350.',
        effect: {'type': 'pay_each', 'amount': 50}),
    CardDefinition(id: 'ch_15', label: 'Your building loan matures. Collect \u00a3150.',
        effect: {'type': 'collect', 'amount': 150}),
  ];

  static List<int> shuffledDeck(int size) {
    final indices = List<int>.generate(size, (i) => i);
    indices.shuffle();
    return indices;
  }
}
