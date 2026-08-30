# Server Game Logic

All game logic runs on the Dart Shelf server. Clients send action intents; the server validates, computes outcomes, writes state, and Supabase broadcasts to all clients. No outcome is ever computed client-side.

---

## Request Structure

All game actions arrive as HTTP POST:

```
POST /api/rooms/{room_id}/actions
Authorization: Bearer {supabase_jwt}
Content-Type: application/json

{
  "action": "roll_dice",
  "payload": {}
}
```

Server extracts `player_id` from the JWT. Every handler begins with the validation pipeline before touching game state.

---

## Validation Pipeline

Every action passes through this chain in order. Failure at any step returns an error response; game state is not modified.

```
1. Auth          Is the JWT valid? Does the player belong to this room?
2. Room state    Is the room status 'active'?
3. Phase         Is this action permitted in the current phase?
4. Turn          Is it this player's turn (for turn-scoped actions)?
5. Ownership     Does the player own the assets referenced in the payload?
6. Balance       Does the player have sufficient funds?
7. Rule          Does the action comply with room_configs rules?
8. Apply         Mutate game state, write to Supabase
```

Steps 1--7 are read-only. Step 8 is the only write. This makes handlers safe to retry if step 8 fails -- the database write is idempotent per action (each action includes an `action_id` UUID; duplicate `action_id` within a room is rejected at step 2).

---

## Turn State Machine

```
                    ┌─────────────────────────────────────────┐
                    │              ACTIVE GAME                 │
                    │                                          │
              ┌─────▼─────┐                                   │
      ┌──────▶│   ROLL    │◀──────────────────────────────┐  │
      │       └─────┬─────┘                               │  │
      │             │ roll_dice                           │  │
      │       ┌─────▼─────┐                               │  │
      │       │   MOVE    │  (server auto-applies)        │  │
      │       └─────┬─────┘                               │  │
      │             │ square resolved                     │  │
      │       ┌─────▼──────┐                              │  │
      │       │   ACTION   │                              │  │
      │       └─────┬──────┘                              │  │
      │             │ action resolved                     │  │
      │       ┌─────▼─────┐                               │  │
      │       │   TRADE   │◀──── any player may propose   │  │
      │       └─────┬─────┘      trades here              │  │
      │             │ end_turn                            │  │
      │       ┌─────▼──────┐                              │  │
      └───────│  END_TURN  │──────────────────────────────┘  │
              └────────────┘  next player's ROLL begins       │
                                                              │
              ┌─────────────┐                                 │
              │  BANKRUPTCY │── negotiation window ──▶ resolve│
              └─────────────┘                                 │
              ┌─────────────┐                                 │
              │  FINISHED   │─────────────────────────────────┘
              └─────────────┘
```

Phase stored in `game_state.phase`. Server enforces phase transitions -- clients cannot skip or reorder phases.

---

## Action Handlers

### `roll_dice`

**Phase**: `roll`  
**Who**: active player only

```
1. Generate dice values: List<int> = List.generate(dice_count, (_) => random(1, dice_sides))
2. Store on game_state.dice_roll
3. Check for doubles (all dice equal)
4. If doubles: increment consecutive_doubles
5. If consecutive_doubles >= jail_on_consecutive_doubles config: send to jail, end turn
6. Transition phase to 'move'
7. Apply movement (see move handler -- auto-chained, no client action needed)
```

### Move (auto-applied after roll)

**Phase**: `move` (server-internal, not a client action)

```
1. new_pos = (current_pos + dice_total) % board_size
2. If new_pos < current_pos: player passed Go → credit go_salary (+ go_landing_bonus if exact)
3. Update game_state.board_positions[player_id]
4. If jailbreak active: check all police pawns -- does player share square with any pawn?
   - If yes: caught (see jailbreak catch handler)
5. Move active police pawn (if player has one):
   a. Roll police dice
   b. Move pawn
   c. Check all jailbreaking players against pawn's new position
   d. Catch any player on same square
6. Resolve landing square (see square handlers below)
7. Transition to 'action' phase
```

### Square Handlers

Chained automatically from move. Each square type produces a different action phase state.

#### Unowned Property / Station / Utility

```
game_state.phase = 'action'
game_state.pending_action = { type: 'purchase_decision', square: idx }
```

Active player must submit `buy_property` or `decline_property`. Turn timer starts.

#### Owned Property (another player, unmortgaged)

```
rent = calculate_rent(square, game_state, room_configs)
if auto_claim_rent:
  debit(active_player, rent)
  credit(owner, rent)
  check_bankruptcy(active_player)
  phase = 'trade'
else:
  game_state.pending_action = { type: 'rent_claim', square: idx, amount: rent, owner: player_id }
  // owner must submit claim_rent before turn can proceed
```

Rent calculation:

