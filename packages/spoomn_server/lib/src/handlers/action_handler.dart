import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../db/supabase_client.dart';
import '../game/card_engine.dart';
import '../middleware/auth_middleware.dart';
import 'auction_handler.dart' as auction;
import 'building_handler.dart' as building;
import 'mortgage_handler.dart' as mortgage;
import 'stats_handler.dart';
import 'trade_handler.dart' as trade;

Future<Response> handleAction(Request request, String playerId) async {
  final roomId = request.params['roomId']!;
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final action = body['action'] as String?;
  final payload = (body['payload'] as Map<String, dynamic>?) ?? {};

  if (action == null) {
    return errorJson(400, 'MISSING_ACTION', 'action field is required');
  }

  // Load current state
  final roomRow = await supabase
      .from('game_rooms')
      .select()
      .eq('id', roomId)
      .maybeSingle();

  if (roomRow == null) return errorJson(404, 'NOT_FOUND', 'Room not found');
  if (roomRow['status'] != 'active') {
    return errorJson(400, 'ROOM_NOT_ACTIVE', 'Room is not active');
  }

  final stateRow = await supabase
      .from('game_state')
      .select()
      .eq('room_id', roomId)
      .single();

  final configRow = await supabase
      .from('room_configs')
      .select()
      .eq('room_id', roomId)
      .single();

  // Debug mode: allow any authenticated room member to act as another player,
  // but only if that player is actually in the room.
  final debugMode = configRow['debug_mode'] as bool? ?? false;
  String effectivePlayerId = playerId;
  if (debugMode && payload.containsKey('debug_as')) {
    final debugAs = payload['debug_as'] as String?;
    if (debugAs != null) {
      final member = await supabase
          .from('room_players')
          .select('player_id')
          .eq('room_id', roomId)
          .eq('player_id', debugAs)
          .isFilter('left_at', null)
          .maybeSingle();
      if (member != null) effectivePlayerId = debugAs;
    }
  }

  // Dispatch
  return switch (action) {
    'roll_dice'              => _rollDice(roomId, effectivePlayerId, stateRow, configRow, roomRow, payload),
    'buy_property'           => _buyProperty(roomId, effectivePlayerId, stateRow, configRow, payload),
    'decline_property'       => auction.declineProperty(roomId, effectivePlayerId, stateRow, configRow),
    'pay_jail_fine'          => _payJailFine(roomId, effectivePlayerId, stateRow, configRow),
    'use_goojf_card'         => _useGoojfCard(roomId, effectivePlayerId, stateRow, configRow),
    'jailbreak'              => _jailbreak(roomId, effectivePlayerId, stateRow, configRow),
    'end_turn'               => _endTurn(roomId, effectivePlayerId, stateRow, configRow, roomRow),
    'propose_trade'          => trade.proposeTrade(roomId, effectivePlayerId, payload, configRow),
    'accept_trade'           => trade.acceptTrade(roomId, effectivePlayerId, payload),
    'reject_trade'           => trade.rejectTrade(roomId, effectivePlayerId, payload),
    'cancel_trade'           => trade.cancelTrade(roomId, effectivePlayerId, payload),
    'counter_trade'          => trade.counterTrade(roomId, effectivePlayerId, payload, configRow),
    'place_trap'             => _placeTrap(roomId, effectivePlayerId, stateRow, configRow, payload),
    'remove_trap'            => _removeTrap(roomId, effectivePlayerId, payload),
    'bid'                    => auction.submitBid(roomId, effectivePlayerId, stateRow, configRow, payload),
    'pass_bid'               => auction.passBid(roomId, effectivePlayerId, stateRow, configRow),
    'build_house'            => building.buildHouse(roomId, effectivePlayerId, stateRow, configRow, payload).then((r) async {
      if (r.statusCode == 200) await _writeLog(roomId, effectivePlayerId, stateRow['turn_number'] as int, 'build_house', {'square': payload['square']});
      return r;
    }),
    'build_hotel'            => building.buildHotel(roomId, effectivePlayerId, stateRow, configRow, payload).then((r) async {
      if (r.statusCode == 200) await _writeLog(roomId, effectivePlayerId, stateRow['turn_number'] as int, 'build_hotel', {'square': payload['square']});
      return r;
    }),
    'sell_house'             => building.sellHouse(roomId, effectivePlayerId, stateRow, configRow, payload).then((r) async {
      if (r.statusCode == 200) await _writeLog(roomId, effectivePlayerId, stateRow['turn_number'] as int, 'sell_house', {'square': payload['square']});
      return r;
    }),
    'sell_hotel'             => building.sellHotel(roomId, effectivePlayerId, stateRow, configRow, payload).then((r) async {
      if (r.statusCode == 200) await _writeLog(roomId, effectivePlayerId, stateRow['turn_number'] as int, 'sell_hotel', {'square': payload['square']});
      return r;
    }),
    'mortgage_property'      => mortgage.mortgageProperty(roomId, effectivePlayerId, stateRow, configRow, payload).then((r) async {
      if (r.statusCode == 200) await _writeLog(roomId, effectivePlayerId, stateRow['turn_number'] as int, 'mortgage_property', {'square': payload['square']});
      return r;
    }),
    'unmortgage_property'    => mortgage.unmortgageProperty(roomId, effectivePlayerId, stateRow, configRow, payload).then((r) async {
      if (r.statusCode == 200) await _writeLog(roomId, effectivePlayerId, stateRow['turn_number'] as int, 'unmortgage_property', {'square': payload['square']});
      return r;
    }),
    'debug_teleport'         => _debugTeleport(roomId, effectivePlayerId, stateRow, configRow, payload),
    'debug_assign_property'  => _debugAssignProperty(roomId, stateRow, configRow, payload),
    'declare_bankruptcy'     => _declareBankruptcy(roomId, effectivePlayerId, stateRow, configRow, roomRow),
    _                        => Future.value(errorJson(400, 'UNKNOWN_ACTION', 'Unknown action: $action')),
  };
}

// ---------------------------------------------------------------------------
// Roll dice
// ---------------------------------------------------------------------------

