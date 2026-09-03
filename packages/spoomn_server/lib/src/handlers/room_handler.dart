import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart' show params;
import 'package:spoomn_core/spoomn_core.dart';

import '../db/supabase_client.dart';
import '../middleware/auth_middleware.dart';

Future<Response> createRoom(Request request, String playerId) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;

  final roomCode = await _generateRoomCode();
  final maxPlayers = (body['max_players'] as int?) ?? 8;
  final playMode = (body['play_mode'] as String?) ?? 'realtime';
  final config = (body['config'] as Map<String, dynamic>?) ?? {};

  final room = await supabase.from('game_rooms').insert({
    'room_code': roomCode,
    'host_id': playerId,
    'max_players': maxPlayers,
    'play_mode': playMode,
  }).select().single();

  await supabase.from('room_configs').insert({
    'room_id': room['id'],
    ...config,
  });

  await supabase.from('room_players').insert({
    'room_id': room['id'],
    'player_id': playerId,
    'is_connected': true,
  });

  await supabase
      .from('game_rooms')
      .update({'player_count': 1}).eq('id', room['id']);

  return okJson({'room': room, 'room_code': roomCode});
}

Future<Response> joinRoom(Request request, String playerId) async {
  final roomCode = params(request, 'roomCode')!;

  final room = await supabase
      .from('game_rooms')
      .select()
      .eq('room_code', roomCode)
      .maybeSingle();

  if (room == null) return errorJson(404, 'NOT_FOUND', 'Room not found');
  if (room['status'] != 'lobby') {
    return errorJson(400, 'ROOM_NOT_IN_LOBBY', 'Game already started -- use rejoin');
  }

  final existing = await supabase
      .from('room_players')
      .select('id, left_at')
      .eq('room_id', room['id'] as String)
      .eq('player_id', playerId)
      .maybeSingle();

  if (existing != null) {
    if (existing['left_at'] != null) {
      return errorJson(403, 'PLAYER_LEFT', 'You left this room -- use rejoin');
    }
    // Already a member; treat as idempotent success
    return okJson({'room': room});
  }

  if ((room['player_count'] as int) >= (room['max_players'] as int)) {
    return errorJson(400, 'ROOM_FULL', 'Room is full');
  }

  await supabase.from('room_players').insert({
    'room_id': room['id'],
    'player_id': playerId,
    'is_connected': true,
  });

  await supabase.from('game_rooms').update({
    'player_count': (room['player_count'] as int) + 1,
  }).eq('id', room['id']);

  return okJson({'room': room});
}

Future<Response> rejoinRoom(Request request, String playerId) async {
  final roomId = params(request, 'roomId')!;
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final deviceToken = body['device_token'] as String?;

  final existing = await supabase
      .from('room_players')
      .select()
      .eq('room_id', roomId)
      .eq('player_id', playerId)
      .maybeSingle();

  if (existing == null && deviceToken != null) {
    // Anonymous rejoin: match via device_token
    final profile = await supabase
        .from('profiles')
        .select('id')
        .eq('device_token', deviceToken)
        .maybeSingle();

    if (profile != null) {
      final byDevice = await supabase
          .from('room_players')
          .select()
          .eq('room_id', roomId)
          .eq('player_id', profile['id'] as String)
          .maybeSingle();

      if (byDevice != null && byDevice['left_at'] == null) {
        await supabase
            .from('room_players')
            .update({'is_connected': true})
            .eq('id', byDevice['id'] as String);
        return okJson({'rejoined': true});
      }
    }
    return errorJson(403, 'NOT_A_MEMBER', 'Player not found in this room');
  }

  if (existing == null) {
    return errorJson(403, 'NOT_A_MEMBER', 'Player not found in this room');
  }
  if (existing['left_at'] != null) {
    return errorJson(403, 'PLAYER_LEFT', 'Player explicitly left this room');
  }

  await supabase
      .from('room_players')
      .update({'is_connected': true})
      .eq('id', existing['id'] as String);

  return okJson({'rejoined': true});
}

Future<Response> startRoom(Request request, String playerId) async {
  final roomId = params(request, 'roomId')!;

  final room = await supabase
      .from('game_rooms')
      .select()
      .eq('id', roomId)
      .maybeSingle();

  if (room == null) return errorJson(404, 'NOT_FOUND', 'Room not found');
  if (room['host_id'] != playerId) {
    return errorJson(403, 'NOT_HOST', 'Only the host can start the game');
  }
  if (room['status'] != 'lobby') {
    return errorJson(400, 'ALREADY_STARTED', 'Game already started');
  }

  final playerCount = room['player_count'] as int;
  if (playerCount < 1) {
    return errorJson(400, 'TOO_FEW_PLAYERS', 'Need at least 1 player to start');
  }

  await supabase
      .from('game_rooms')
      .update({'status': 'starting'})
      .eq('id', roomId);

  return okJson({'started': true});
}