```dart
int calculateRent(int squareIndex, GameState state, RoomConfig config) {
  final ownership = state.propertyOwnership[squareIndex];
  if (ownership == null || state.mortgaged.contains(squareIndex)) return 0;

  final square = Board.squares[squareIndex];
  final landingPlayerId = state.currentPlayerId;

  // Check rent immunity
  final immunity = state.rentModifiers[landingPlayerId]?.protections
    .where((p) => p.coversSquare(squareIndex))
    .firstOrNull;
  if (immunity != null) {
    immunity.consume(); // decrement remaining
    return 0;
  }

  // Check rent discount
  final discount = state.rentModifiers[landingPlayerId]?.discounts
    .where((d) => d.coversSquare(squareIndex))
    .firstOrNull;

  int baseRent = switch (square.type) {
    SquareType.utility  => calculateUtilityRent(squareIndex, state),
    SquareType.station  => calculateStationRent(squareIndex, state),
    SquareType.property => calculatePropertyRent(squareIndex, state),
    _                   => 0,
  };

  return discount?.apply(baseRent) ?? baseRent;
}
```

#### Owned Property (active player, or mortgaged)

No action. Phase transitions to `trade`.

#### Community Chest / Chance

```
1. Draw top card from deck (deck index stored in game_state)
2. Apply card effect immediately (server-side)
3. If keep card (GOOJF, rent protection, etc.): add to player's held cards
4. Log card draw and effect
5. Phase transitions based on effect outcome
   - go_to_jail effect → jail entry, end turn
   - move_to / move_relative → re-resolve landing square
   - all others → trade phase
```

#### Tax Squares

```
amount = calculate_tax(square, game_state, room_configs)
debit(active_player, amount)
if free_parking_jackpot: add to pot
else: to bank
check_bankruptcy(active_player)
phase = 'trade'
```

#### Free Parking

```
if free_parking_jackpot and pot > 0:
  credit(active_player, pot)
  game_state.free_parking_pot = 0
phase = 'trade'
```

#### Go To Jail

```
game_state.board_positions[player_id] = jail_square (10)
game_state.jail_status[player_id].in_jail = true
game_state.jail_status[player_id].turns_in_jail = 0
game_state.consecutive_doubles = 0
remove player's police pawn if active
phase = 'roll' (next player -- jail entry ends turn immediately)
```

#### Go

```
credit(active_player, go_salary + go_landing_bonus)
phase = 'trade'
```

#### Jail / Just Visiting

```
phase = 'trade'  // no effect
```

---

### `buy_property`

**Phase**: `action`, pending `purchase_decision`  
**Who**: active player

```
1. Validate player has sufficient funds
2. Debit purchase price from player
3. Set property_ownership[square] = player_id
4. Log purchase
5. Phase = 'trade'
```

### `decline_property`

**Phase**: `action`, pending `purchase_decision`  
**Who**: active player

```
if auction_on_decline:
  start_auction(square, room_configs)
  phase = 'auction'
else:
  property remains bank-owned
  phase = 'trade'
```

### Auction Flow

Auction state stored in `game_state.active_auction`. Auction actions (`bid`, `pass_bid`, `claim`) are valid for all non-bankrupt players during `auction` phase.

```
active_auction: {
  square_index: int,
  style: 'ascending' | 'blind' | 'dutch',
  current_price: int,
  current_leader: player_id | null,
  bids: { player_id: amount },
  passed: [player_id],
  ends_at: timestamp | null
}
```

On auction completion: highest bidder debited, property transferred. If no bids: property stays with bank. Phase returns to `trade`.

---

### `end_turn`

**Phase**: `trade`  
**Who**: active player

```
1. Validate no outstanding pending_action
2. Validate no pending trades involving active player (all resolved)
3. Process repayment instalments due this turn (auto-debit)
4. Check repayment default → bankruptcy if insufficient
5. Advance current_player_id to next non-bankrupt player in seat_order
6. If cycled back to seat 0: increment turn_number
7. Check turn_limit or time_limit winning condition
8. Reset dice_roll, consecutive_doubles (if no doubles this turn)
9. Phase = 'roll'
```

If `doubles_extra_turn` is true and player rolled doubles this turn (and was not jailed): player takes another turn instead of advancing.

---

### `jailbreak`

**Phase**: `roll`  
**Who**: active player, must be in jail, not in mandatory_turns

```
1. Validate jail_status[player_id].in_jail = true
2. Validate mandatory_turns_remaining = 0
3. Validate jailbreak_enabled config
4. Set jail_status[player_id].in_jail = false
5. Set jail_status[player_id].is_jailbreaking = true
6. Spawn police pawn at square 10:
   active_police_pawns.add({ owner_id: player_id, position: 10, turns_remaining: police_duration })
7. Proceed with normal roll_dice flow
```

### Jailbreak Catch Handler

