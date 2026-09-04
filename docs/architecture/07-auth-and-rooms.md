# Auth and Rooms

## Authentication

### Anonymous Session

Every player gets a Supabase anonymous session on first launch. No sign-up required. The SDK persists the session in device secure storage (mobile) or `localStorage` (web) automatically.

On first launch:

```dart
Future<void> initAuth() async {
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) {
    await Supabase.instance.client.auth.signInAnonymously();
  }
  await _ensureProfile();
}

Future<void> _ensureProfile() async {
  final userId = Supabase.instance.client.auth.currentUser!.id;
  final deviceToken = await _getOrCreateDeviceToken(); // from secure storage

  await Supabase.instance.client.from('profiles').upsert({
    'id': userId,
    'display_name': _generateGuestName(), // e.g. 'Guest_K7X2'
    'is_anonymous': true,
    'device_token': deviceToken,
  }, onConflict: 'id');
}
```

`device_token` is a UUID generated once and stored permanently in device secure storage. It survives app reinstall on Android (backed up by Google), and is preserved on iOS via Keychain. On web it is stored in `localStorage` -- not as durable.

### Named Account

Players may upgrade at any time via the profile screen. Supabase links the anonymous session to the new account -- all game history is preserved.

```dart
// Email magic link
await Supabase.instance.client.auth.updateUser(
  UserAttributes(email: email),
);

// Google OAuth
await Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.google);

// Email + password
await Supabase.instance.client.auth.updateUser(
  UserAttributes(email: email, password: password),
);
```

After upgrade: `profiles.is_anonymous` set to `false`. Cross-device rejoin now works via `auth.uid()` rather than `device_token`.

A player who already has a named account on another device signs in normally
(`signOut()` then `signInWithPassword`) rather than upgrading -- this switches
`auth.uid()` to the existing account, leaving the current device's anonymous
session (and its history) behind.

Named accounts also carry `profiles.avatar_url` and `profiles.pawn_photo_url`
(both nullable, uploaded to the public `avatars` Storage bucket at
`{user_id}/avatar.*` / `{user_id}/pawn.*`). `pawn_photo_url`, when set, is
rendered as the player's board token instead of a flat colour disc.

### Session Expiry

Supabase JWTs expire after 1 hour by default. The Flutter SDK auto-refreshes silently. No action required from the user or the app. Game actions hitting the server always carry a fresh JWT.

---

## Room Lifecycle

```
created (lobby) → active → paused ⇄ active → finished → archived
```

### Creating a Room

Host creates a room from the main dashboard:

```
POST /api/rooms
Authorization: Bearer {jwt}
{
  "display_name": "Friday Night Game",
  "max_players": 6,
  "play_mode": "realtime",
  "config": { ...room_configs fields... }
}
```

Server:

1. Generates unique `room_code` (6-char `[A-Z0-9]`, collision-checked against `game_rooms`)
2. Inserts `game_rooms` row with `status = 'lobby'`
3. Inserts `room_configs` row with provided config (defaults for any omitted keys)
4. Inserts `room_players` row for host (`seat_order = 0`)
5. Returns `room_code` to client

Client navigates to lobby screen.

### Joining a Room

Via room code (typed or pasted) or rejoin link:

```
POST /api/rooms/{room_code}/join
Authorization: Bearer {jwt}
```

Server:

1. Looks up room by `room_code`
2. Validates `status = 'lobby'` (cannot join mid-game; see Rejoin for active/paused rooms)
3. Validates `player_count < max_players`
4. Validates player not already in room
5. Inserts `room_players` row, increments `player_count`
6. Returns full room state

Client navigates to lobby screen and subscribes to `room_players` Realtime channel.

### Lobby Screen

All players see each other's display names and ready status in real time. Host sees a "Start Game" button (enabled when ≥ 2 players are ready). Host can configure room settings and assign seat order if `turn_order_method: 'host_assigned'`.

### Starting the Game

```
POST /api/rooms/{room_id}/start
Authorization: Bearer {jwt}  -- must be host
```

Server:

1. Validates `player_count >= 2`
2. Assigns `seat_order` per `turn_order_method` config
3. Assigns token colours (first-come or host-assigned)
4. Initialises `game_state`: all balances at `starting_money`, all positions at 0, shuffled card decks
5. Initialises `room_configs` record
6. Sets `game_rooms.status = 'active'`, `started_at = now()`
7. Sets `current_player_id` to first seat, `phase = 'roll'`
8. Broadcasts via Supabase Realtime

All clients navigate from lobby to game screen.

---

## Pause and Resume

### Pausing

Any player may pause (not host-only -- any player can trigger it):

```
POST /api/rooms/{room_id}/pause
Authorization: Bearer {jwt}
```

Server sets `status = 'paused'`, `paused_at = now()`. Supabase broadcasts. All clients display pause screen. No turn timer runs while paused.

