import 'package:spoomn_core/spoomn_core.dart';

/// Draws the next card from a deck, handles reshuffling, and applies its effect.
/// Returns updated state fields to be merged before the DB write.
Future<CardDrawResult> drawAndApply({
  required String deckType, // 'community_chest' or 'chance'
  required String roomId,
  required String playerId,
  required Map<String, dynamic> state,
  required Map<String, dynamic> config,
}) async {
  final isCC = deckType == 'community_chest';
  final defaultDeck = isCC ? Cards.defaultCommunityChest : Cards.defaultChance;
  final customKey = isCC ? 'custom_community_chest' : 'custom_chance';
  final deckKey = isCC ? 'community_chest_deck' : 'chance_deck';
  final indexKey = isCC ? 'community_chest_index' : 'chance_index';

  final customCards = config[customKey] as List<dynamic>?;
  final cards = customCards != null
      ? customCards
          .cast<Map<String, dynamic>>()
          .map((c) => CardDefinition(
                id: c['id'] as String,
                label: c['label'] as String,
                effect: c['effect'] as Map<String, dynamic>,
                keep: (c['keep'] as bool?) ?? false,
              ),)
          .toList()
      : defaultDeck;

  var deck = (state[deckKey] as List<dynamic>).cast<int>();
  var index = state[indexKey] as int;

  // Reshuffle if exhausted
  if (index >= deck.length) {
    deck = Cards.shuffledDeck(cards.length);
    index = 0;
  }

  final cardIndex = deck[index];
  final card = cards[cardIndex];

  // Keep cards (GOOJF, rent protection, etc.) stay with player; not returned to deck yet
  final newIndex = card.keep ? index : index + 1;

  final stateUpdates = <String, dynamic>{
    deckKey: deck,
    indexKey: newIndex,
  };

  final effectUpdates = await _applyEffect(
    card: card,
    roomId: roomId,
    playerId: playerId,
    state: state,
    config: config,
  );

  return CardDrawResult(
    card: card,
    stateUpdates: {...stateUpdates, ...effectUpdates.stateUpdates},
    phaseOverride: effectUpdates.phaseOverride,
    logPayload: {'card_id': card.id, 'label': card.label, 'deck': deckType, 'effect': card.effect},
  );
}

Future<_EffectResult> _applyEffect({
  required CardDefinition card,
  required String roomId,
  required String playerId,
  required Map<String, dynamic> state,
  required Map<String, dynamic> config,
}) async {
  final effect = card.effect;
  final type = effect['type'] as String;

  final balances = Map<String, dynamic>.from(
    state['balances'] as Map<String, dynamic>,
  );
  final positions = Map<String, dynamic>.from(
    state['board_positions'] as Map<String, dynamic>,
  );
  final currentPos = positions[playerId] as int? ?? 0;
  final goSalary = (config['go_salary'] as int?) ?? 200;

  return switch (type) {
    'move_to' => _effectMoveTo(
        effect, playerId, positions, balances, currentPos, goSalary,),
    'move_relative' => _effectMoveRelative(
        effect, playerId, positions, balances, currentPos, goSalary,),
    'move_to_nearest' => _effectMoveToNearest(
        effect, playerId, positions, balances, currentPos, goSalary, state,),
    'collect' => _effectCollect(effect, playerId, balances),
    'pay' => _effectPay(effect, playerId, balances, state, config),
    'collect_from_each' =>
      _effectCollectFromEach(effect, playerId, balances, state),
    'pay_each' => _effectPayEach(effect, playerId, balances, state),
    'pay_per_building' =>
      _effectPayPerBuilding(effect, playerId, balances, state, config),
    'go_to_jail' => _effectGoToJail(playerId, positions, state, config),
    'keep_goojf' => _effectKeepGoojf(playerId, state),
    'rent_protection' => _effectRentProtection(card, playerId, state),
    'rent_discount' => _effectRentDiscount(card, playerId, state),
    _ => _EffectResult(stateUpdates: {}),
  };
}

_EffectResult _effectMoveTo(
  Map<String, dynamic> effect,
  String playerId,
  Map<String, dynamic> positions,
  Map<String, dynamic> balances,
  int currentPos,
  int goSalary,
) {
  final target = effect['square'] as int;
  final passedGo = target < currentPos;
  positions[playerId] = target;
  if (passedGo) {
    balances[playerId] = ((balances[playerId] as int?) ?? 0) + goSalary;
  }
  return _EffectResult(stateUpdates: {
    'board_positions': positions,
    'balances': balances,
  },);
}

