# Data Model

All game state lives in Supabase (Postgres). Server holds no in-memory state -- every action reads from and writes to these tables. This enables pause/resume, crash recovery, and rejoin at no extra cost.

---

## Tables

### `users`

Managed by Supabase Auth. Extended with a public profile row.

```sql
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null,
  is_anonymous  boolean not null default true,
  device_token  text,           -- set for anonymous users, used for same-device rejoin
  push_token    text,           -- FCM/APNs/Web Push token for async turn notifications
  push_platform text,           -- 'ios' | 'android' | 'web' | null
  created_at    timestamptz not null default now()
);
```

- `id` mirrors `auth.users.id` -- Supabase Auth creates the `auth.users` row; we create the `profiles` row via trigger
- `is_anonymous` flips to `false` when user upgrades to named account
- `device_token` is a UUID generated client-side on first launch, stored in device secure storage, sent on anonymous session creation -- allows same-device rejoin even if the Supabase session expires
- `avatar_url` / `pawn_photo_url` point at objects in the public `avatars` Storage bucket, uploaded from the profile screen; `pawn_photo_url` renders on the board in place of the flat colour token when set

---

### `player_stats`, `property_stats`, `trade_stats`

Permanent per-profile stats, server-written only. Rolled up once per game, right after `game_rooms.status` becomes `'finished'` -- see `recordGameStats` in the server's `stats_handler.dart`.

```sql
create table public.player_stats (
  profile_id            uuid primary key references public.profiles(id) on delete cascade,
  games_played          int not null default 0,
  wins                  int not null default 0,
  losses                int not null default 0,
  bankruptcies          int not null default 0,
  avg_placement         numeric not null default 0,
  peak_net_worth        int not null default 0,
  properties_bought     int not null default 0,
  monopolies_completed  int not null default 0,
  jail_visits           int not null default 0,
  tax_paid_total        int not null default 0,
  fastest_win_turns     int,
  updated_at            timestamptz not null default now()
);

-- Per (profile, board square) ownership counts -- drives "favourite property"
create table public.property_stats (
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  square_index int not null,
  times_owned  int not null default 0,
  primary key (profile_id, square_index)
);

-- Per (profile, partner) completed trade counts -- drives "favourite trading partner"
create table public.trade_stats (
  profile_id       uuid not null references public.profiles(id) on delete cascade,
  partner_id       uuid not null references public.profiles(id) on delete cascade,
  trades_completed int not null default 0,
  primary key (profile_id, partner_id)
);
```

`peak_net_worth` and `property_stats.times_owned` are computed from the game's *final* state, not tracked incrementally through the game -- cheap, and close enough for a stat rather than a ledger. `avg_placement` is a running average updated in place (`new = old + (placement - old) / games_played`), never recomputed from history.

---

### `game_rooms`

One row per game session.

```sql
create table public.game_rooms (
  id              uuid primary key default gen_random_uuid(),
  room_code       text not null unique,          -- short alphanumeric, e.g. 'K7X2MQ'
  status          text not null default 'lobby', -- lobby | active | paused | finished
  host_id         uuid not null references public.profiles(id),
  current_player_id uuid references public.profiles(id),
  play_mode       text not null default 'realtime', -- realtime | async
  turn_started_at timestamptz,                      -- when current turn began; used for async expiry
  player_count    int not null default 0,
  max_players     int not null default 8,
  created_at      timestamptz not null default now(),
  started_at      timestamptz,
  paused_at       timestamptz,
  finished_at     timestamptz,

  constraint room_code_format check (room_code ~ '^[A-Z0-9]{6}$'),
  constraint player_count_range check (player_count between 0 and 8),
  constraint max_players_range check (max_players between 2 and 8)
);
```

**Status lifecycle:**

```
lobby → active → paused → active → ... → finished
```

- `lobby`: waiting for players, game not started
- `active`: game in progress, turns running
- `paused`: all players disconnected or host paused; resumable indefinitely
- `finished`: game over (one winner or all others bankrupt)

`room_code` is the human-readable join code. Generated server-side on room creation using a collision-checked random 6-character string from `[A-Z0-9]`.

---

### `room_players`

Join table linking players to rooms. One row per player per game.

```sql
create table public.room_players (
  id           uuid primary key default gen_random_uuid(),
  room_id      uuid not null references public.game_rooms(id) on delete cascade,
  player_id    uuid not null references public.profiles(id),
  seat_order   int not null,                -- turn order: 0-indexed
  token_colour text not null,               -- e.g. 'red', 'blue', 'green'
  is_bankrupt  boolean not null default false,
  is_connected boolean not null default false,
  joined_at    timestamptz not null default now(),
  left_at      timestamptz,                 -- null = still in game

  unique (room_id, player_id),
  unique (room_id, seat_order),
  unique (room_id, token_colour)
);
```

`seat_order` determines turn sequence. Assigned when game starts, never changes mid-game.

---

### `game_state`

Single row per room. The complete, authoritative board state at any moment. Server reads this before every action and writes it after. Supabase Realtime broadcasts every write to all subscribed clients.