Future<Response> beginGame(Request request, String playerId) async {
  final roomId = params(request, 'roomId')!;

  final room = await supabase
      .from('game_rooms')
      .select()
      .eq('id', roomId)
      .maybeSingle();

  if (room == null) return errorJson(404, 'NOT_FOUND', 'Room not found');
  if (room['host_id'] != playerId) {
    return errorJson(403, 'NOT_HOST', 'Only the host can begin the game');
  }
  if (room['status'] != 'starting') {
    return errorJson(400, 'NOT_STARTING', 'Room is not in starting state');
  }

  final config = await supabase
      .from('room_configs')
      .select()
      .eq('room_id', roomId)
      .single();

  final players = await supabase
      .from('room_players')
      .select('id, player_id')
      .eq('room_id', roomId)
      .isFilter('left_at', null)
      .order('joined_at');

  final turnOrderMethod = config['turn_order_method'] as String? ?? 'random';
  final orderedPlayers = _assignSeatOrder(
    players.cast<Map<String, dynamic>>(),
    turnOrderMethod,
  );

  const colours = ['red', 'blue', 'green', 'yellow', 'purple', 'orange', 'pink', 'black'];
  for (var i = 0; i < orderedPlayers.length; i++) {
    await supabase.from('room_players').update({
      'seat_order': i,
      'token_colour': colours[i],
    }).eq('id', orderedPlayers[i]['id'] as String);
  }

  final startingMoney = (config['starting_money'] as int?) ?? 1500;
  final balances = <String, dynamic>{
    for (final p in orderedPlayers) p['player_id'] as String: startingMoney,
  };
  final boardPositions = <String, dynamic>{
    for (final p in orderedPlayers) p['player_id'] as String: 0,
  };
  final jailStatus = <String, dynamic>{
    for (final p in orderedPlayers)
      p['player_id'] as String: {
        'in_jail': false,
        'is_jailbreaking': false,
        'turns_in_jail': 0,
        'mandatory_turns_remaining': 0,
        'catch_count': 0,
        'effective_fine': config['jail_fine'] ?? 50,
        'has_card': false,
      },
  };

  final freeParkingStarting =
      (config['free_parking_jackpot'] as bool? ?? false)
          ? (config['free_parking_starting_amount'] as int? ?? 0)
          : 0;

  final customCC = config['custom_community_chest'] as List<dynamic>?;
  final customCh = config['custom_chance'] as List<dynamic>?;
  final ccSize = customCC?.length ?? Cards.defaultCommunityChest.length;
  final chSize = customCh?.length ?? Cards.defaultChance.length;
  final ccDeck = Cards.shuffledDeck(ccSize);
  final chDeck = Cards.shuffledDeck(chSize);

  await supabase.from('game_state').insert({
    'room_id': roomId,
    'turn_number': 1,
    'phase': 'roll',
    'consecutive_doubles': 0,
    'board_positions': boardPositions,
    'property_ownership': {},
    'houses': {},
    'hotels': {},
    'mortgaged': [],
    'balances': balances,
    'jail_status': jailStatus,
    'get_out_of_jail_cards': {},
    'community_chest_deck': ccDeck,
    'community_chest_index': 0,
    'chance_deck': chDeck,
    'chance_index': 0,
    'free_parking_pot': freeParkingStarting,
    'active_police_pawns': [],
    'rent_modifiers': {},
    'repayment_plans': [],
    'updated_at': DateTime.now().toIso8601String(),
  });

  final firstPlayerId = orderedPlayers.first['player_id'] as String;
  final now = DateTime.now().toIso8601String();

  await supabase.from('game_rooms').update({
    'status': 'active',
    'started_at': now,
    'current_player_id': firstPlayerId,
    'turn_started_at': now,
  }).eq('id', roomId);

  return okJson({'started': true, 'first_player': firstPlayerId});
}

List<Map<String, dynamic>> _assignSeatOrder(
  List<Map<String, dynamic>> players,
  String method,
) {
  return switch (method) {
    'random' => (List<Map<String, dynamic>>.from(players)..shuffle(Random.secure())),
    // host_assigned and highest_roll both use join order for now
    // highest_roll TODO: implement pre-game dice roll
    _ => List<Map<String, dynamic>>.from(players),
  };
}