_EffectResult _effectMoveRelative(
  Map<String, dynamic> effect,
  String playerId,
  Map<String, dynamic> positions,
  Map<String, dynamic> balances,
  int currentPos,
  int goSalary,
) {
  final squares = effect['squares'] as int;
  final newPos = ((currentPos + squares) % Board.boardSize + Board.boardSize) % Board.boardSize;
  // Negative movement never passes Go
  final passedGo = squares > 0 && newPos < currentPos;
  positions[playerId] = newPos;
  if (passedGo) {
    balances[playerId] = ((balances[playerId] as int?) ?? 0) + goSalary;
  }
  return _EffectResult(stateUpdates: {
    'board_positions': positions,
    'balances': balances,
  },);
}

_EffectResult _effectMoveToNearest(
  Map<String, dynamic> effect,
  String playerId,
  Map<String, dynamic> positions,
  Map<String, dynamic> balances,
  int currentPos,
  int goSalary,
  Map<String, dynamic> state,
) {
  final squareType = effect['square_type'] as String;
  final target = squareType == 'station'
      ? Board.nearestStation(currentPos)
      : Board.nearestUtility(currentPos);
  final passedGo = target < currentPos;
  positions[playerId] = target;
  if (passedGo) {
    balances[playerId] = ((balances[playerId] as int?) ?? 0) + goSalary;
  }
  return _EffectResult(
    stateUpdates: {
      'board_positions': positions,
      'balances': balances,
      '_card_rent_multiplier': effect['rent_multiplier'],
    },
  );
}

_EffectResult _effectCollect(
  Map<String, dynamic> effect,
  String playerId,
  Map<String, dynamic> balances,
) {
  final amount = effect['amount'] as int;
  balances[playerId] = ((balances[playerId] as int?) ?? 0) + amount;
  return _EffectResult(stateUpdates: {'balances': balances});
}

_EffectResult _effectPay(
  Map<String, dynamic> effect,
  String playerId,
  Map<String, dynamic> balances,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) {
  final amount = effect['amount'] as int;
  balances[playerId] = ((balances[playerId] as int?) ?? 0) - amount;
  final updates = <String, dynamic>{'balances': balances};
  // Route payment to Free Parking pot if enabled
  if (config['free_parking_jackpot'] as bool? ?? false) {
    updates['free_parking_pot'] =
        ((state['free_parking_pot'] as int?) ?? 0) + amount;
  }
  return _EffectResult(stateUpdates: updates);
}

_EffectResult _effectCollectFromEach(
  Map<String, dynamic> effect,
  String playerId,
  Map<String, dynamic> balances,
  Map<String, dynamic> state,
) {
  final amount = effect['amount'] as int;
  final activePlayers = (state['balances'] as Map<String, dynamic>).keys
      .where((id) => id != playerId)
      .toList();
  for (final otherId in activePlayers) {
    balances[otherId] = ((balances[otherId] as int?) ?? 0) - amount;
  }
  balances[playerId] =
      ((balances[playerId] as int?) ?? 0) + amount * activePlayers.length;
  return _EffectResult(stateUpdates: {'balances': balances});
}

_EffectResult _effectPayEach(
  Map<String, dynamic> effect,
  String playerId,
  Map<String, dynamic> balances,
  Map<String, dynamic> state,
) {
  final amount = effect['amount'] as int;
  final activePlayers = (state['balances'] as Map<String, dynamic>).keys
      .where((id) => id != playerId)
      .toList();
  for (final otherId in activePlayers) {
    balances[otherId] = ((balances[otherId] as int?) ?? 0) + amount;
  }
  balances[playerId] =
      ((balances[playerId] as int?) ?? 0) - amount * activePlayers.length;
  return _EffectResult(stateUpdates: {'balances': balances});
}