Future<Response> _rollDice(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> room,
  Map<String, dynamic> payload,
) async {
  final phase = state['phase'] as String;
  if (phase != 'roll') {
    return errorJson(400, 'INVALID_PHASE', 'Expected phase: roll, got: $phase');
  }
  if (room['current_player_id'] != playerId) {
    return errorJson(403, 'NOT_YOUR_TURN', 'Not your turn');
  }

  final diceCount = (config['dice_count'] as int?) ?? 2;
  final diceSides = (config['dice_sides'] as int?) ?? 6;

  final List<int> roll;
  final debugMode = config['debug_mode'] as bool? ?? false;
  final forcedRaw = payload['forced_roll'];
  if (debugMode && forcedRaw != null) {
    roll = (forcedRaw as List<dynamic>).cast<int>();
  } else {
    final rand = Random.secure();
    roll = List.generate(diceCount, (_) => rand.nextInt(diceSides) + 1);
  }

  final total = roll.fold(0, (a, b) => a + b);
  final isDoubles = diceCount >= 2 && roll.every((d) => d == roll[0]);

  // --- Jail roll path ---
  final jailStatus = state['jail_status'] as Map<String, dynamic>;
  final playerJail =
      Map<String, dynamic>.from(jailStatus[playerId] as Map<String, dynamic>? ?? {});
  final inJail = playerJail['in_jail'] as bool? ?? false;

  if (inJail) {
    return _rollDiceInJail(
        roomId, playerId, state, config, roll, total, isDoubles, playerJail,);
  }

  // --- Normal roll path ---
  final consecutiveDoubles =
      isDoubles ? (state['consecutive_doubles'] as int) + 1 : 0;
  final jailOnN = config['jail_on_consecutive_doubles'] as int?;

  if (isDoubles && jailOnN != null && consecutiveDoubles >= jailOnN) {
    await _sendToJail(roomId, playerId, state, consecutiveDoubles: 0);
    await _writeLog(roomId, playerId, state['turn_number'] as int, 'roll_dice',
        {'roll': roll, 'sent_to_jail': true},);
    return okJson({'roll': roll, 'sent_to_jail': true});
  }

  final positions = Map<String, dynamic>.from(
      state['board_positions'] as Map<String, dynamic>,);
  final currentPos = (positions[playerId] as int?) ?? 0;
  final newPos = (currentPos + total) % Board.boardSize;
  final passedGo = newPos < currentPos;
  positions[playerId] = newPos;

  final rentModifiers = _decrementRollProtections(
    Map<String, dynamic>.from(state['rent_modifiers'] as Map<String, dynamic>? ?? {}),
    playerId,
  );

  final updates = <String, dynamic>{
    'dice_roll': roll,
    'consecutive_doubles': consecutiveDoubles,
    'board_positions': positions,
    'rent_modifiers': rentModifiers,
    'updated_at': DateTime.now().toIso8601String(),
  };

  if (passedGo) {
    final goSalary = (config['go_salary'] as int?) ?? 200;
    final goBonus = newPos == Board.goSquare
        ? (config['go_landing_bonus'] as int? ?? 0)
        : 0;
    final balances = Map<String, dynamic>.from(
        state['balances'] as Map<String, dynamic>,);
    balances[playerId] =
        ((balances[playerId] as int?) ?? 0) + goSalary + goBonus;
    updates['balances'] = balances;
  }

  // Carry updated positions and balances into landing so card effects
  // (e.g. "go back 3 spaces") operate on the post-roll position, not the
  // position before the roll.
  // Note: stateForLanding keeps the pre-decrement rent_modifiers so that
  // _resolveSquareLanding can check immunity against the original roll count.
  final stateForLanding = Map<String, dynamic>.from(state)
    ..['board_positions'] = positions;
  if (updates.containsKey('balances')) {
    stateForLanding['balances'] = updates['balances'];
  }

  await supabase.from('game_state').update(updates).eq('room_id', roomId);

  await _writeLog(roomId, playerId, state['turn_number'] as int, 'roll_dice',
      {'roll': roll, 'new_position': newPos, 'passed_go': passedGo},);

  // Resolve landing square effect and set pending_action
  await _resolveSquareLanding(roomId, playerId, newPos, stateForLanding, config);

  return okJson({'roll': roll, 'new_position': newPos, 'passed_go': passedGo});
}

// ---------------------------------------------------------------------------
// Buy property
// ---------------------------------------------------------------------------

Future<Response> _buyProperty(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  final positions = state['board_positions'] as Map<String, dynamic>;
  final squareIndex = (positions[playerId] as int?) ?? 0;
  final square = Board.squares[squareIndex];

  if (square.price == null) {
    return errorJson(400, 'RULE_VIOLATION', 'Square is not purchasable');
  }

  final ownership = state['property_ownership'] as Map<String, dynamic>;
  if (ownership.containsKey('$squareIndex')) {
    return errorJson(400, 'RULE_VIOLATION', 'Property already owned');
  }

  final balances = Map<String, dynamic>.from(
    state['balances'] as Map<String, dynamic>,
  );
  final balance = (balances[playerId] as int?) ?? 0;
  if (balance < square.price!) {
    return errorJson(400, 'INSUFFICIENT_FUNDS', 'Not enough money to buy');
  }

  balances[playerId] = balance - square.price!;
  final newOwnership = Map<String, dynamic>.from(ownership);
  newOwnership['$squareIndex'] = playerId;

  await supabase.from('game_state').update({
    'balances': balances,
    'property_ownership': newOwnership,
    'pending_action': null,
    'phase': 'trade',
  }).eq('room_id', roomId);

  await _writeLog(roomId, playerId, state['turn_number'] as int,
      'buy_property', {'square': squareIndex, 'price': square.price},);

  return okJson({'bought': true, 'square': squareIndex});
}

// ---------------------------------------------------------------------------
// Stub handlers (to be fully implemented)
// ---------------------------------------------------------------------------

Future<Response> _payJailFine(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) async {
  final jailStatus = Map<String, dynamic>.from(
      state['jail_status'] as Map<String, dynamic>,);
  final playerJail = Map<String, dynamic>.from(
      jailStatus[playerId] as Map<String, dynamic>? ?? {},);

  if (playerJail['in_jail'] != true) {
    return errorJson(400, 'RULE_VIOLATION', 'Player is not in jail');
  }
  if ((playerJail['mandatory_turns_remaining'] as int? ?? 0) > 0) {
    return errorJson(400, 'RULE_VIOLATION', 'Serving mandatory jail turns -- cannot pay yet');
  }

  final fine = (playerJail['effective_fine'] as int?) ??
      (config['jail_fine'] as int? ?? 50);
  final balances = Map<String, dynamic>.from(
      state['balances'] as Map<String, dynamic>,);

  if (((balances[playerId] as int?) ?? 0) < fine) {
    return errorJson(400, 'INSUFFICIENT_FUNDS', 'Not enough money to pay jail fine');
  }

  balances[playerId] = ((balances[playerId] as int?) ?? 0) - fine;
  playerJail['in_jail'] = false;
  playerJail['turns_in_jail'] = 0;
  jailStatus[playerId] = playerJail;

  final freeParkingJackpot = config['free_parking_jackpot'] as bool? ?? false;
  final updates = <String, dynamic>{
    'balances': balances,
    'jail_status': jailStatus,
    'phase': 'roll',
    'updated_at': DateTime.now().toIso8601String(),
  };
  if (freeParkingJackpot) {
    updates['free_parking_pot'] =
        ((state['free_parking_pot'] as int?) ?? 0) + fine;
  }

  await supabase.from('game_state').update(updates).eq('room_id', roomId);
  await _writeLog(roomId, playerId, state['turn_number'] as int,
      'pay_jail_fine', {'fine': fine},);

  return okJson({'paid': true, 'fine': fine});
}

