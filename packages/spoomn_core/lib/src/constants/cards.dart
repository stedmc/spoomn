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
    CardDefinition(id: 'cc_00', label: 'Advance to Go',                    effect: {'type': 'move_to',          'square': 0}),
    CardDefinition(id: 'cc_01', label: 'Bank error in your favour',        effect: {'type': 'collect',          'amount': 200}),
    CardDefinition(id: 'cc_02', label: "Doctor's fee",                     effect: {'type': 'pay',              'amount': 50}),
    CardDefinition(id: 'cc_03', label: 'From sale of stock',               effect: {'type': 'collect',          'amount': 50}),
    CardDefinition(id: 'cc_04', label: 'Get Out of Jail Free',             effect: {'type': 'keep_goojf'},                     keep: true),
    CardDefinition(id: 'cc_05', label: 'Go to Jail',                       effect: {'type': 'go_to_jail'}),
    CardDefinition(id: 'cc_06', label: 'Grand Opera Night',                effect: {'type': 'collect_from_each','amount': 50}),
    CardDefinition(id: 'cc_07', label: 'Holiday fund matures',             effect: {'type': 'collect',          'amount': 100}),
    CardDefinition(id: 'cc_08', label: 'Income tax refund',                effect: {'type': 'collect',          'amount': 20}),
    CardDefinition(id: 'cc_09', label: 'It is your birthday',              effect: {'type': 'collect_from_each','amount': 10}),
    CardDefinition(id: 'cc_10', label: 'Life insurance matures',           effect: {'type': 'collect',          'amount': 100}),
    CardDefinition(id: 'cc_11', label: 'Pay hospital fees',                effect: {'type': 'pay',              'amount': 100}),
    CardDefinition(id: 'cc_12', label: 'Pay school fees',                  effect: {'type': 'pay',              'amount': 50}),
    CardDefinition(id: 'cc_13', label: 'Receive consultancy fee',          effect: {'type': 'collect',          'amount': 25}),
    CardDefinition(id: 'cc_14', label: 'Street repairs',                   effect: {'type': 'pay_per_building', 'house_amount': 40, 'hotel_amount': 115}),
    CardDefinition(id: 'cc_15', label: 'You inherit \u00a3100',            effect: {'type': 'collect',          'amount': 100}),
  ];

  static const List<CardDefinition> defaultChance = [
    CardDefinition(id: 'ch_00', label: 'Advance to Go',                         effect: {'type': 'move_to',          'square': 0}),
    CardDefinition(id: 'ch_01', label: 'Advance to Trafalgar Square',            effect: {'type': 'move_to',          'square': 24}),
    CardDefinition(id: 'ch_02', label: 'Advance to Pall Mall',                   effect: {'type': 'move_to',          'square': 11}),
    CardDefinition(id: 'ch_03', label: 'Advance to nearest station (\u00d72)',   effect: {'type': 'move_to_nearest',  'square_type': 'station', 'rent_multiplier': 2.0}),
    CardDefinition(id: 'ch_04', label: 'Advance to nearest station (\u00d72)',   effect: {'type': 'move_to_nearest',  'square_type': 'station', 'rent_multiplier': 2.0}),
    CardDefinition(id: 'ch_05', label: 'Advance to nearest utility (\u00d710)',  effect: {'type': 'move_to_nearest',  'square_type': 'utility',  'rent_multiplier': 10.0}),
    CardDefinition(id: 'ch_06', label: 'Bank pays dividend',                      effect: {'type': 'collect',          'amount': 50}),
    CardDefinition(id: 'ch_07', label: 'Get Out of Jail Free',                   effect: {'type': 'keep_goojf'},                     keep: true),
    CardDefinition(id: 'ch_08', label: 'Go back 3 spaces',                       effect: {'type': 'move_relative',    'squares': -3}),
    CardDefinition(id: 'ch_09', label: 'Go to Jail',                              effect: {'type': 'go_to_jail'}),
    CardDefinition(id: 'ch_10', label: 'Make general repairs',                    effect: {'type': 'pay_per_building', 'house_amount': 25, 'hotel_amount': 100}),
    CardDefinition(id: 'ch_11', label: 'Pay poor tax',                            effect: {'type': 'pay',              'amount': 15}),
    CardDefinition(id: 'ch_12', label: "Take trip to King's Cross",               effect: {'type': 'move_to',          'square': 5}),
    CardDefinition(id: 'ch_13', label: 'Take a walk on the Old Kent Road',        effect: {'type': 'move_to',          'square': 1}),
    CardDefinition(id: 'ch_14', label: 'Elected chairman of the board',           effect: {'type': 'pay_each',         'amount': 50}),
    CardDefinition(id: 'ch_15', label: 'Building loan matures',                   effect: {'type': 'collect',          'amount': 150}),
  ];

  static List<int> shuffledDeck(int size) {
    final indices = List<int>.generate(size, (i) => i);
    indices.shuffle();
    return indices;
  }
}
