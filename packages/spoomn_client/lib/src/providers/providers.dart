import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:spoomn_core/spoomn_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'providers.g.dart';

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

@riverpod
String? currentUserId(CurrentUserIdRef ref) =>
    Supabase.instance.client.auth.currentUser?.id;

// ---------------------------------------------------------------------------
// Game room
// ---------------------------------------------------------------------------

@riverpod
Stream<GameRoom> gameRoom(GameRoomRef ref, String roomId) {
  return Supabase.instance.client
      .from('game_rooms')
      .stream(primaryKey: ['id'])
      .eq('id', roomId)
      .map((rows) => GameRoom.fromJson(rows.first));
}

// ---------------------------------------------------------------------------
// Game state
// ---------------------------------------------------------------------------

@riverpod
Stream<GameState> gameState(GameStateRef ref, String roomId) async* {
  // Eager REST fetch so data is available before the WebSocket channel is
  // confirmed — avoids the stream getting stuck when the initial query fires
  // before the realtime subscription is established.
  try {
    final row = await Supabase.instance.client
        .from('game_state')
        .select()
        .eq('room_id', roomId)
        .maybeSingle();
    if (row != null) yield GameState.fromJson(row as Map<String, dynamic>);
  } catch (_) {}
  yield* Supabase.instance.client
      .from('game_state')
      .stream(primaryKey: ['room_id'])
      .eq('room_id', roomId)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => GameState.fromJson(rows.first));
}

// ---------------------------------------------------------------------------
// Players
// ---------------------------------------------------------------------------

@riverpod
Stream<List<RoomPlayer>> roomPlayers(RoomPlayersRef ref, String roomId) {
  return Supabase.instance.client
      .from('room_players')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .asyncMap((rows) async {
        final seen = <String>{};
        final activeRows = rows
            .where((r) => r['left_at'] == null)
            .where((r) => seen.add(r['player_id'] as String))
            .toList();
        final playerIds = activeRows.map((r) => r['player_id'] as String).toList();
        if (playerIds.isEmpty) return <RoomPlayer>[];

        final profiles = await Supabase.instance.client
            .from('profiles')
            .select('id, display_name')
            .inFilter('id', playerIds);

        final nameMap = {
          for (final p in profiles) p['id'] as String: p['display_name'] as String?,
        };

        return activeRows.map((r) {
          final pid = r['player_id'] as String;
          return RoomPlayer.fromJson({...r, 'display_name': nameMap[pid]});
        }).toList();
      });
}

@riverpod
RoomPlayer? myPlayer(MyPlayerRef ref, String roomId) {
  final players = ref.watch(roomPlayersProvider(roomId)).valueOrNull ?? [];
  final myId = ref.watch(currentUserIdProvider);
  return players.where((p) => p.playerId == myId).firstOrNull;
}

@riverpod
bool isMyTurn(IsMyTurnRef ref, String roomId) {
  final room = ref.watch(gameRoomProvider(roomId)).valueOrNull;
  final myId = ref.watch(currentUserIdProvider);
  return room?.currentPlayerId == myId;
}

// ---------------------------------------------------------------------------
// Active traps (RLS filters invisible traps from other players automatically)
// ---------------------------------------------------------------------------

@riverpod
Stream<List<ActiveTrap>> activeTraps(ActiveTrapsRef ref, String roomId) {
  return Supabase.instance.client
      .from('active_traps')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .map((rows) => rows.map(ActiveTrap.fromJson).toList());
}

// ---------------------------------------------------------------------------
// Room config (non-annotated to avoid build_runner dependency for new fields)
// ---------------------------------------------------------------------------

final roomConfigProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, roomId) async* {
  try {
    final row = await Supabase.instance.client
        .from('room_configs')
        .select()
        .eq('room_id', roomId)
        .maybeSingle();
    if (row != null) yield row as Map<String, dynamic>;
  } catch (_) {}
  yield* Supabase.instance.client
      .from('room_configs')
      .stream(primaryKey: ['room_id'])
      .eq('room_id', roomId)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => rows.first as Map<String, dynamic>);
});

final draftRoomConfigProvider = StateProvider.family<Map<String, dynamic>?, String>((ref, roomId) => null);

final pendingTradesProvider = StreamProvider.family<List<Map<String, dynamic>>, String>(
  (ref, roomId) async* {
    try {
      final rows = await Supabase.instance.client
          .from('pending_trades')
          .select()
          .eq('room_id', roomId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      yield (rows as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    yield* Supabase.instance.client
        .from('pending_trades')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .map((rows) => rows
            .where((r) => r['status'] == 'pending')
            .cast<Map<String, dynamic>>()
            .toList());
  },
);

final isDebugModeProvider = Provider.family<bool, String>((ref, roomId) {
  final config = ref.watch(roomConfigProvider(roomId));
  return config.valueOrNull?['debug_mode'] as bool? ?? false;
});

// ---------------------------------------------------------------------------
// Game log
// ---------------------------------------------------------------------------

@riverpod
Stream<List<Map<String, dynamic>>> gameLog(GameLogRef ref, String roomId) {
  return Supabase.instance.client
      .from('game_log')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .order('id', ascending: false)
      .limit(50)
      .map((rows) => rows.cast<Map<String, dynamic>>());
}