Future<Response> _useGoojfCard(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) async {
  final jailStatus = Map<String, dynamic>.from(
      state['jail_status'] as Map<String, dynamic>,);
  final playerJail = Map<String, dynamic>.from(
      jailStatus[playerId] as Map<String, dynamic>? ?? {},);

  if (playerJail['in_jail'] != true) {
    return errorJson(400, 'RULE_VIOLATION', 'Player is not in jail');
  }
  if ((playerJail['mandatory_turns_remaining'] as int? ?? 0) > 0) {
    return errorJson(400, 'RULE_VIOLATION', 'Serving mandatory jail turns -- cannot use card yet');
  }

  final goojfCards = Map<String, dynamic>.from(
      state['get_out_of_jail_cards'] as Map<String, dynamic>,);
  final cardCount = (goojfCards[playerId] as int?) ?? 0;

  if (cardCount <= 0) {
    return errorJson(400, 'RULE_VIOLATION', 'No Get Out of Jail Free cards held');
  }

  goojfCards[playerId] = cardCount - 1;
  playerJail['in_jail'] = false;
  playerJail['turns_in_jail'] = 0;
  playerJail['has_card'] = cardCount - 1 > 0;
  jailStatus[playerId] = playerJail;

  await supabase.from('game_state').update({
    'get_out_of_jail_cards': goojfCards,
    'jail_status': jailStatus,
    'phase': 'roll',
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  await _writeLog(roomId, playerId, state['turn_number'] as int,
      'use_goojf_card', {},);

  return okJson({'used': true});
}

Future<Response> _jailbreak(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) async {
  if (!(config['jailbreak_enabled'] as bool? ?? false)) {
    return errorJson(400, 'RULE_VIOLATION', 'Jailbreak is not enabled in this room');
  }

  final jailStatus = Map<String, dynamic>.from(
      state['jail_status'] as Map<String, dynamic>,);
  final playerJail = Map<String, dynamic>.from(
      jailStatus[playerId] as Map<String, dynamic>? ?? {},);

  if (playerJail['in_jail'] != true) {
    return errorJson(400, 'RULE_VIOLATION', 'Player is not in jail');
  }
  if ((playerJail['mandatory_turns_remaining'] as int? ?? 0) > 0) {
    return errorJson(400, 'RULE_VIOLATION', 'Serving mandatory jail turns -- cannot jailbreak yet');
  }

  playerJail['in_jail'] = false;
  playerJail['is_jailbreaking'] = true;
  playerJail['turns_in_jail'] = 0;
  jailStatus[playerId] = playerJail;

  final policeDuration = config['police_duration'] as int?;
  final activePawns = List<dynamic>.from(
      state['active_police_pawns'] as List<dynamic>,);
  activePawns.add({
    'owner_id': playerId,
    'position': Board.jailSquare,
    'turns_remaining': policeDuration,
  });

  await supabase.from('game_state').update({
    'jail_status': jailStatus,
    'active_police_pawns': activePawns,
    'phase': 'roll',
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  await _writeLog(roomId, playerId, state['turn_number'] as int,
      'jailbreak', {'police_spawned_at': Board.jailSquare},);

  return okJson({'jailbreaking': true});
}

Future<Response> _endTurn(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> room,
) async {
  if (state['phase'] != 'trade') {
    return errorJson(400, 'INVALID_PHASE', 'Can only end turn in trade phase');
  }
  if (room['current_player_id'] != playerId) {
    return errorJson(403, 'NOT_YOUR_TURN', 'Not your turn');
  }

  // Process repayment instalments due this turn
  final repaymentResult = await _processRepayments(roomId, playerId, state, config);
  if (repaymentResult != null) return repaymentResult; // bankruptcy triggered

  // Reload state in case repayments mutated it
  final freshState = await supabase
      .from('game_state')
      .select()
      .eq('room_id', roomId)
      .single();

  // Check doubles extra turn
  final doublesEnabled = config['doubles_enabled'] as bool? ?? true;
  final doublesExtraTurn = config['doubles_extra_turn'] as bool? ?? true;
  final diceRoll = freshState['dice_roll'] as List<dynamic>?;
  final consecutiveDoubles = freshState['consecutive_doubles'] as int? ?? 0;
  final rolledDoubles = doublesEnabled &&
      doublesExtraTurn &&
      diceRoll != null &&
      diceRoll.length >= 2 &&
      diceRoll.every((d) => d == diceRoll[0]);

  // If rolled doubles this turn: same player rolls again
  if (rolledDoubles && consecutiveDoubles > 0) {
    await supabase.from('game_state').update({
      'phase': 'roll',
      'dice_roll': null,
      'pending_action': null,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('room_id', roomId);
    return okJson({'turn_ended': false, 'reason': 'doubles_extra_turn'});
  }

  // Advance to next player
  final players = await supabase
      .from('room_players')
      .select('player_id, seat_order')
      .eq('room_id', roomId)
      .eq('is_bankrupt', false)
      .isFilter('left_at', null)
      .order('seat_order');

  if (players.isEmpty) return errorJson(500, 'NO_PLAYERS', 'No active players');

  final seats = (players as List).cast<Map<String, dynamic>>();
  final currentSeat = seats.indexWhere((p) => p['player_id'] == playerId);
  final nextSeat = (currentSeat + 1) % seats.length;
  final nextPlayerId = seats[nextSeat]['player_id'] as String;

  // Increment turn_number when cycle completes (back to seat 0)
  final currentTurn = freshState['turn_number'] as int;
  final nextTurn = nextSeat == 0 ? currentTurn + 1 : currentTurn;

  // Check turn_limit win condition
  final winningCondition = config['winning_condition'] as String? ?? 'last_player_standing';
  if (winningCondition == 'turn_limit') {
    final turnLimit = config['turn_limit'] as int? ?? 30;
    if (nextTurn > turnLimit) {
      await _endGame(roomId, seats, freshState, 'turn_limit');
      return okJson({'turn_ended': true, 'game_over': true});
    }
  }

  // Check time_limit win condition
  if (winningCondition == 'time_limit') {
    final startedAt = DateTime.parse(room['started_at'] as String);
    final timeLimitMins = config['time_limit_mins'] as int? ?? 60;
    if (DateTime.now().difference(startedAt).inMinutes >= timeLimitMins) {
      await _endGame(roomId, seats, freshState, 'time_limit');
      return okJson({'turn_ended': true, 'game_over': true});
    }
  }

  // Check net_worth_target at end of turn
  if (winningCondition == 'net_worth_target' &&
      config['net_worth_check'] == 'end_of_turn') {
    final target = config['net_worth_target'] as int? ?? 10000;
    final balances = freshState['balances'] as Map<String, dynamic>;
    final winner = seats.firstWhereOrNull(
      (p) => (balances[p['player_id']] as int? ?? 0) >= target,
    );
    if (winner != null) {
      await _endGame(roomId, seats, freshState, 'net_worth_target');
      return okJson({'turn_ended': true, 'game_over': true});
    }
  }

  final now = DateTime.now().toIso8601String();

  await supabase.from('game_state').update({
    'turn_number': nextTurn,
    'phase': 'roll',
    'dice_roll': null,
    'consecutive_doubles': 0,
    'pending_action': null,
    'updated_at': now,
  }).eq('room_id', roomId);

  await supabase.from('game_rooms').update({
    'current_player_id': nextPlayerId,
    'turn_started_at': now,
  }).eq('id', roomId);

  await _writeLog(roomId, playerId, currentTurn, 'end_turn',
      {'next_player': nextPlayerId},);

  // Async mode: send push notification to next player
  if (room['play_mode'] == 'async') {
    await _sendTurnNotification(nextPlayerId, room['room_code'] as String, roomId);
  }

  return okJson({'turn_ended': true, 'next_player': nextPlayerId});
}

Future<Response?> _processRepayments(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) async {
  final plans = (state['repayment_plans'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((p) => p['debtor_id'] == playerId)
      .toList();

  if (plans.isEmpty) return null;

  final balances = Map<String, dynamic>.from(
    state['balances'] as Map<String, dynamic>,
  );

  for (final plan in plans) {
    final instalmentAmount = plan['instalment_amount'] as int;
    final currentBalance = balances[playerId] as int? ?? 0;

    if (currentBalance >= instalmentAmount) {
      balances[playerId] = currentBalance - instalmentAmount;
      final creditorId = plan['creditor_id'] as String;
      balances[creditorId] =
          ((balances[creditorId] as int?) ?? 0) + instalmentAmount;

      final remaining = (plan['instalments_remaining'] as int) - 1;
      final allPlans = (state['repayment_plans'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final updatedPlans = allPlans.map((p) {
        if (p['plan_id'] == plan['plan_id']) {
          if (remaining <= 0) return null;
          return {...p, 'instalments_remaining': remaining};
        }
        return p;
      }).whereType<Map<String, dynamic>>().toList();

      await supabase.from('game_state').update({
        'balances': balances,
        'repayment_plans': updatedPlans,
      }).eq('room_id', roomId);
    } else {
      // Missed instalment → bankruptcy
      // TODO: liquidate assets then declare bankruptcy
      return errorJson(400, 'REPAYMENT_DEFAULT',
          'Insufficient funds for repayment instalment',);
    }
  }

  return null;
}

Future<void> _endGame(
  String roomId,
  List<Map<String, dynamic>> activePlayers,
  Map<String, dynamic> state,
  String reason,
) async {
  await supabase.from('game_rooms').update({
    'status': 'finished',
    'finished_at': DateTime.now().toIso8601String(),
  }).eq('id', roomId);

  await supabase.from('game_state').update({
    'phase': 'finished',
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  await _writeLog(roomId, null, state['turn_number'] as int, 'game_over',
      {'reason': reason},);

  await recordGameStats(roomId);
}

Future<Response> _declareBankruptcy(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> room,
) async {
  if (room['current_player_id'] != playerId) {
    return errorJson(403, 'NOT_YOUR_TURN', 'Not your turn');
  }
  final balances = state['balances'] as Map<String, dynamic>;
  final currentBalance = (balances[playerId] as int?) ?? 0;
  if (currentBalance >= 0) {
    return errorJson(400, 'RULE_VIOLATION', 'Cannot declare bankruptcy with non-negative balance');
  }

  final now = DateTime.now().toIso8601String();
  final bankruptcyAssetsTo = config['bankruptcyAssetsTo'] as String? ?? 'bank';

  // Transfer properties to creditor or bank
  final ownership = Map<String, dynamic>.from(
      state['property_ownership'] as Map<String, dynamic>,);
  final pendingAction = state['pending_action'] as Map<String, dynamic>?;
  final creditorId = pendingAction?['owner_id'] as String?;

  final String? newOwner = bankruptcyAssetsTo == 'creditor' && creditorId != null
      ? creditorId
      : null; // null = bank / unowned

  for (final entry in ownership.entries.toList()) {
    if (entry.value == playerId) {
      if (newOwner != null) {
        ownership[entry.key] = newOwner;
      } else {
        ownership.remove(entry.key);
      }
    }
  }

  // Clear buildings on bankrupt player's properties
  final houses = Map<String, dynamic>.from(state['houses'] as Map<String, dynamic>);
  final hotels = Map<String, dynamic>.from(state['hotels'] as Map<String, dynamic>);
  for (final key in houses.keys.toList()) {
    if ((state['property_ownership'] as Map<String, dynamic>)[key] == playerId) {
      houses.remove(key);
    }
  }
  for (final key in hotels.keys.toList()) {
    if ((state['property_ownership'] as Map<String, dynamic>)[key] == playerId) {
      hotels.remove(key);
    }
  }

  // Mark player bankrupt
  await supabase.from('room_players').update({
    'is_bankrupt': true,
  }).eq('room_id', roomId).eq('player_id', playerId);

  // Advance to next active (non-bankrupt) player
  final players = await supabase
      .from('room_players')
      .select('player_id, seat_order')
      .eq('room_id', roomId)
      .eq('is_bankrupt', false)
      .neq('player_id', playerId)
      .isFilter('left_at', null)
      .order('seat_order');

  final seats = (players as List).cast<Map<String, dynamic>>();

  // End immediately on first bankruptcy when this win condition is set
  final winningCondition = config['winning_condition'] as String? ?? 'last_player_standing';
  if (winningCondition == 'highest_value_first_bankruptcy') {
    await supabase.from('game_state').update({
      'property_ownership': ownership,
      'houses': houses,
      'hotels': hotels,
      'phase': 'finished',
      'pending_action': null,
      'updated_at': now,
    }).eq('room_id', roomId);
    await _endGame(roomId, seats, state, 'highest_value_first_bankruptcy');
    return okJson({'bankrupt': true, 'game_over': true});
  }

  if (seats.length <= 1) {
    // Game over
    await supabase.from('game_state').update({
      'property_ownership': ownership,
      'houses': houses,
      'hotels': hotels,
      'phase': 'finished',
      'pending_action': null,
      'updated_at': now,
    }).eq('room_id', roomId);
    await supabase.from('game_rooms').update({
      'status': 'finished',
      'finished_at': now,
    }).eq('id', roomId);
    await _writeLog(roomId, playerId, state['turn_number'] as int, 'game_over',
        {'reason': 'bankruptcy'},);
    await recordGameStats(roomId);
    return okJson({'bankrupt': true, 'game_over': true});
  }

  // Find next player after the bankrupt one in seat order
  final allSeats = await supabase
      .from('room_players')
      .select('player_id, seat_order')
      .eq('room_id', roomId)
      .isFilter('left_at', null)
      .order('seat_order');

  final allSeatList = (allSeats as List).cast<Map<String, dynamic>>();
  final currentSeat = allSeatList.indexWhere((p) => p['player_id'] == playerId);
  String nextPlayerId = seats[0]['player_id'] as String;
  for (int i = currentSeat + 1; i < allSeatList.length + currentSeat + 1; i++) {
    final candidate = allSeatList[i % allSeatList.length]['player_id'] as String;
    if (seats.any((s) => s['player_id'] == candidate)) {
      nextPlayerId = candidate;
      break;
    }
  }

  await supabase.from('game_state').update({
    'property_ownership': ownership,
    'houses': houses,
    'hotels': hotels,
    'phase': 'roll',
    'pending_action': null,
    'updated_at': now,
  }).eq('room_id', roomId);

  await supabase.from('game_rooms').update({
    'current_player_id': nextPlayerId,
  }).eq('id', roomId);

  await _writeLog(roomId, playerId, state['turn_number'] as int, 'game_over',
      {'reason': 'player_bankrupt', 'player_id': playerId},);

  return okJson({'bankrupt': true, 'next_player': nextPlayerId});
}

Future<void> _sendTurnNotification(
  String playerId,
  String roomCode,
  String roomId,
) async {
  // Notification dispatch is handled by Supabase Edge Function triggered
  // on game_rooms.current_player_id change. No direct push here.
  // This is a no-op on the server — kept as hook for future direct dispatch.
}

Future<Response> _placeTrap(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  final cardId = payload['source_card_id'] as String?;
  final triggerEffect = payload['trigger_effect'] as Map<String, dynamic>?;
  final visible = payload['visible'] as bool? ?? true;
  final triggerCount = payload['trigger_count'] as int?;
  final placement = payload['placement'] as String? ?? 'player_choice';

  if (cardId == null || triggerEffect == null) {
    return errorJson(400, 'MISSING_FIELD', 'source_card_id and trigger_effect required');
  }

  final rand = Random.secure();
  const illegalSquares = {
    Board.goSquare,
    Board.jailSquare,
    Board.freeParkingSquare,
    Board.goToJailSquare,
  };

  int squareIndex;
  if (placement == 'random') {
    final eligible = List.generate(Board.boardSize, (i) => i)
        .where((i) => !illegalSquares.contains(i))
        .toList();
    squareIndex = eligible[rand.nextInt(eligible.length)];
  } else {
    final chosen = payload['square'] as int?;
    if (chosen == null) {
      return errorJson(400, 'MISSING_FIELD', 'square required for player_choice placement');
    }
    if (illegalSquares.contains(chosen)) {
      return errorJson(400, 'RULE_VIOLATION', 'Cannot place trap on this square');
    }
    squareIndex = chosen;
  }

  await supabase.from('active_traps').insert({
    'room_id': roomId,
    'owner_id': playerId,
    'square_index': squareIndex,
    'visible': visible,
    'source_card_id': cardId,
    'triggers_remaining': triggerCount,
    'placed_turn': state['turn_number'] as int,
    'trigger_effect': triggerEffect,
  });

  await _writeLog(roomId, playerId, state['turn_number'] as int, 'place_trap', {
    'square': visible ? squareIndex : null, // redact position in log for invisible traps
    'visible': visible,
  });

  return okJson({
    'placed': true,
    'square': visible ? squareIndex : null,
    'visible': visible,
  });
}

Future<Response> _removeTrap(
    String roomId, String playerId, Map<String, dynamic> payload,) async {
  final trapId = payload['trap_id'] as String?;
  if (trapId == null) return errorJson(400, 'MISSING_FIELD', 'trap_id required');
  await supabase
      .from('active_traps')
      .delete()
      .eq('id', trapId)
      .eq('owner_id', playerId)
      .eq('room_id', roomId);
  return okJson({'removed': true});
}

// ---------------------------------------------------------------------------
// Debug actions (only available when room_configs.debug_mode = true)
// ---------------------------------------------------------------------------

Future<Response> _debugTeleport(
  String roomId,
  String actingPlayerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  if (!(config['debug_mode'] as bool? ?? false)) {
    return errorJson(403, 'FORBIDDEN', 'Debug mode not enabled');
  }
  final targetPlayer = payload['player_id'] as String? ?? actingPlayerId;
  final squareIndex = payload['square'] as int?;
  if (squareIndex == null || squareIndex < 0 || squareIndex >= Board.boardSize) {
    return errorJson(400, 'MISSING_FIELD', 'Valid square (0-${Board.boardSize - 1}) required');
  }

  final positions = Map<String, dynamic>.from(
      state['board_positions'] as Map<String, dynamic>,);
  positions[targetPlayer] = squareIndex;

  await supabase.from('game_state').update({
    'board_positions': positions,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  // Position-only: do not resolve landing effects so game flow is unaffected.
  await _writeLog(roomId, actingPlayerId, state['turn_number'] as int, 'debug_teleport',
      {'player': targetPlayer, 'square': squareIndex},);

  return okJson({'teleported': true, 'player': targetPlayer, 'square': squareIndex});
}

Future<Response> _debugAssignProperty(
  String roomId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  if (!(config['debug_mode'] as bool? ?? false)) {
    return errorJson(403, 'FORBIDDEN', 'Debug mode not enabled');
  }
  final squareIndex = payload['square'] as int?;
  if (squareIndex == null || squareIndex < 0 || squareIndex >= Board.boardSize) {
    return errorJson(400, 'MISSING_FIELD', 'Valid square (0-${Board.boardSize - 1}) required');
  }
  final square = Board.squares[squareIndex];
  if (square.price == null) {
    return errorJson(400, 'RULE_VIOLATION', 'Square is not purchasable');
  }

  final toPlayerId = payload['player_id'] as String?;
  final ownership = Map<String, dynamic>.from(
      state['property_ownership'] as Map<String, dynamic>,);

  if (toPlayerId == null) {
    ownership.remove('$squareIndex');
  } else {
    ownership['$squareIndex'] = toPlayerId;
  }

  await supabase.from('game_state').update({
    'property_ownership': ownership,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({'assigned': true, 'square': squareIndex, 'player_id': toPlayerId});
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Decrements the `rolls` counter on trade-based rent protections for [playerId].
/// Removes entries where rolls drop to zero. Returns the updated rent_modifiers map.
Map<String, dynamic> _decrementRollProtections(
  Map<String, dynamic> rentModifiers,
  String playerId,
) {
  final result = Map<String, dynamic>.from(rentModifiers);
  final playerMods = result[playerId] as Map<String, dynamic>?;
  if (playerMods == null) return result;

  final mods = Map<String, dynamic>.from(playerMods);
  final protections = (mods['protections'] as List? ?? [])
      .cast<Map<String, dynamic>>()
      .map((p) {
        if (!p.containsKey('rolls')) return p;
        final remaining = ((p['rolls'] as int?) ?? 0) - 1;
        return {...p, 'rolls': remaining};
      })
      .where((p) => !p.containsKey('rolls') || (p['rolls'] as int) > 0)
      .toList();
  mods['protections'] = protections;
  result[playerId] = mods;
  return result;
}

/// Returns true if [playerId] has an active trade-based rent protection
/// against [ownerId] in the given [rentModifiers].
bool _hasRentImmunity(
  Map<String, dynamic> rentModifiers,
  String playerId,
  String ownerId,
) {
  final playerMods = rentModifiers[playerId] as Map<String, dynamic>?;
  if (playerMods == null) return false;
  final protections = (playerMods['protections'] as List? ?? [])
      .cast<Map<String, dynamic>>();
  return protections.any(
    (p) => p['from_player_id'] == ownerId && ((p['rolls'] as int?) ?? 0) > 0,
  );
}

Future<Response> _rollDiceInJail(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  List<int> roll,
  int total,
  bool isDoubles,
  Map<String, dynamic> playerJail,
) async {
  final mandatoryTurns = playerJail['mandatory_turns_remaining'] as int? ?? 0;
  final turnsInJail = playerJail['turns_in_jail'] as int? ?? 0;
  final jailTurns = (config['jail_turns'] as int?) ?? 3;
  final jailDoublesEscape = config['jail_doubles_escape'] as bool? ?? true;

  final jailStatus = Map<String, dynamic>.from(
      state['jail_status'] as Map<String, dynamic>,);

  // Mandatory turns: serve time, no escape possible
  if (mandatoryTurns > 0) {
    final newMandatory = mandatoryTurns - 1;
    playerJail['mandatory_turns_remaining'] = newMandatory;
    if (newMandatory == 0) playerJail['turns_in_jail'] = 0;
    jailStatus[playerId] = playerJail;
    await supabase.from('game_state').update({
      'jail_status': jailStatus,
      'dice_roll': roll,
      'phase': 'trade',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('room_id', roomId);
    await _writeLog(roomId, playerId, state['turn_number'] as int,
        'roll_dice', {'roll': roll, 'mandatory_turns_remaining': newMandatory},);
    return okJson({'roll': roll, 'mandatory_turns_remaining': newMandatory});
  }

  // Escape via doubles
  if (isDoubles && jailDoublesEscape) {
    playerJail['in_jail'] = false;
    playerJail['turns_in_jail'] = 0;
    jailStatus[playerId] = playerJail;

    final positions = Map<String, dynamic>.from(
        state['board_positions'] as Map<String, dynamic>,);
    final currentPos = (positions[playerId] as int?) ?? Board.jailSquare;
    final newPos = (currentPos + total) % Board.boardSize;
    positions[playerId] = newPos;

    final jailEscapeRentModifiers = _decrementRollProtections(
      Map<String, dynamic>.from(state['rent_modifiers'] as Map<String, dynamic>? ?? {}),
      playerId,
    );

    await supabase.from('game_state').update({
      'jail_status': jailStatus,
      'board_positions': positions,
      'dice_roll': roll,
      'consecutive_doubles': 0,
      'rent_modifiers': jailEscapeRentModifiers,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('room_id', roomId);

    await _writeLog(roomId, playerId, state['turn_number'] as int,
        'roll_dice', {'roll': roll, 'escaped_jail': true, 'new_position': newPos},);
    await _resolveSquareLanding(roomId, playerId, newPos, state, config);
    return okJson({'roll': roll, 'escaped_jail': true, 'new_position': newPos});
  }

  // Failed roll — last attempt: force payment and move
  if (turnsInJail >= jailTurns - 1) {
    final fine = (playerJail['effective_fine'] as int?) ??
        (config['jail_fine'] as int? ?? 50);
    final balances = Map<String, dynamic>.from(
        state['balances'] as Map<String, dynamic>,);
    balances[playerId] = ((balances[playerId] as int?) ?? 0) - fine;

    playerJail['in_jail'] = false;
    playerJail['turns_in_jail'] = 0;
    jailStatus[playerId] = playerJail;

    final positions = Map<String, dynamic>.from(
        state['board_positions'] as Map<String, dynamic>,);
    final currentPos = (positions[playerId] as int?) ?? Board.jailSquare;
    final newPos = (currentPos + total) % Board.boardSize;
    positions[playerId] = newPos;

    final forcedMoveRentModifiers = _decrementRollProtections(
      Map<String, dynamic>.from(state['rent_modifiers'] as Map<String, dynamic>? ?? {}),
      playerId,
    );

    final updates = <String, dynamic>{
      'jail_status': jailStatus,
      'balances': balances,
      'board_positions': positions,
      'dice_roll': roll,
      'rent_modifiers': forcedMoveRentModifiers,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (config['free_parking_jackpot'] as bool? ?? false) {
      updates['free_parking_pot'] =
          ((state['free_parking_pot'] as int?) ?? 0) + fine;
    }

    final stateForLanding = Map<String, dynamic>.from(state)
        ..['balances'] = balances;
    await supabase.from('game_state').update(updates).eq('room_id', roomId);
    await _writeLog(roomId, playerId, state['turn_number'] as int,
        'roll_dice', {'roll': roll, 'forced_fine': fine, 'new_position': newPos},);
    await _resolveSquareLanding(roomId, playerId, newPos, stateForLanding, config);
    return okJson({'roll': roll, 'forced_fine': fine, 'new_position': newPos});
  }

  // Normal failed roll — stay in jail
  playerJail['turns_in_jail'] = turnsInJail + 1;
  jailStatus[playerId] = playerJail;
  await supabase.from('game_state').update({
    'jail_status': jailStatus,
    'dice_roll': roll,
    'phase': 'trade',
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  await _writeLog(roomId, playerId, state['turn_number'] as int,
      'roll_dice', {'roll': roll, 'failed_jail_roll': true, 'turns_in_jail': turnsInJail + 1},);
  return okJson({'roll': roll, 'failed_jail_roll': true, 'turns_in_jail': turnsInJail + 1});
}

/// Resolves the effect of landing on a square.
/// Writes pending_action if player input is needed; auto-resolves otherwise.
Future<void> _resolveSquareLanding(
  String roomId,
  String playerId,
  int squareIndex,
  Map<String, dynamic> state,
  Map<String, dynamic> config, {
  double rentMultiplier = 1.0,
  int depth = 0,
}) async {
  final square = Board.squares[squareIndex];
  final ownership = state['property_ownership'] as Map<String, dynamic>;
  final ownerId = ownership['$squareIndex'] as String?;
  final mortgaged = (state['mortgaged'] as List<dynamic>).contains(squareIndex);
  final now = DateTime.now().toIso8601String();

  if (depth > 1) {
    await supabase.from('game_state').update({
      'phase': 'trade',
      'pending_action': null,
      'updated_at': now,
    }).eq('room_id', roomId);
    return;
  }

  switch (square.type) {
    case SquareType.property:
    case SquareType.station:
    case SquareType.utility:
      if (ownerId == null) {
        // Unowned: offer purchase — phase and pending set atomically here
        await supabase.from('game_state').update({
          'phase': 'action',
          'pending_action': {'type': 'purchase_decision', 'square': squareIndex},
          'updated_at': now,
        }).eq('room_id', roomId);
      } else if (ownerId != playerId && !mortgaged) {
        final rentModifiers = Map<String, dynamic>.from(
            state['rent_modifiers'] as Map<String, dynamic>? ?? {},);
        final immune = _hasRentImmunity(rentModifiers, playerId, ownerId);

        if (immune) {
          await supabase.from('game_state').update({
            'pending_action': null,
            'phase': 'trade',
            'updated_at': now,
          }).eq('room_id', roomId);
          await _writeLog(roomId, playerId, state['turn_number'] as int, 'rent_immunity',
              {'square': squareIndex, 'owner_id': ownerId},);
        } else {
          final rent = (_calculateRent(square, squareIndex, ownerId, state) * rentMultiplier).round();
          final balances = Map<String, dynamic>.from(
              state['balances'] as Map<String, dynamic>,);
          final playerBalance = (balances[playerId] as int?) ?? 0;
          final actualPayment = playerBalance < rent ? playerBalance : rent;
          balances[playerId] = playerBalance - rent; // goes negative if insufficient
          balances[ownerId] = ((balances[ownerId] as int?) ?? 0) + actualPayment;

          if (playerBalance < rent) {
            // Insufficient funds: freeze in bankruptcyNegotiation
            await supabase.from('game_state').update({
              'balances': balances,
              'pending_action': {
                'type': 'rent_payment',
                'square': squareIndex,
                'owner_id': ownerId,
                'amount': rent,
              },
              'phase': 'bankruptcyNegotiation',
              'updated_at': now,
            }).eq('room_id', roomId);
            await _writeLog(roomId, playerId, state['turn_number'] as int, 'rent_payment',
                {'square': squareIndex, 'owner_id': ownerId, 'amount': rent},);
          } else {
            await supabase.from('game_state').update({
              'balances': balances,
              'pending_action': null,
              'phase': 'trade',
              'updated_at': now,
            }).eq('room_id', roomId);
            await _writeLog(roomId, playerId, state['turn_number'] as int, 'rent_payment',
                {'square': squareIndex, 'owner_id': ownerId, 'amount': rent},);
          }
        }
      } else {
        // Own property or mortgaged: no action
        await supabase.from('game_state').update({
          'pending_action': null,
          'phase': 'trade',
          'updated_at': now,
        }).eq('room_id', roomId);
      }

    case SquareType.communityChest:
    case SquareType.chance:
      final result = await drawAndApply(
        deckType: square.type == SquareType.communityChest ? 'community_chest' : 'chance',
        roomId: roomId,
        playerId: playerId,
        state: state,
        config: config,
      );

      final cardRentMultiplier =
          (result.stateUpdates['_card_rent_multiplier'] as num?)?.toDouble() ?? 1.0;
      final cardUpdates = Map<String, dynamic>.from(result.stateUpdates)
        ..remove('_card_rent_multiplier');

      // Check if card caused a negative balance → bankruptcy
      final cardBalances = cardUpdates['balances'] as Map<String, dynamic>?;
      final cardPlayerBalance = (cardBalances ?? (state['balances'] as Map<String, dynamic>))[playerId] as int? ?? 0;
      final cardCausedBankruptcy = cardPlayerBalance < 0;

      await supabase.from('game_state').update({
        ...cardUpdates,
        'pending_action': cardCausedBankruptcy
            ? {'type': 'card_payment', 'card_id': result.card.id, 'label': result.card.label}
            : null,
        'phase': cardCausedBankruptcy ? 'bankruptcyNegotiation' : 'trade',
        'updated_at': now,
      }).eq('room_id', roomId);
      await _writeLog(roomId, playerId, state['turn_number'] as int,
          'draw_card', result.logPayload,);

      final newPositions = cardUpdates['board_positions'] as Map<String, dynamic>?;
      if (!cardCausedBankruptcy && newPositions != null) {
        final newPos = newPositions[playerId] as int?;
        if (newPos != null && newPos != squareIndex) {
          final mergedState = Map<String, dynamic>.from(state)..addAll(cardUpdates);
          await _resolveSquareLanding(
            roomId, playerId, newPos, mergedState, config,
            rentMultiplier: cardRentMultiplier,
            depth: depth + 1,
          );
        }
      }

    case SquareType.tax:
      final taxAmount = square.taxAmount ?? 0;
      final balances = Map<String, dynamic>.from(
          state['balances'] as Map<String, dynamic>,);
      final preTaxBalance = (balances[playerId] as int?) ?? 0;
      balances[playerId] = preTaxBalance - taxAmount;
      final canPayTax = preTaxBalance >= taxAmount;
      final taxUpdates = <String, dynamic>{
        'balances': balances,
        'pending_action': canPayTax
            ? null
            : {'type': 'tax_payment', 'square': squareIndex, 'amount': taxAmount},
        'phase': canPayTax ? 'trade' : 'bankruptcyNegotiation',
        'updated_at': now,
      };
      if (config['free_parking_jackpot'] as bool? ?? false) {
        taxUpdates['free_parking_pot'] =
            ((state['free_parking_pot'] as int?) ?? 0) + taxAmount;
      }
      await supabase.from('game_state').update(taxUpdates).eq('room_id', roomId);
      await _writeLog(roomId, playerId, state['turn_number'] as int, 'tax_payment',
          {'square': squareIndex, 'amount': taxAmount},);

    case SquareType.freeParking:
      final jackpot = config['free_parking_jackpot'] as bool? ?? false;
      if (jackpot) {
        final pot = (state['free_parking_pot'] as int?) ?? 0;
        if (pot > 0) {
          final balances = Map<String, dynamic>.from(
              state['balances'] as Map<String, dynamic>,);
          balances[playerId] = ((balances[playerId] as int?) ?? 0) + pot;
          await supabase.from('game_state').update({
            'balances': balances,
            'free_parking_pot': 0,
            'pending_action': null,
            'phase': 'trade',
            'updated_at': now,
          }).eq('room_id', roomId);
          break;
        }
      }
      await supabase.from('game_state').update({
        'pending_action': null,
        'phase': 'trade',
        'updated_at': now,
      }).eq('room_id', roomId);

    case SquareType.goToJail:
      await _sendToJail(roomId, playerId, state);
      await _writeLog(roomId, playerId, state['turn_number'] as int, 'go_to_jail', {});

    case SquareType.go:
    case SquareType.jail:
      // Go salary already applied in roll handler; jail = just visiting
      await supabase.from('game_state').update({
        'pending_action': null,
        'phase': 'trade',
        'updated_at': now,
      }).eq('room_id', roomId);

    // Trap resolution runs after square resolution
    // active_traps checked in landing pipeline separately
  }

  // Check active traps on this square
  await _resolveTrapTriggers(roomId, playerId, squareIndex, state, config);
}

Future<void> _resolveTrapTriggers(
  String roomId,
  String playerId,
  int squareIndex,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) async {
  final traps = await supabase
      .from('active_traps')
      .select()
      .eq('room_id', roomId)
      .eq('square_index', squareIndex)
      .order('created_at');

  if ((traps as List).isEmpty) return;

  final balances = Map<String, dynamic>.from(
      state['balances'] as Map<String, dynamic>,);

  for (final trap in traps.cast<Map<String, dynamic>>()) {
    if (trap['owner_id'] == playerId) continue; // own trap: no trigger

    final effect = trap['trigger_effect'] as Map<String, dynamic>;
    final amount = effect['amount'] as int? ?? 0;
    final beneficiary = effect['beneficiary'] as String? ?? 'bank';

    balances[playerId] = ((balances[playerId] as int?) ?? 0) - amount;
    if (beneficiary == 'placer') {
      final ownerId = trap['owner_id'] as String;
      balances[ownerId] = ((balances[ownerId] as int?) ?? 0) + amount;
    } else if (config['free_parking_jackpot'] as bool? ?? false) {
      await supabase.from('game_state').update({
        'free_parking_pot':
            ((state['free_parking_pot'] as int?) ?? 0) + amount,
      }).eq('room_id', roomId);
    }

    final triggersRemaining = trap['triggers_remaining'] as int?;
    if (triggersRemaining != null) {
      if (triggersRemaining <= 1) {
        await supabase.from('active_traps').delete().eq('id', trap['id']);
      } else {
        await supabase.from('active_traps').update({
          'triggers_remaining': triggersRemaining - 1,
        }).eq('id', trap['id']);
      }
    }

    await _writeLog(roomId, playerId, state['turn_number'] as int,
        'trap_triggered', {'trap_id': trap['id'], 'amount': amount, 'square': squareIndex},);
  }

  await supabase.from('game_state').update({
    'balances': balances,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);
}

Future<void> _sendToJail(
  String roomId,
  String playerId,
  Map<String, dynamic> state, {
  int consecutiveDoubles = 0,
}) async {
  final positions = Map<String, dynamic>.from(
    state['board_positions'] as Map<String, dynamic>,
  );
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
    'effective_fine': 50,
    'has_card': false,
  };

  await supabase.from('game_state').update({
    'board_positions': positions,
    'jail_status': jailStatus,
    'consecutive_doubles': consecutiveDoubles,
    'pending_action': null,
    'phase': 'trade',
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);
}

int _calculateRent(
  BoardSquare square,
  int squareIndex,
  String ownerId,
  Map<String, dynamic> state,
) {
  final ownership = state['property_ownership'] as Map<String, dynamic>;

  switch (square.type) {
    case SquareType.property:
      if (square.rent == null) return 0;
      final hasHotel =
          (state['hotels'] as Map<String, dynamic>)['$squareIndex'] as bool? ??
              false;
      final houses =
          (state['houses'] as Map<String, dynamic>)['$squareIndex'] as int? ??
              0;
      if (hasHotel) return square.rent![5];
      if (houses > 0) return square.rent![houses];
      // Base rent doubles when owner holds the full colour group
      final groupIndices = Board.squares
          .asMap()
          .entries
          .where((e) =>
              e.value.colourGroup != null &&
              e.value.colourGroup == square.colourGroup,)
          .map((e) => e.key)
          .toList();
      final ownsMonopoly =
          groupIndices.every((i) => ownership['$i'] == ownerId);
      return ownsMonopoly ? square.rent![0] * 2 : square.rent![0];

    case SquareType.station:
      final stationsOwned = Board.squares
          .asMap()
          .entries
          .where((e) =>
              e.value.type == SquareType.station &&
              ownership['${e.key}'] == ownerId,)
          .length;
      // 25 → 50 → 100 → 200
      return 25 * (1 << (stationsOwned - 1).clamp(0, 3));

    case SquareType.utility:
      final diceRoll =
          (state['dice_roll'] as List<dynamic>?)?.cast<int>() ?? [];
      final diceTotal = diceRoll.fold(0, (a, b) => a + b);
      final utilitiesOwned = Board.squares
          .asMap()
          .entries
          .where((e) =>
              e.value.type == SquareType.utility &&
              ownership['${e.key}'] == ownerId,)
          .length;
      return diceTotal * (utilitiesOwned >= 2 ? 10 : 4);

    default:
      return 0;
  }
}

Future<void> _writeLog(
  String roomId,
  String? playerId,
  int turnNumber,
  String action,
  Map<String, dynamic> payload,
) async {
  await supabase.from('game_log').insert({
    'room_id': roomId,
    'player_id': playerId,
    'turn_number': turnNumber,
    'action': action,
    'payload': payload,
  });
}
