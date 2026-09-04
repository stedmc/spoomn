import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:spoomn_core/spoomn_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'providers.g.dart';

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

@riverpod
String? currentUserId(Ref ref) =>
    Supabase.instance.client.auth.currentUser?.id;

// ---------------------------------------------------------------------------
// Game room
// ---------------------------------------------------------------------------

@riverpod
Stream<GameRoom> gameRoom(Ref ref, String roomId) {
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
Stream<GameState> gameState(Ref ref, String roomId) async* {
  // Eager REST fetch so data is available before the WebSocket channel is
  // confirmed — avoids the stream getting stuck when the initial query fires
  // before the realtime subscription is established.
  try {
    final row = await Supabase.instance.client
        .from('game_state')
        .select()
        .eq('room_id', roomId)
        .maybeSingle();
    if (row != null) yield GameState.fromJson(row);
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
Stream<List<RoomPlayer>> roomPlayers(Ref ref, String roomId) {
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

// ---------------------------------------------------------------------------
// Presence (who's actually got the page open right now)
// ---------------------------------------------------------------------------

/// Tracks which players currently have this room open via a Supabase Realtime
/// Presence channel. Unlike [RoomPlayer.isConnected] (a DB flag flipped by
/// explicit connect/disconnect calls, which can go stale if the client never
/// gets to call disconnect), presence is driven by the websocket itself: the
/// server evicts a client's presence as soon as its socket drops, including
/// on tab close/crash/network loss.
@riverpod
Stream<Set<String>> onlinePlayerIds(Ref ref, String roomId) {
  final controller = StreamController<Set<String>>();
  final channel = Supabase.instance.client.channel('presence:room:$roomId');

  void emit() {
    if (controller.isClosed) return;
    final ids = <String>{
      for (final state in channel.presenceState())
        for (final presence in state.presences)
          if (presence.payload['player_id'] is String)
            presence.payload['player_id'] as String,
    };
    controller.add(ids);
  }

  channel
      .onPresenceSync((_) => emit())
      .onPresenceJoin((_) => emit())
      .onPresenceLeave((_) => emit())
      .subscribe((status, error) async {
    if (status == RealtimeSubscribeStatus.subscribed) {
      final myId = Supabase.instance.client.auth.currentUser?.id;
      if (myId != null) {
        await channel.track({'player_id': myId});
      }
      emit();
    }
  });

  ref.onDispose(() {
    unawaited(channel.untrack());
    unawaited(Supabase.instance.client.removeChannel(channel));
    controller.close();
  });

  return controller.stream;
}

@riverpod
RoomPlayer? myPlayer(Ref ref, String roomId) {
  final players = ref.watch(roomPlayersProvider(roomId)).value ?? [];
  final myId = ref.watch(currentUserIdProvider);
  return players.where((p) => p.playerId == myId).firstOrNull;
}

@riverpod
bool isMyTurn(Ref ref, String roomId) {
  final room = ref.watch(gameRoomProvider(roomId)).value;
  final myId = ref.watch(currentUserIdProvider);
  return room?.currentPlayerId == myId;
}

// ---------------------------------------------------------------------------
// Active traps (RLS filters invisible traps from other players automatically)
// ---------------------------------------------------------------------------

@riverpod
Stream<List<ActiveTrap>> activeTraps(Ref ref, String roomId) {
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
  // Always yield from the REST fetch so the UI never gets stuck on a spinner
  // while waiting for the realtime stream's first event. If the row doesn't
  // exist yet (race during room creation), yield an empty map so default rules
  // are displayed immediately.
  try {
    final row = await Supabase.instance.client
        .from('room_configs')
        .select()
        .eq('room_id', roomId)
        .maybeSingle();
    yield row ?? {};
  } catch (_) {
    yield {};
  }
  yield* Supabase.instance.client
      .from('room_configs')
      .stream(primaryKey: ['room_id'])
      .eq('room_id', roomId)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => rows.first);
});

final draftRoomConfigProvider = StateProvider.family<Map<String, dynamic>?, String>((ref, roomId) => null);

final resetConfigKeyProvider = StateProvider.family<String?, String>((ref, roomId) => null);

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
  return config.value?['debug_mode'] as bool? ?? false;
});

// ---------------------------------------------------------------------------
// Pawn photos (non-annotated, mirrors roomConfigProvider, to avoid touching
// the generated RoomPlayer model just for a board-rendering detail)
// ---------------------------------------------------------------------------

final pawnPhotoUrlsProvider = StreamProvider.family<Map<String, String?>, String>(
  (ref, roomId) {
    return Supabase.instance.client
        .from('room_players')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .asyncMap((rows) async {
          final playerIds = rows
              .where((r) => r['left_at'] == null)
              .map((r) => r['player_id'] as String)
              .toSet()
              .toList();
          if (playerIds.isEmpty) return <String, String?>{};
          final profiles = await Supabase.instance.client
              .from('profiles')
              .select('id, pawn_photo_url')
              .inFilter('id', playerIds);
          return {
            for (final p in profiles) p['id'] as String: p['pawn_photo_url'] as String?,
          };
        });
  },
);

// ---------------------------------------------------------------------------
// Profile (current user's own row, editable from the profile screen)
// ---------------------------------------------------------------------------

final myProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return Stream.value(null);
  return Supabase.instance.client
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('id', userId)
      .map((rows) => rows.firstOrNull);
});

final myStatsProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return null;
  return Supabase.instance.client
      .from('player_stats')
      .select()
      .eq('profile_id', userId)
      .maybeSingle();
});

// ---------------------------------------------------------------------------
// Game log
// ---------------------------------------------------------------------------

@riverpod
Stream<List<Map<String, dynamic>>> gameLog(Ref ref, String roomId) {
  return Supabase.instance.client
      .from('game_log')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .order('id', ascending: false)
      .limit(50)
      .map((rows) => rows.cast<Map<String, dynamic>>());
}