Turn state is fully preserved -- the game resumes exactly where it left off, mid-phase if necessary.

### Resuming

Any player in the room may resume:

```
POST /api/rooms/{room_id}/resume
Authorization: Bearer {jwt}
```

Server sets `status = 'active'`, clears `paused_at`. Broadcasts. All connected clients return to game screen. Players who are not connected see the resume via push notification (async mode) or on next app open (realtime mode).

Paused games have no expiry. A game paused for months is still valid.

---

## Rejoin

### Scenario: Player Disconnects Mid-Game

`is_connected` is set to `false` via the disconnect endpoint (or missed heartbeat). The game continues without them -- it's their turn when it comes, auto-action fires if turn timer expires.

On reconnect:

1. Client calls `POST /api/rooms/{room_id}/connect`
2. Server sets `is_connected = true` on `room_players`
3. Client re-subscribes to all Realtime channels
4. Full current `game_state` emitted immediately by Supabase stream
5. Client renders current board state -- no catch-up replay needed

### Scenario: Player Returns to App (No Active Session)

Anonymous player on same device:

1. App reads `device_token` from secure storage
2. Supabase anonymous session resumed (still valid) or re-created
3. `GET /api/my-games` returns active/paused rooms matching `device_token`
4. Player taps game → rejoin flow

Named account player on any device:

1. Player signs in
2. `GET /api/my-games` returns active/paused rooms for `auth.uid()`
3. Player taps game → rejoin flow

### Scenario: Player Joins via Rejoin Link

Deep link `spoomn://join/K7X2MQ` or web URL `https://spoomn.app/join/K7X2MQ`:

```
POST /api/rooms/{room_code}/rejoin
Authorization: Bearer {jwt}
{ "device_token": "..." }  -- included for anonymous players
```

Server:

1. Looks up room by code
2. Checks `room_players` for existing row matching `player_id` (named) or `device_token` via `profiles` (anonymous)
3. If found and `left_at` is null: allow rejoin, set `is_connected = true`
4. If found and `left_at` is set: player explicitly left -- do not rejoin (return error)
5. If not found: player was never in this room -- return error (cannot join mid-game via rejoin link)

### Explicit Leave

Player may explicitly leave a room via the leave button. Sets `room_players.left_at = now()`. Left players cannot rejoin. Their assets are handled per the room's bankruptcy config (if they had assets, treated as voluntary bankruptcy -- assets go to bank regardless of `bankruptcy_assets_to` config, since there is no creditor).

---

## In-Progress Dashboard

Main dashboard shows a player's active and paused games. Displayed on app open after auth.

```
GET /api/my-games
Authorization: Bearer {jwt}
```

Server query:

```sql
select
  gr.id,
  gr.room_code,
  gr.status,
  gr.play_mode,
  gr.current_player_id,
  gr.turn_started_at,
  rp.is_bankrupt,
  (select count(*) from room_players where room_id = gr.id and left_at is null) as player_count,
  gs.balances->auth.uid()::text as my_balance
from game_rooms gr
join room_players rp on rp.room_id = gr.id and rp.player_id = auth.uid()
join game_state gs on gs.room_id = gr.id
where gr.status in ('lobby', 'active', 'paused')
  and rp.left_at is null
  and rp.is_bankrupt = false
order by gr.updated_at desc;
```

Anonymous players: server additionally queries by `device_token` from profile, returning the same shape.

Dashboard cards show:
- Room code
- Status badge (Lobby / Active / Paused)
- Player count
- My balance
- Whose turn it is
- In async mode: time remaining on current turn if `async_turn_timeout_hours` set

---

## Token Colour Assignment

8 available token colours: red, blue, green, yellow, purple, orange, pink, black.

Assignment order in lobby: first-joined gets first pick if `turn_order_method: 'host_assigned'`. Otherwise, colours are assigned in join order when game starts. Host can reassign colours before start.

Stored on `room_players.token_colour`. Cannot change after game starts.

---

## Display Names

Players set a display name on first launch (auto-generated guest name pre-filled, editable). Name is scoped to the profile -- same name appears in all games.

Named account players can update display name in profile settings at any time. Change propagates to all active games via `profiles` table update (Realtime-subscribed clients re-read player names on next `room_players` update).

Anonymous players can change display name before and during game (lobby only -- locked once game starts).

---

## Room Codes

6-character alphanumeric `[A-Z0-9]`. Generated server-side:

```dart
String generateRoomCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // omit O,0,I,1 -- ambiguous
  final rand = Random.secure();
  return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
}
```

Collision-checked against `game_rooms.room_code` on insert. Retry up to 5 times if collision (statistically negligible beyond 1 retry until millions of concurrent rooms exist).

Finished rooms retain their code but are excluded from join/rejoin lookups. Codes are not reused.