```
1. Set jail_status[player_id].in_jail = true
2. Set jail_status[player_id].is_jailbreaking = false
3. jail_status[player_id].mandatory_turns_remaining = jailbreak_mandatory_turns
4. jail_status[player_id].catch_count += 1
5. jail_status[player_id].effective_fine *= jailbreak_fine_multiplier
6. Remove catching police pawn from active_police_pawns
7. board_positions[player_id] = 10
8. End turn
```

---

### `propose_trade` / `accept_trade` / `counter_trade` / `reject_trade` / `cancel_trade`

See [Trading][trading] for full flow. Server validates:

- All assets exist and are owned by the offering party at time of acceptance
- No asset appears in more than one pending trade simultaneously
- `multi_party_trades` config permits participant count
- Trade is balanced (every offered item has a receiver)

On acceptance: all asset transfers applied atomically in a single `game_state` write.

---

### `place_trap`

**Phase**: `trade` (or any turn if `trade_any_turn`)  
**Who**: any player holding a trap card

```
1. Validate player holds source trap card
2. If placement = 'player_choice': validate chosen square is legal
3. If placement = 'random': server selects random eligible square
4. Remove card from player's held_cards
5. Insert into active_traps table (not game_state JSONB -- see below)
6. Log placement (square revealed in log for visible traps; 'a trap was placed' for invisible)
```

### Trap Trigger Handler (auto -- on landing)

```
1. Query active_traps where square_index = landing_square
2. For each trap (ordered by placed_turn ascending):
   a. Apply trigger_effect to landing player
   b. If beneficiary = 'placer': credit owner
   c. If beneficiary = 'bank': to bank / free parking pot
   d. Decrement triggers_remaining
   e. If triggers_remaining = 0: remove trap
3. Check bankruptcy after all traps on square resolved
```

---

## Active Traps: Separate Table (Data Model Correction)

Invisible traps require per-player state visibility. Storing traps in `game_state` JSONB and constructing per-player views before broadcast is fragile and couples the server to Supabase's broadcast mechanism.

**Correction to `03-data-model.md`**: `active_traps` is a standalone table, not JSONB on `game_state`.

```sql
create table public.active_traps (
  id               uuid primary key default gen_random_uuid(),
  room_id          uuid not null references public.game_rooms(id) on delete cascade,
  owner_id         uuid not null references public.profiles(id),
  square_index     int not null,
  visible          boolean not null default true,
  source_card_id   text not null,
  triggers_remaining int,   -- null = unlimited
  placed_turn      int not null,
  trigger_effect   jsonb not null,
  created_at       timestamptz not null default now()
);
```

RLS handles visibility automatically:

```sql
-- Players can see: all visible traps in their room + their own invisible traps
create policy "trap visibility"
  on public.active_traps for select
  using (
    room_id in (select room_id from public.room_players where player_id = auth.uid())
    and (visible = true or owner_id = auth.uid())
  );
```

Clients subscribe to `active_traps` filtered by `room_id`. RLS transparently redacts invisible traps owned by other players. No per-player view construction on the server required.

---

## Bankruptcy Handler

```
check_bankruptcy(player_id, debt, creditor_id):
  if balance[player_id] >= debt: return  // solvent

  if allow_bankruptcy_negotiation and creditor_id != 'bank':
    phase = 'bankruptcy_negotiation'
    pending_action = { type: 'negotiate', debtor: player_id, creditor: creditor_id, amount: debt }
    start negotiation timer
    return

  // No negotiation -- immediate bankruptcy
  liquidate(player_id)
  if balance[player_id] >= debt:
    debit(player_id, debt)
    credit(creditor_id, debt)
    return

  // Still insolvent after liquidation -- bankrupt
  declare_bankruptcy(player_id, creditor_id)

liquidate(player_id):
  sell all buildings at sell_building_rate
  mortgage all unmortgaged properties at mortgage_rate

declare_bankruptcy(player_id, creditor_id):
  if bankruptcy_assets_to = 'creditor' and creditor_id != 'bank':
    transfer all assets to creditor_id
    transfer all active_traps owned by player to creditor_id
  else:
    return all properties to bank
    remove all buildings
    remove all active_traps owned by player

  room_players.is_bankrupt[player_id] = true
  remove from turn order
  check_win_condition()
```

---

## Repayment Processing

At step 3 of `end_turn`, server processes all repayment instalments due:

```
for each repayment_plan where debtor_id = current_player_id:
  if balance[debtor] >= instalment_amount:
    debit(debtor, instalment_amount)
    credit(creditor, instalment_amount)
    plan.instalments_remaining -= 1
    if instalments_remaining = 0: remove plan
  else:
    liquidate(debtor)
    if balance[debtor] >= instalment_amount:
      debit, credit, decrement as above
    else:
      declare_bankruptcy(debtor, creditor)
      break  // no further instalments processed
```