Future<Response> pauseRoom(Request request, String playerId) async {
  final roomId = params(request, 'roomId')!;
  await supabase.from('game_rooms').update({
    'status': 'paused',
    'paused_at': DateTime.now().toIso8601String(),
  }).eq('id', roomId);
  return okJson({'paused': true});
}

Future<Response> resumeRoom(Request request, String playerId) async {
  final roomId = params(request, 'roomId')!;
  await supabase.from('game_rooms').update({
    'status': 'active',
    'paused_at': null,
  }).eq('id', roomId);
  return okJson({'resumed': true});
}

Future<Response> connectPlayer(Request request, String playerId) async {
  final roomId = params(request, 'roomId')!;
  await supabase
      .from('room_players')
      .update({'is_connected': true})
      .eq('room_id', roomId)
      .eq('player_id', playerId);
  return okJson({'connected': true});
}

Future<Response> disconnectPlayer(Request request, String playerId) async {
  final roomId = params(request, 'roomId')!;
  await supabase
      .from('room_players')
      .update({'is_connected': false})
      .eq('room_id', roomId)
      .eq('player_id', playerId);
  return okJson({'disconnected': true});
}

Future<Response> listMyGames(Request request, String playerId) async {
  final rows = await supabase
      .from('room_players')
      .select('room_id, game_rooms!inner(*)')
      .eq('player_id', playerId)
      .isFilter('left_at', null)
      .inFilter('game_rooms.status', ['lobby', 'active', 'paused']);

  return okJson({'games': rows});
}

Future<Response> updatePushToken(Request request, String playerId) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  await supabase.from('profiles').update({
    'push_token': body['token'],
    'push_platform': body['platform'],
  }).eq('id', playerId);
  return okJson({'updated': true});
}

Future<Response> debugAddPlayer(Request request, String playerId) async {
  final roomId = params(request, 'roomId')!;

  final room = await supabase
      .from('game_rooms')
      .select('host_id, status, player_count, max_players')
      .eq('id', roomId)
      .maybeSingle();

  if (room == null) return errorJson(404, 'NOT_FOUND', 'Room not found');
  if (room['host_id'] != playerId) {
    return errorJson(403, 'NOT_HOST', 'Only host can add debug players');
  }
  if (room['status'] != 'lobby') {
    return errorJson(400, 'NOT_IN_LOBBY', 'Can only add players in lobby');
  }

  final config = await supabase
      .from('room_configs')
      .select('debug_mode')
      .eq('room_id', roomId)
      .single();

  if (!(config['debug_mode'] as bool? ?? false)) {
    return errorJson(403, 'FORBIDDEN', 'Debug mode not enabled');
  }

  final playerCount = room['player_count'] as int;
  final maxPlayers = room['max_players'] as int;
  if (playerCount >= maxPlayers) {
    return errorJson(400, 'ROOM_FULL', 'Room is at max capacity ($maxPlayers players)');
  }

  // Count active players for bot numbering
  final seated = await supabase
      .from('room_players')
      .select('id')
      .eq('room_id', roomId)
      .isFilter('left_at', null);
  final botNumber = (seated as List).length + 1;
  final displayName = 'Bot $botNumber';

  final botId = _generateUuid();
  await supabase.from('profiles').insert({
    'id': botId,
    'display_name': displayName,
    'is_anonymous': true,
    'is_bot': true,
  });

  await supabase.from('room_players').insert({
    'room_id': roomId,
    'player_id': botId,
    'is_connected': true,
  });

  await supabase
      .from('game_rooms')
      .update({'player_count': playerCount + 1})
      .eq('id', roomId);

  return okJson({'added': true, 'player_id': botId, 'display_name': displayName});
}