```sql
create table public.game_state (
  room_id           uuid primary key references public.game_rooms(id) on delete cascade,
  turn_number       int not null default 0,
  phase             text not null default 'roll',  -- roll | move | action | trade | end_turn
  dice_roll         int[2],                        -- [die1, die2], null before roll
  consecutive_doubles int not null default 0,      -- tracks doubles streak for jail
  board_positions   jsonb not null default '{}',   -- { player_id: position_index }
  property_ownership jsonb not null default '{}',  -- { square_index: player_id | 'bank' }
  houses            jsonb not null default '{}',   -- { square_index: house_count }
  hotels            jsonb not null default '{}',   -- { square_index: true }
  mortgaged         jsonb not null default '[]',   -- [square_index, ...]
  balances          jsonb not null default '{}',   -- { player_id: amount }
  jail_status       jsonb not null default '{}',   -- { player_id: { in_jail: bool, turns_in_jail: int, has_card: bool } }
  get_out_of_jail_cards jsonb not null default '{}', -- { player_id: count }
  community_chest_index int not null default 0,    -- position in shuffled deck
  chance_index      int not null default 0,        -- position in shuffled deck
  free_parking_pot  int not null default 0,        -- optional house rule (configurable)
  updated_at        timestamptz not null default now()
);
```

**Why JSONB for board state?**

Board state has variable-length maps keyed by player ID or square index. JSONB avoids a schema change when player count varies. The server validates all JSONB content -- clients never write to this table directly.

**Trade-off**: JSONB is less queryable than normalised columns. Acceptable here -- we never query individual property ownership or balances across games. We only ever read one room's full state.

---

### `pending_trades`

Trades are multi-step (propose → counter → accept/reject). A separate table tracks in-flight trade offers.

```sql
create table public.pending_trades (
  id              uuid primary key default gen_random_uuid(),
  room_id         uuid not null references public.game_rooms(id) on delete cascade,
  proposer_id     uuid not null references public.profiles(id),
  recipient_id    uuid not null references public.profiles(id),
  offer           jsonb not null, -- { properties: [sq_idx], money: int, jail_cards: int }
  request         jsonb not null, -- { properties: [sq_idx], money: int, jail_cards: int }
  status          text not null default 'pending', -- pending | countered | accepted | rejected | cancelled
  created_at      timestamptz not null default now(),
  resolved_at     timestamptz
);
```

Only one `pending` trade allowed per pair of players at a time (enforced by server).

---

### `game_log`

Append-only audit trail of every action taken in a game. Used for the in-game event feed ("Alice bought Mayfair", "Bob rolled a double").

```sql
create table public.game_log (
  id          bigint primary key generated always as identity,
  room_id     uuid not null references public.game_rooms(id) on delete cascade,
  player_id   uuid references public.profiles(id), -- null for system events
  turn_number int not null,
  action      text not null,   -- e.g. 'roll_dice', 'buy_property', 'draw_chance'
  payload     jsonb not null,  -- action-specific details
  created_at  timestamptz not null default now()
);

create index game_log_room_id_idx on public.game_log (room_id, created_at desc);
```

Write-only from the server. Clients subscribe to new rows for their room to display the event feed.

---

### `room_configs`

Optional per-room rule variants configured in the lobby before the game starts.

```sql
create table public.room_configs (
  room_id              uuid primary key references public.game_rooms(id) on delete cascade,
  free_parking_jackpot boolean not null default false, -- house rule: fines go to Free Parking
  auction_on_reject    boolean not null default true,  -- standard rule: property goes to auction if declined
  starting_money       int not null default 1500,
  go_salary            int not null default 200,
  max_turn_time_secs   int,                            -- null = no time limit per turn
  created_at           timestamptz not null default now()
);
```

---

## Indexes

```sql
-- Room lookup by code (join flow)
create unique index game_rooms_room_code_idx on public.game_rooms (room_code);

-- Player's active games (dashboard: "in progress" list)
create index room_players_player_id_idx on public.room_players (player_id)
  where left_at is null;

-- Game log feed per room
create index game_log_room_id_idx on public.game_log (room_id, created_at desc);
```

---

## Realtime Subscriptions

| Table | Event | Who subscribes | Why |
|-------|-------|----------------|-----|
| `game_state` | `UPDATE` | All players in room | Board state changed -- re-render |
| `game_rooms` | `UPDATE` | All players in room | Status changed (pause, finish, player join) |
| `room_players` | `INSERT`, `UPDATE` | All players in room | Player joined, connected, or went bankrupt |
| `pending_trades` | `INSERT`, `UPDATE` | Trade participants | Trade proposed or updated |
| `game_log` | `INSERT` | All players in room | New event for the feed |

All subscriptions filtered by `room_id = {active_room_id}`.

---

## Row-Level Security

RLS is enabled on all tables. The Dart Shelf server connects using the **service role key** (bypasses RLS) for all game state writes. Clients connect with their **anon/user JWT** (subject to RLS).

```sql
-- game_rooms: players can read rooms they're in
create policy "player can read own rooms"
  on public.game_rooms for select
  using (
    id in (
      select room_id from public.room_players
      where player_id = auth.uid()
    )
  );

-- game_state: same rule
create policy "player can read own game state"
  on public.game_state for select
  using (
    room_id in (
      select room_id from public.room_players
      where player_id = auth.uid()
    )
  );

-- No client INSERT or UPDATE on game_state -- server only
```

---

## Anonymous Rejoin Flow

```
1. User launches app on same device
2. App reads device_token from secure storage
3. App creates Supabase anon session (or resumes existing)
4. App GETs /api/my-games with device_token in header
5. Server queries: SELECT * FROM room_players rp
                    JOIN profiles p ON p.id = rp.player_id
                    WHERE p.device_token = $1
                    AND rp.left_at IS NULL
6. Returns list of active/paused games
7. Player taps game → rejoins
```

Named account users skip step 2-4 -- query uses `auth.uid()` directly.

---

## Entity Relationship Summary

```
profiles (1) ──────────── (many) room_players (many) ──── (1) game_rooms
                                                                    │
                                                              game_state (1:1)
                                                              room_configs (1:1)
                                                              game_log (1:many)
                                                              pending_trades (1:many)
```