---

## Win Condition Checks

Called after every state-mutating action.

```dart
void checkWinCondition(GameState state, RoomConfig config) {
  final activePlayers = state.players.where((p) => !p.isBankrupt).toList();

  switch (config.winningCondition) {
    case 'last_player_standing':
      if (activePlayers.length == 1) endGame(activePlayers.first);

    case 'net_worth_target':
      if (config.netWorthCheck == 'real_time') {
        final winner = activePlayers
          .where((p) => calculateNetWorth(p, state) >= config.netWorthTarget)
          .firstOrNull;
        if (winner != null) endGame(winner);
      }
      // end_of_turn check happens in end_turn handler

    case 'turn_limit':
      if (state.turnNumber >= config.turnLimit) endGame(highestNetWorth(activePlayers, state));

    case 'time_limit':
      // checked by server on each end_turn against room.started_at
  }
}
```

---

## Async Play

When `play_mode: 'async'`, players do not need to be online simultaneously. The game progresses one turn at a time at whatever pace each player responds.

### How It Differs from Real-Time

| Behaviour | Real-time | Async |
|-----------|-----------|-------|
| Players online together | Required | Not required |
| Turn notification | Supabase Realtime (in-app) | Push notification + Realtime if online |
| Turn timeout unit | Seconds (`max_turn_time_secs`) | Hours (`async_turn_timeout_hours`) |
| Auto-action on timeout | Immediate server action | After N hours, server applies default action |
| Room status between turns | `active` | `active` (no pause needed between turns) |
| Trades across turns | Resolved before `end_turn` | Same -- trade must resolve before turn ends |

### Turn Notification Flow

On each `end_turn`, the server:

1. Advances `current_player_id` as normal
2. Sets `game_rooms.turn_started_at = now()`
3. Looks up `profiles.push_token` for the new active player
4. If token exists: fires a push notification via the notification service
5. If player is currently connected (Supabase Realtime): notification suppressed (they see the state update directly)

Push notification payload:

```json
{
  "title": "Your turn in Spoomn",
  "body": "It's your turn -- tap to play",
  "data": {
    "room_id": "uuid",
    "room_code": "K7X2MQ",
    "deep_link": "spoomn://join/K7X2MQ"
  }
}
```

### Notification Service

Push notifications dispatched from a Supabase Edge Function triggered by a Postgres webhook on `game_rooms.current_player_id` change. The Edge Function:

1. Reads new `current_player_id`
2. Fetches `push_token` and `push_platform` from `profiles`
3. Dispatches via platform-appropriate service:
   - iOS: APNs (via Firebase Cloud Messaging unified API)
   - Android: FCM
   - Web: Web Push (VAPID)

The Dart Shelf server does not send push notifications directly -- this is handled by the Edge Function to avoid coupling the game server to notification infrastructure.

### Async Turn Expiry

When `async_turn_timeout_hours` is set, a `pg_cron` job runs every 15 minutes and checks:

```sql
select id from game_rooms
where play_mode = 'async'
  and status = 'active'
  and turn_started_at < now() - (room_config.async_turn_timeout_hours * interval '1 hour');
```

For each expired turn, the server applies the default auto-action for the current phase (same logic as `max_turn_time_secs` real-time timeout -- see Turn Timer in game rules). A reminder notification is sent at `async_turn_reminder_hours` before expiry if configured.

### Push Token Registration

Clients register their push token on login or when notification permission is granted:

```
POST /api/profile/push-token
Authorization: Bearer {jwt}
{ "token": "fcm-or-apns-token", "platform": "ios" }
```

Server upserts `profiles.push_token` and `profiles.push_platform`. Token refreshed automatically by the client SDK when it rotates.

Anonymous players can register push tokens -- token is associated with their anonymous profile. Token persists if they upgrade to a named account (anonymous session is linked).

---

## Error Responses

All validation failures return structured errors:

```json
{
  "error": {
    "code": "INVALID_PHASE",
    "message": "Action 'buy_property' not permitted in phase 'roll'",
    "phase": "roll",
    "action": "buy_property"
  }
}
```

| Code | Meaning |
|------|---------|
| `UNAUTHORIZED` | JWT invalid or player not in room |
| `ROOM_NOT_ACTIVE` | Room is paused, finished, or in lobby |
| `INVALID_PHASE` | Action not permitted in current phase |
| `NOT_YOUR_TURN` | Turn-scoped action submitted by non-active player |
| `INSUFFICIENT_FUNDS` | Balance too low for action |
| `NOT_OWNER` | Player does not own referenced asset |
| `RULE_VIOLATION` | Action violates a room_config rule |
| `DUPLICATE_ACTION` | action_id already processed |
| `ASSET_COMMITTED` | Asset already in a pending trade |

---

[trading]: ../game-rules/04-trading.md