_EffectResult _effectPayPerBuilding(
  Map<String, dynamic> effect,
  String playerId,
  Map<String, dynamic> balances,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) {
  final houseAmount = effect['house_amount'] as int;
  final hotelAmount = effect['hotel_amount'] as int;

  final ownership = state['property_ownership'] as Map<String, dynamic>;
  final houses = state['houses'] as Map<String, dynamic>;
  final hotels = state['hotels'] as Map<String, dynamic>;

  var totalHouses = 0;
  var totalHotels = 0;

  for (final entry in ownership.entries) {
    if (entry.value == playerId) {
      final idx = entry.key;
      if (hotels[idx] == true) {
        totalHotels++;
      } else {
        totalHouses += (houses[idx] as int?) ?? 0;
      }
    }
  }

  final total = totalHouses * houseAmount + totalHotels * hotelAmount;
  balances[playerId] = ((balances[playerId] as int?) ?? 0) - total;

  final updates = <String, dynamic>{'balances': balances};
  if (config['free_parking_jackpot'] as bool? ?? false) {
    updates['free_parking_pot'] =
        ((state['free_parking_pot'] as int?) ?? 0) + total;
  }
  return _EffectResult(stateUpdates: updates);
}

_EffectResult _effectGoToJail(
  String playerId,
  Map<String, dynamic> positions,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) {
  positions[playerId] = Board.jailSquare;
  final jailStatus = Map<String, dynamic>.from(
    state['jail_status'] as Map<String, dynamic>,
  );
  jailStatus[playerId] = {
    'in_jail': true,
    'is_jailbreaking': false,
    'turns_in_jail': 0,
    'mandatory_turns_remaining': 0,
    'catch_count': 0,
    'effective_fine': (config['jail_fine'] as int?) ?? 50,
    'has_card': false,
  };
  return _EffectResult(
    stateUpdates: {
      'board_positions': positions,
      'jail_status': jailStatus,
      'consecutive_doubles': 0,
    },
    phaseOverride: 'trade', // jail card ends action phase; player still ends turn
  );
}

_EffectResult _effectKeepGoojf(
  String playerId,
  Map<String, dynamic> state,
) {
  final cards = Map<String, dynamic>.from(
    state['get_out_of_jail_cards'] as Map<String, dynamic>,
  );
  cards[playerId] = ((cards[playerId] as int?) ?? 0) + 1;

  final jailStatus = Map<String, dynamic>.from(
    state['jail_status'] as Map<String, dynamic>,
  );
  final playerStatus =
      Map<String, dynamic>.from(jailStatus[playerId] as Map<String, dynamic>? ?? {});
  playerStatus['has_card'] = true;
  jailStatus[playerId] = playerStatus;

  return _EffectResult(stateUpdates: {
    'get_out_of_jail_cards': cards,
    'jail_status': jailStatus,
  },);
}

_EffectResult _effectRentProtection(
  CardDefinition card,
  String playerId,
  Map<String, dynamic> state,
) {
  final modifiers = Map<String, dynamic>.from(
    state['rent_modifiers'] as Map<String, dynamic>,
  );
  final playerMods = Map<String, dynamic>.from(
    (modifiers[playerId] as Map<String, dynamic>?) ?? {'protections': [], 'discounts': []},
  );
  final protections = List<dynamic>.from(playerMods['protections'] as List? ?? []);
  protections.add({...card.effect, 'source_card_id': card.id});
  playerMods['protections'] = protections;
  modifiers[playerId] = playerMods;
  return _EffectResult(stateUpdates: {'rent_modifiers': modifiers});
}

_EffectResult _effectRentDiscount(
  CardDefinition card,
  String playerId,
  Map<String, dynamic> state,
) {
  final modifiers = Map<String, dynamic>.from(
    state['rent_modifiers'] as Map<String, dynamic>,
  );
  final playerMods = Map<String, dynamic>.from(
    (modifiers[playerId] as Map<String, dynamic>?) ?? {'protections': [], 'discounts': []},
  );
  final discounts = List<dynamic>.from(playerMods['discounts'] as List? ?? []);
  discounts.add({...card.effect, 'source_card_id': card.id});
  playerMods['discounts'] = discounts;
  modifiers[playerId] = playerMods;
  return _EffectResult(stateUpdates: {'rent_modifiers': modifiers});
}

class CardDrawResult {
  const CardDrawResult({
    required this.card,
    required this.stateUpdates,
    required this.logPayload,
    this.phaseOverride,
  });

  final CardDefinition card;
  final Map<String, dynamic> stateUpdates;
  final Map<String, dynamic> logPayload;
  final String? phaseOverride;
}

class _EffectResult {
  const _EffectResult({required this.stateUpdates, this.phaseOverride});

  final Map<String, dynamic> stateUpdates;
  final String? phaseOverride;
}
