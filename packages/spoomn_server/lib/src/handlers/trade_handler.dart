import 'package:shelf/shelf.dart';

import '../db/supabase_client.dart';
import '../middleware/auth_middleware.dart';

Future<void> _writeLog(String roomId, String playerId, int turnNumber, String action, Map<String, dynamic> payload) async {
  await supabase.from('game_log').insert({
    'room_id': roomId,
    'player_id': playerId,
    'turn_number': turnNumber,
    'action': action,
    'payload': payload,
  });
}

Future<int> _getTurnNumber(String roomId) async {
  final row = await supabase.from('game_state').select('turn_number').eq('room_id', roomId).single();
  return (row['turn_number'] as int?) ?? 0;
}

Future<Response> proposeTrade(
  String roomId,
  String playerId,
  Map<String, dynamic> payload,
  Map<String, dynamic> config, {
  String? excludeTradeId,
  bool writeLog = true,
}) async {
  final participants = (payload['participants'] as List?)?.cast<String>();
  final legs = (payload['legs'] as List?)?.cast<Map<String, dynamic>>();

  if (participants == null || legs == null) {
    return errorJson(400, 'MISSING_FIELD', 'participants and legs required');
  }
  if (!participants.contains(playerId)) {
    return errorJson(400, 'RULE_VIOLATION', 'Proposer must be in participants list');
  }

  final multiParty = config['multi_party_trades'] as bool? ?? false;
  if (!multiParty && participants.length > 2) {
    return errorJson(400, 'RULE_VIOLATION',
        'Multi-party trades not enabled — max 2 participants',);
  }

  // Validate proposer owns everything they're offering
  final stateRow = await supabase
      .from('game_state')
      .select()
      .eq('room_id', roomId)
      .single();

  final ownership = stateRow['property_ownership'] as Map<String, dynamic>;
  final balances = stateRow['balances'] as Map<String, dynamic>;
  final goojfCards = stateRow['get_out_of_jail_cards'] as Map<String, dynamic>;

  for (final leg in legs) {
    final from = leg['from'] as String;
    final properties = (leg['properties'] as List?)?.cast<int>() ?? [];
    final money = (leg['money'] as int?) ?? 0;
    final jailCards = (leg['jail_cards'] as int?) ?? 0;

    for (final prop in properties) {
      if (ownership['$prop'] != from) {
        return errorJson(400, 'NOT_OWNER',
            'Player $from does not own property $prop',);
      }
    }
    if (money > 0 && ((balances[from] as int?) ?? 0) < money) {
      return errorJson(400, 'INSUFFICIENT_FUNDS',
          'Player $from cannot afford £$money in this trade',);
    }
    if (jailCards > 0 && ((goojfCards[from] as int?) ?? 0) < jailCards) {
      return errorJson(400, 'RULE_VIOLATION',
          'Player $from does not have $jailCards GOOJF card(s)',);
    }
  }

  // Check no asset committed to another active pending trade.
  // Countered trades are superseded and must not block new proposals.
  var pendingQuery = supabase
      .from('pending_trades')
      .select()
      .eq('room_id', roomId)
      .eq('status', 'pending');
  if (excludeTradeId != null) {
    pendingQuery = pendingQuery.neq('id', excludeTradeId);
  }
  final pendingTrades = await pendingQuery;

  for (final existing in (pendingTrades as List).cast<Map<String, dynamic>>()) {
    final existingLegs = (existing['legs'] as List).cast<Map<String, dynamic>>();
    for (final el in existingLegs) {
      final ep = (el['properties'] as List?)?.cast<int>() ?? [];
      for (final leg in legs) {
        final lp = (leg['properties'] as List?)?.cast<int>() ?? [];
        final conflict = lp.any((p) => ep.contains(p));
        if (conflict) {
          return errorJson(400, 'ASSET_COMMITTED',
              'A property in this trade is already in a pending trade',);
        }
      }
    }
  }

  await supabase.from('pending_trades').insert({
    'room_id': roomId,
    'proposer_id': playerId,
    'participants': participants,
    'legs': legs,
    'status': 'pending',
    'accepted_by': [playerId], // proposer auto-accepts their own proposal
  });

  if (writeLog) {
    await _writeLog(roomId, playerId, stateRow['turn_number'] as int, 'propose_trade',
        {'participants': participants, 'legs': legs},);
  }

  return okJson({'proposed': true});
}

