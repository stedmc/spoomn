# Realtime Sync

Supabase Realtime delivers Postgres row changes to all subscribed clients. No custom WebSocket server needed -- the Dart Shelf server writes to Postgres; Supabase handles broadcast.

---

## How It Works

```
Server writes to game_state
       │
       ▼
Postgres WAL (Write-Ahead Log)
       │
       ▼
Supabase Realtime engine detects row change
       │
       ▼
Broadcasts to all clients subscribed to that room_id
       │
       ▼
Client Riverpod StreamProvider receives event → state updates → Flame re-renders
```

Latency: typically 50--150ms from server write to client render. Acceptable for a turn-based board game.

---

## Client Subscription Setup

Each client subscribes to five channels on entering a room. All filtered by `room_id`.

```dart
final supabase = Supabase.instance.client;

// 1. Board state -- most frequent updates
final gameStateStream = supabase
  .from('game_state')
  .stream(primaryKey: ['room_id'])
  .eq('room_id', roomId);

// 2. Room metadata -- pause, finish, player count
final roomStream = supabase
  .from('game_rooms')
  .stream(primaryKey: ['id'])
  .eq('id', roomId);

// 3. Player roster -- join, disconnect, bankruptcy
final playersStream = supabase
  .from('room_players')
  .stream(primaryKey: ['id'])
  .eq('room_id', roomId);

// 4. Trade offers -- only relevant participants need this
final tradeStream = supabase
  .from('pending_trades')
  .stream(primaryKey: ['id'])
  .eq('room_id', roomId)
  .filter('status', 'eq', 'pending');

// 5. Event feed -- append-only log for UI feed
final logStream = supabase
  .from('game_log')
  .stream(primaryKey: ['id'])
  .eq('room_id', roomId)
  .order('created_at', ascending: false)
  .limit(50);
```

Each stream feeds a Riverpod `StreamProvider`. Flame components and Flutter widgets watch the relevant providers.

---

## Riverpod Integration

```dart
@riverpod
Stream<GameState> gameState(GameStateRef ref, String roomId) {
  return Supabase.instance.client
    .from('game_state')
    .stream(primaryKey: ['room_id'])
    .eq('room_id', roomId)
    .map((rows) => GameState.fromJson(rows.first));
}

@riverpod
Stream<GameRoom> gameRoom(GameRoomRef ref, String roomId) {
  return Supabase.instance.client
    .from('game_rooms')
    .stream(primaryKey: ['id'])
    .eq('id', roomId)
    .map((rows) => GameRoom.fromJson(rows.first));
}
```

Flame components read state via a `WidgetRef` bridge -- a thin notifier that pushes Riverpod state into the Flame game loop on each update.

---

## Disconnect and Reconnect

Supabase Flutter SDK handles reconnection automatically on network restore. No custom retry logic needed on the client.

On reconnect:

1. Supabase re-establishes Realtime channel
2. `stream()` re-emits current row value immediately
3. Client state snaps to latest server state
4. Any missed updates are irrelevant -- client always gets current state, not a delta

No event replay, no delta patching. Full state on every update. Simple and correct.

### Marking Connection Status

Server does not track connection state via WebSocket heartbeat (no direct server--client socket). Instead, clients write their own `is_connected` flag on `room_players`:

```
On enter room:  POST /api/rooms/{id}/connect    → server sets is_connected = true
On app pause:   POST /api/rooms/{id}/disconnect → server sets is_connected = false
On app resume:  POST /api/rooms/{id}/connect    → server sets is_connected = true
```

`room_players.is_connected` broadcasts via Realtime to all players -- used to show online/offline indicators next to player tokens.

Flutter `AppLifecycleState` listener drives connect/disconnect calls:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  switch (state) {
    case AppLifecycleState.resumed:
      _gameService.connect(roomId);
    case AppLifecycleState.paused:
    case AppLifecycleState.detached:
      _gameService.disconnect(roomId);
    default:
      break;
  }
}
```

---

## Pause Detection

If all players disconnect, the server does not auto-pause. Pause is always an explicit action (host taps "Pause Game").

However, the host client shows a warning banner when `is_connected = false` for all other players -- nudging the host to pause if everyone has dropped.

Auto-pause could be added later via a Supabase Edge Function that watches `room_players` and fires when all `is_connected` flags are false. Not in initial scope.

---

## Realtime and RLS

Supabase Realtime respects RLS policies. A client only receives broadcasts for rows they can SELECT under RLS. Since all subscriptions are filtered by `room_id` and RLS gates on room membership, a player cannot receive another room's events even if they construct a malicious subscription.

---

## Optimistic UI

No optimistic updates on the client. Reason: game outcomes (dice rolls, card draws, rent calculations) are computed server-side and cannot be predicted client-side. Attempting optimistic updates would require duplicating server logic on the client, creating drift risk.

Instead: active player sees a loading indicator from the moment they submit an action until the Realtime update arrives (~100--200ms round trip). Acceptable latency for a board game.

---

## Subscription Teardown

On leaving a room (game over, explicit exit, or navigation away), all channels are unsubscribed:

```dart
@override
void dispose() {
  supabase.removeAllChannels();
  super.dispose();
}
```

Prevents ghost subscriptions accumulating across game sessions.

---

## Failure Modes

| Failure | Behaviour |
|---------|-----------|
| Client loses network | Supabase SDK buffers, reconnects automatically on restore |
| Server crashes mid-action | Action may not complete; game_state not updated; client retries action on reconnect if turn still belongs to them |
| Supabase Realtime outage | Clients fall back to polling `game_state` every 5s (degraded mode) |
| Duplicate broadcast received | Idempotent -- state update replaces current state, not appended |

Polling fallback for Realtime outage:

```dart
// Activated only when Realtime channel status = 'CLOSED' for > 10s
Timer.periodic(const Duration(seconds: 5), (_) async {
  final state = await supabase
    .from('game_state')
    .select()
    .eq('room_id', roomId)
    .single();
  ref.read(gameStateProvider(roomId).notifier).update(state);
});
```