Future<Response> removePlayer(Request request, String playerId) async {
  final roomId = params(request, 'roomId')!;
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final targetPlayerId = body['player_id'] as String?;

  if (targetPlayerId == null) {
    return errorJson(400, 'MISSING_FIELD', 'player_id required');
  }

  final room = await supabase
      .from('game_rooms')
      .select('host_id, status, player_count')
      .eq('id', roomId)
      .maybeSingle();

  if (room == null) return errorJson(404, 'NOT_FOUND', 'Room not found');
  if (room['status'] != 'lobby') {
    return errorJson(400, 'NOT_IN_LOBBY', 'Can only remove players in lobby');
  }

  // Host can remove anyone (except themselves); players can only remove themselves
  final isHost = room['host_id'] == playerId;
  if (!isHost && targetPlayerId != playerId) {
    return errorJson(403, 'FORBIDDEN', 'Only the host can remove other players');
  }
  if (isHost && targetPlayerId == playerId) {
    return errorJson(400, 'RULE_VIOLATION', 'Host cannot remove themselves');
  }

  final updated = await supabase
      .from('room_players')
      .update({'left_at': DateTime.now().toIso8601String()})
      .eq('room_id', roomId)
      .eq('player_id', targetPlayerId)
      .isFilter('left_at', null)
      .select();

  if ((updated as List).isEmpty) {
    return errorJson(404, 'NOT_FOUND', 'Player not found in this room');
  }

  final newCount = (room['player_count'] as int) - 1;
  await supabase
      .from('game_rooms')
      .update({'player_count': newCount.clamp(0, 999)})
      .eq('id', roomId);

  return okJson({'removed': true, 'player_id': targetPlayerId});
}

Future<Response> updateRoomConfig(Request request, String playerId) async {
  final roomId = params(request, 'roomId')!;
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;

  final room = await supabase
      .from('game_rooms')
      .select('host_id, status')
      .eq('id', roomId)
      .maybeSingle();

  if (room == null) return errorJson(404, 'NOT_FOUND', 'Room not found');
  if (room['host_id'] != playerId) {
    return errorJson(403, 'NOT_HOST', 'Only the host can update config');
  }
  if (room['status'] != 'lobby' && room['status'] != 'starting') {
    return errorJson(400, 'NOT_IN_LOBBY', 'Config can only be changed before the game starts');
  }

  const allowedFields = {
    'debug_mode',
    'starting_money', 'bank_unlimited', 'bank_starting_amount', 'house_limit', 'hotel_limit', 'turn_order_method',
    'dice_count', 'dice_sides', 'doubles_enabled', 'doubles_extra_turn', 'jail_on_consecutive_doubles',
    'go_salary', 'go_landing_bonus',
    'auto_claim_rent',
    'income_tax_type', 'income_tax_amount', 'income_tax_percentage', 'super_tax_amount',
    'free_parking_jackpot', 'free_parking_starting_amount',
    'max_turn_time_secs',
    'jail_fine', 'jail_turns', 'jail_doubles_escape', 'collect_go_while_in_jail',
    'jailbreak_enabled', 'jailbreak_mandatory_turns', 'jailbreak_fine_multiplier', 'police_check_mode', 'police_duration',
    'must_build_evenly', 'hotel_requires_four_houses', 'houses_returned_on_hotel', 'build_own_turn_only', 'sell_building_rate',
    'mortgage_rate', 'unmortgage_interest_rate', 'trade_mortgaged_properties', 'mortgage_transfer_penalty',
    'auction_on_decline', 'auction_style', 'auction_starting_bid', 'auction_min_raise', 'auction_time_per_bid_secs',
    'auction_blind_time_secs', 'auction_min_bid', 'dutch_start_price', 'dutch_decrement', 'dutch_interval_secs', 'dutch_floor_price',
    'trade_any_turn', 'multi_party_trades', 'trade_futures', 'trade_timeout_secs',
    'winning_condition', 'net_worth_target', 'net_worth_check', 'turn_limit', 'time_limit_mins',
    'bankruptcy_assets_to', 'allow_bankruptcy_negotiation', 'negotiation_timeout_secs', 'repayment_interest_rate',
    'loans_enabled', 'loan_amount', 'loan_interest_rate', 'max_loans_per_player',
    'async_turn_timeout_hours', 'async_turn_reminder_hours',
  };
  final updates = {
    for (final e in body.entries)
      if (allowedFields.contains(e.key)) e.key: e.value,
  };

  if (updates.isEmpty) {
    return errorJson(400, 'NO_VALID_FIELDS', 'No recognised config fields provided');
  }

  await supabase.from('room_configs').update(updates).eq('room_id', roomId);
  return okJson({'updated': true});
}

String _generateUuid() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String h(int b) => b.toRadixString(16).padLeft(2, '0');
  final hex = bytes.map(h).toList();
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}'
      '-${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}'
      '-${hex.sublist(10).join()}';
}

Future<String> _generateRoomCode() async {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rand = Random.secure();

  for (var attempt = 0; attempt < 5; attempt++) {
    final code = List.generate(
      6,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();

    final existing = await supabase
        .from('game_rooms')
        .select('id')
        .eq('room_code', code)
        .maybeSingle();

    if (existing == null) return code;
  }

  throw StateError('Failed to generate unique room code after 5 attempts');
}
