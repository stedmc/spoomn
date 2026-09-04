import 'package:spoomn_core/spoomn_core.dart';

import '../db/supabase_client.dart';

/// Rolls a just-finished game into each participant's permanent [player_stats]
/// row plus the [property_stats] / [trade_stats] breakdown tables. Called once,
/// right after `game_rooms.status` is set to `'finished'`.
Future<void> recordGameStats(String roomId) async {
  final players = ((await supabase
              .from('room_players')
              .select('player_id, seat_order, is_bankrupt')
              .eq('room_id', roomId)
              .order('seat_order')) as List)
      .cast<Map<String, dynamic>>();
  if (players.isEmpty) return;

  final state = await supabase
      .from('game_state')
      .select('turn_number, balances, property_ownership, houses, hotels, mortgaged')
      .eq('room_id', roomId)
      .single();

  final balances = state['balances'] as Map<String, dynamic>;
  final ownership = state['property_ownership'] as Map<String, dynamic>;
  final mortgaged = (state['mortgaged'] as List).cast<dynamic>();
  final turnNumber = state['turn_number'] as int;

  // Net worth = cash + owned property value (unmortgaged at full price, mortgaged
  // at mortgage value). Houses/hotels omitted -- their value isn't separately
  // tracked once built, only reconstructable via game_log, not worth it here.
  int netWorthOf(String playerId) {
    var worth = (balances[playerId] as int?) ?? 0;
    for (final entry in ownership.entries) {
      if (entry.value != playerId) continue;
      final square = Board.squares[int.parse(entry.key)];
      final isMortgaged = mortgaged.contains(int.parse(entry.key));
      worth += (isMortgaged ? square.mortgageValue : square.price) ?? 0;
    }
    return worth;
  }

  final ranked = [...players]..sort((a, b) {
      final aBankrupt = a['is_bankrupt'] as bool;
      final bBankrupt = b['is_bankrupt'] as bool;
      if (aBankrupt != bBankrupt) return aBankrupt ? 1 : -1;
      return netWorthOf(b['player_id'] as String)
          .compareTo(netWorthOf(a['player_id'] as String));
    });

  final placements = <String, int>{
    for (var i = 0; i < ranked.length; i++) ranked[i]['player_id'] as String: i + 1,
  };
  final winnerId = ranked.first['player_id'] as String;

  final playerIds = players.map((p) => p['player_id'] as String).toList();

  final existingStats = {
    for (final row in ((await supabase
                .from('player_stats')
                .select()
                .inFilter('profile_id', playerIds)) as List)
            .cast<Map<String, dynamic>>())
      row['profile_id'] as String: row,
  };

  final logRows = ((await supabase
              .from('game_log')
              .select('player_id, action, payload')
              .eq('room_id', roomId)) as List)
      .cast<Map<String, dynamic>>();

  int countAction(String playerId, String action) => logRows
      .where((r) => r['player_id'] == playerId && r['action'] == action)
      .length;

  int sumTax(String playerId) => logRows
      .where((r) => r['player_id'] == playerId && r['action'] == 'tax_payment')
      .fold(0, (sum, r) => sum + ((r['payload'] as Map)['amount'] as int? ?? 0));

  final monopolyOwner = <String, String>{}; // colourGroup -> owner, if complete
  for (final entry in Board.colourGroups.entries) {
    final owners = entry.value.map((sq) => ownership['$sq']).toSet();
    if (owners.length == 1 && owners.first != null) {
      monopolyOwner[entry.key] = owners.first as String;
    }
  }

  final statsUpserts = <Map<String, dynamic>>[];
  for (final playerId in playerIds) {
    final existing = existingStats[playerId];
    final oldGamesPlayed = existing?['games_played'] as int? ?? 0;
    final oldAvgPlacement = (existing?['avg_placement'] as num?)?.toDouble() ?? 0;
    final newGamesPlayed = oldGamesPlayed + 1;
    final placement = placements[playerId]!;
    final isWinner = playerId == winnerId;
    final netWorth = netWorthOf(playerId);
    final monopolies = monopolyOwner.values.where((o) => o == playerId).length;

    statsUpserts.add({
      'profile_id': playerId,
      'games_played': newGamesPlayed,
      'wins': (existing?['wins'] as int? ?? 0) + (isWinner ? 1 : 0),
      'losses': (existing?['losses'] as int? ?? 0) + (isWinner ? 0 : 1),
      'bankruptcies': (existing?['bankruptcies'] as int? ?? 0) +
          (players.firstWhere((p) => p['player_id'] == playerId)['is_bankrupt'] as bool
              ? 1
              : 0),
      'avg_placement':
          oldAvgPlacement + (placement - oldAvgPlacement) / newGamesPlayed,
      'peak_net_worth': [existing?['peak_net_worth'] as int? ?? 0, netWorth]
          .reduce((a, b) => a > b ? a : b),
      'properties_bought': (existing?['properties_bought'] as int? ?? 0) +
          countAction(playerId, 'buy_property'),
      'monopolies_completed':
          (existing?['monopolies_completed'] as int? ?? 0) + monopolies,
      'jail_visits':
          (existing?['jail_visits'] as int? ?? 0) + countAction(playerId, 'go_to_jail'),
      'tax_paid_total': (existing?['tax_paid_total'] as int? ?? 0) + sumTax(playerId),
      'fastest_win_turns': isWinner
          ? [existing?['fastest_win_turns'] as int?, turnNumber]
              .whereType<int>()
              .reduce((a, b) => a < b ? a : b)
          : existing?['fastest_win_turns'] as int?,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
  await supabase.from('player_stats').upsert(statsUpserts);

  // Property stats: final ownership snapshot, one increment per owned square.
  final propertyRows = ((await supabase
              .from('property_stats')
              .select()
              .inFilter('profile_id', playerIds)) as List)
      .cast<Map<String, dynamic>>();
  final propertyExisting = {
    for (final row in propertyRows)
      '${row['profile_id']}:${row['square_index']}': row['times_owned'] as int,
  };
  final propertyUpserts = <Map<String, dynamic>>[];
  for (final entry in ownership.entries) {
    final ownerId = entry.value as String?;
    if (ownerId == null || !playerIds.contains(ownerId)) continue;
    final squareIndex = int.parse(entry.key);
    final key = '$ownerId:$squareIndex';
    propertyUpserts.add({
      'profile_id': ownerId,
      'square_index': squareIndex,
      'times_owned': (propertyExisting[key] ?? 0) + 1,
    });
  }
  if (propertyUpserts.isNotEmpty) {
    await supabase.from('property_stats').upsert(propertyUpserts);
  }

  // Trade stats: every accepted trade in this room, both directions.
  final acceptedTrades = ((await supabase
              .from('pending_trades')
              .select('proposer_id, recipient_id')
              .eq('room_id', roomId)
              .eq('status', 'accepted')) as List)
      .cast<Map<String, dynamic>>();
  if (acceptedTrades.isNotEmpty) {
    final tradeRows = ((await supabase
                .from('trade_stats')
                .select()
                .inFilter('profile_id', playerIds)) as List)
        .cast<Map<String, dynamic>>();
    final tradeExisting = {
      for (final row in tradeRows)
        '${row['profile_id']}:${row['partner_id']}': row['trades_completed'] as int,
    };
    final tradeCounts = <String, int>{};
    for (final trade in acceptedTrades) {
      final a = trade['proposer_id'] as String;
      final b = trade['recipient_id'] as String;
      tradeCounts['$a:$b'] = (tradeCounts['$a:$b'] ?? 0) + 1;
      tradeCounts['$b:$a'] = (tradeCounts['$b:$a'] ?? 0) + 1;
    }
    final tradeUpserts = tradeCounts.entries.map((e) {
      final parts = e.key.split(':');
      final key = '${parts[0]}:${parts[1]}';
      return {
        'profile_id': parts[0],
        'partner_id': parts[1],
        'trades_completed': (tradeExisting[key] ?? 0) + e.value,
      };
    }).toList();
    await supabase.from('trade_stats').upsert(tradeUpserts);
  }
}