Future<Response> acceptTrade(
  String roomId,
  String playerId,
  Map<String, dynamic> payload,
) async {
  final tradeId = payload['trade_id'] as String?;
  if (tradeId == null) return errorJson(400, 'MISSING_FIELD', 'trade_id required');

  final trade = await supabase
      .from('pending_trades')
      .select()
      .eq('id', tradeId)
      .eq('room_id', roomId)
      .maybeSingle();

  if (trade == null) return errorJson(404, 'NOT_FOUND', 'Trade not found');
  if (!['pending', 'countered'].contains(trade['status'])) {
    return errorJson(400, 'RULE_VIOLATION', 'Trade is no longer active');
  }

  final participants = List<String>.from(trade['participants'] as List);
  if (!participants.contains(playerId)) {
    return errorJson(403, 'NOT_PARTICIPANT', 'You are not part of this trade');
  }

  final acceptedBy = List<String>.from(trade['accepted_by'] as List? ?? []);
  if (acceptedBy.contains(playerId)) {
    return errorJson(400, 'RULE_VIOLATION', 'Already accepted');
  }

  acceptedBy.add(playerId);
  final allAccepted = participants.every((p) => acceptedBy.contains(p));

  if (!allAccepted) {
    await supabase.from('pending_trades').update({
      'accepted_by': acceptedBy,
    }).eq('id', tradeId);
    final partialTurnNum = await _getTurnNumber(roomId);
    await _writeLog(roomId, playerId, partialTurnNum, 'accept_trade', {'trade_id': tradeId, 'completed': false});
    return okJson({'accepted': true, 'waiting_for': participants.length - acceptedBy.length});
  }

  // All accepted — apply atomically
  final stateRow = await supabase
      .from('game_state')
      .select()
      .eq('room_id', roomId)
      .single();

  final legs = (trade['legs'] as List).cast<Map<String, dynamic>>();

  // Re-validate all assets still owned
  final ownership = Map<String, dynamic>.from(
      stateRow['property_ownership'] as Map<String, dynamic>,);
  final balances = Map<String, dynamic>.from(
      stateRow['balances'] as Map<String, dynamic>,);
  final goojfCards = Map<String, dynamic>.from(
      stateRow['get_out_of_jail_cards'] as Map<String, dynamic>,);
  final rentModifiers = Map<String, dynamic>.from(
      stateRow['rent_modifiers'] as Map<String, dynamic>,);

  for (final leg in legs) {
    final from = leg['from'] as String;
    final properties = (leg['properties'] as List?)?.cast<int>() ?? [];
    final money = (leg['money'] as int?) ?? 0;
    final jailCards = (leg['jail_cards'] as int?) ?? 0;

    for (final prop in properties) {
      if (ownership['$prop'] != from) {
        await supabase.from('pending_trades').update({
          'status': 'cancelled',
          'resolved_at': DateTime.now().toIso8601String(),
        }).eq('id', tradeId);
        return errorJson(400, 'ASSET_INVALID',
            'Property $prop is no longer owned by $from — trade cancelled',);
      }
    }
    if (money > 0 && ((balances[from] as int?) ?? 0) < money) {
      await supabase.from('pending_trades').update({
        'status': 'cancelled',
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', tradeId);
      return errorJson(400, 'INSUFFICIENT_FUNDS',
          'Player $from can no longer afford trade — cancelled',);
    }
    if (jailCards > 0 && ((goojfCards[from] as int?) ?? 0) < jailCards) {
      await supabase.from('pending_trades').update({
        'status': 'cancelled',
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', tradeId);
      return errorJson(400, 'ASSET_INVALID',
          'Player $from no longer has $jailCards GOOJF card(s) — cancelled',);
    }
  }

  // Apply all legs
  for (final leg in legs) {
    final from = leg['from'] as String;
    final to = leg['to'] as String;
    final properties = (leg['properties'] as List?)?.cast<int>() ?? [];
    final money = (leg['money'] as int?) ?? 0;
    final jailCards = (leg['jail_cards'] as int?) ?? 0;
    final immunityTurns = (leg['rent_immunity_turns'] as int?) ?? 0;

    for (final prop in properties) {
      ownership['$prop'] = to;
    }

    if (money > 0) {
      balances[from] = ((balances[from] as int?) ?? 0) - money;
      balances[to] = ((balances[to] as int?) ?? 0) + money;
    }

    if (jailCards > 0) {
      goojfCards[from] = ((goojfCards[from] as int?) ?? 0) - jailCards;
      goojfCards[to] = ((goojfCards[to] as int?) ?? 0) + jailCards;
    }

    if (immunityTurns > 0) {
      final toMods = Map<String, dynamic>.from(
          (rentModifiers[to] as Map<String, dynamic>?) ??
              {'protections': [], 'discounts': []},);
      final protections = List<dynamic>.from(toMods['protections'] as List? ?? []);
      protections.add({
        'type': 'rent_protection',
        'rolls': immunityTurns,
        'from_player_id': from,
      });
      toMods['protections'] = protections;
      rentModifiers[to] = toMods;
    }
  }

  // Transfer trap ownership for any active traps included
  final trapIds = (legs
          .expand((l) => (l['trap_ids'] as List?)?.cast<String>() ?? []))
      .toList();
  for (final leg in legs) {
    final to = leg['to'] as String;
    final ids = (leg['trap_ids'] as List?)?.cast<String>() ?? [];
    for (final trapId in ids) {
      await supabase
          .from('active_traps')
          .update({'owner_id': to})
          .eq('id', trapId)
          .eq('room_id', roomId);
    }
  }
  // ignore: unused_local_variable
  final _ = trapIds; // suppress unused warning

  await supabase.from('game_state').update({
    'property_ownership': ownership,
    'balances': balances,
    'get_out_of_jail_cards': goojfCards,
    'rent_modifiers': rentModifiers,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  await supabase.from('pending_trades').update({
    'status': 'accepted',
    'accepted_by': acceptedBy,
    'resolved_at': DateTime.now().toIso8601String(),
  }).eq('id', tradeId);

  await _writeLog(roomId, playerId, stateRow['turn_number'] as int, 'accept_trade', {'trade_id': tradeId, 'completed': true});

  return okJson({'trade_completed': true});
}

Future<Response> counterTrade(
  String roomId,
  String playerId,
  Map<String, dynamic> payload,
  Map<String, dynamic> config,
) async {
  final tradeId = payload['trade_id'] as String?;
  if (tradeId == null) return errorJson(400, 'MISSING_FIELD', 'trade_id required');

  // Cancel existing trade
  final trade = await supabase
      .from('pending_trades')
      .select()
      .eq('id', tradeId)
      .eq('room_id', roomId)
      .maybeSingle();

  if (trade == null) return errorJson(404, 'NOT_FOUND', 'Trade not found');

  final participants = List<String>.from(trade['participants'] as List);
  if (!participants.contains(playerId)) {
    return errorJson(403, 'NOT_PARTICIPANT', 'You are not part of this trade');
  }

  await supabase.from('pending_trades').update({
    'status': 'countered',
    'resolved_at': DateTime.now().toIso8601String(),
  }).eq('id', tradeId);

  final turnNum = await _getTurnNumber(roomId);
  await _writeLog(roomId, playerId, turnNum, 'counter_trade', {'original_trade_id': tradeId});

  // Propose counter as new trade, excluding the countered trade from conflict checks
  return proposeTrade(roomId, playerId, payload['counter'] as Map<String, dynamic>, config,
      excludeTradeId: tradeId, writeLog: false,);
}

Future<Response> rejectTrade(
  String roomId,
  String playerId,
  Map<String, dynamic> payload,
) async {
  final tradeId = payload['trade_id'] as String?;
  if (tradeId == null) return errorJson(400, 'MISSING_FIELD', 'trade_id required');

  final updated = await supabase
      .from('pending_trades')
      .update({
        'status': 'rejected',
        'resolved_at': DateTime.now().toIso8601String(),
      })
      .eq('id', tradeId)
      .eq('room_id', roomId)
      .select();

  if ((updated as List).isEmpty) {
    return errorJson(404, 'NOT_FOUND', 'Trade not found');
  }

  final turnNum = await _getTurnNumber(roomId);
  await _writeLog(roomId, playerId, turnNum, 'reject_trade', {'trade_id': tradeId});

  return okJson({'rejected': true});
}

Future<Response> cancelTrade(
  String roomId,
  String playerId,
  Map<String, dynamic> payload,
) async {
  final tradeId = payload['trade_id'] as String?;
  if (tradeId == null) return errorJson(400, 'MISSING_FIELD', 'trade_id required');

  final updated = await supabase
      .from('pending_trades')
      .update({
        'status': 'cancelled',
        'resolved_at': DateTime.now().toIso8601String(),
      })
      .eq('id', tradeId)
      .eq('room_id', roomId)
      .eq('proposer_id', playerId) // only proposer can cancel
      .select();

  if ((updated as List).isEmpty) {
    return errorJson(403, 'FORBIDDEN', 'Only the proposer can cancel a trade');
  }

  final turnNum = await _getTurnNumber(roomId);
  await _writeLog(roomId, playerId, turnNum, 'cancel_trade', {'trade_id': tradeId});

  return okJson({'cancelled': true});
}
