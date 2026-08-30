# Turn Flow

## Turn Phases

Each turn moves through these phases in order. The server enforces phase sequence -- clients can only submit actions valid for the current phase.

```
roll → move → action → [trade] → end_turn
```

| Phase | Description |
|-------|-------------|
| `roll` | Active player must roll dice |
| `move` | Server moves token, determines landing square |
| `action` | Player responds to landing square (buy, pay rent, draw card, etc.) |
| `trade` | Optional: player may initiate or respond to trades |
| `end_turn` | Player ends turn; next player's `roll` phase begins |

`trade` phase can be entered from `action` or `end_turn`. Trades from other players can arrive at any point -- the active player must resolve them before ending their turn.

---

## Dice

### Default Roll

Two standard 6-sided dice. Server generates both values using a cryptographically random source. Clients never roll -- they receive the result.

```
dice_roll: [die1, die2]   -- stored on game_state
total: die1 + die2        -- movement amount
```

### Doubles

Both dice show the same value.

**Default doubles behaviour:**

1. Player rolls doubles → takes full turn (move, action)
2. After completing the turn, player rolls again immediately (extra turn)
3. If doubles rolled a second consecutive time → another extra turn
4. If doubles rolled a third consecutive time → player goes directly to jail, turn ends

Doubles streak tracked in `game_state.consecutive_doubles`. Resets to 0 on any non-double roll or on jail.

### Configurable Dice Options

| Config key | Default | Options |
|------------|---------|---------|
| `dice_count` | 2 | 1--4 |
| `dice_sides` | 6 | 4, 6, 8, 10, 12, 20 |
| `doubles_enabled` | true | true / false |
| `doubles_extra_turn` | true | true / false -- ignored if `doubles_enabled` is false |
| `jail_on_consecutive_doubles` | 3 | 1--5, or `null` to disable |

Setting `doubles_enabled: false` removes all doubles mechanics -- a matching roll is treated as a normal roll. Setting `jail_on_consecutive_doubles: null` allows infinite consecutive doubles without jail (chaotic, use with care).

---

## Movement

Player moves clockwise by the dice total. Server calculates new position:

```
new_position = (current_position + dice_total) % board_size
```

### Passing Go

If `new_position < current_position` after adding dice total (i.e. the player wrapped around the board), the player collects the Go salary.

| Config key | Default | Notes |
|------------|---------|-------|
| `go_salary` | 200 | Collected each time player passes or lands on Go |
| `go_landing_bonus` | 0 | Extra amount collected for landing *exactly* on Go (added on top of `go_salary`) |

---

## Landing: Square Effects

### Go (square 00)

Collect `go_salary`. If landed exactly, also collect `go_landing_bonus` (default: 0).

### Property (unowned)

Player may buy at face value, or decline. If declined, property goes to auction (see [Properties][properties]).

### Property (owned, unmortgaged)

Player pays rent to owner. Owner must claim rent before dice are passed (server auto-claims if `auto_claim_rent` config is true). If owner fails to claim before next roll, rent is forfeit for that landing.

| Config key | Default |
|------------|---------|
| `auto_claim_rent` | true |

### Property (owned, mortgaged)

No rent owed. Player moves on.

### Property (owned by active player)

No effect.

### Station (unowned / owned)

Same buy/decline/rent rules as property. Rent based on number of stations owned by same player (see [Board and Setup][board-setup]).

### Utility (unowned / owned)

Same buy/decline rules. Rent = multiplier × current dice roll total. Multiplier depends on utilities owned by same player.

### Tax: Income Tax (square 04)

Player pays `income_tax_amount` or `income_tax_percentage` of net worth, whichever is configured.

| Config key | Default | Notes |
|------------|---------|-------|
| `income_tax_type` | `fixed` | `fixed` or `percentage` |
| `income_tax_amount` | 200 | Used when type is `fixed` |
| `income_tax_percentage` | 10 | Used when type is `percentage`; applied to net worth |

Player chooses before calculating (standard rule). If `income_tax_type` is `fixed`, no choice -- flat amount only.

### Tax: Super Tax (square 38)

Fixed payment. No choice.

| Config key | Default |
|------------|---------|
| `super_tax_amount` | 100 |

### Community Chest (squares 02, 17, 28)

Player draws top card from Community Chest deck, effect applied immediately. Card returned to bottom of deck (or reshuffled if deck exhausted).

### Chance (squares 07, 22, 33, 36)

Player draws top card from Chance deck, effect applied immediately. Same reshuffle behaviour.

### Free Parking (square 20)

Default: no effect. Player rests.

| Config key | Default | Notes |
|------------|---------|-------|
| `free_parking_jackpot` | false | If true, all tax and fine payments go into a Free Parking pot |
| `free_parking_starting_amount` | 0 | Starting pot when `free_parking_jackpot` is true |

When `free_parking_jackpot` is true and a player lands on Free Parking, they collect the entire pot. Pot resets to 0 after collection (not to `free_parking_starting_amount`).

### Go To Jail (square 30)

Player moves directly to jail square (10). Does not collect Go salary. `consecutive_doubles` resets to 0.

### Jail / Just Visiting (square 10)

Players passing through or landing on square 10 without being sent to jail are "just visiting" -- no effect.

---

## Jail

### Entering Jail

Three ways to be sent to jail:

1. Land on Go To Jail square (30)
2. Roll doubles three consecutive times
3. Draw a "Go to Jail" card from Chance or Community Chest

On entering jail: position set to square 10, `jail_status.in_jail = true`, `jail_status.turns_in_jail = 0`, `consecutive_doubles` resets.

### Leaving Jail

On each turn while in jail, player chooses one of:

1. **Roll doubles**: roll dice; if doubles, move by that amount and leave jail (turn continues normally, no extra turn for the doubles). If not doubles, `turns_in_jail` increments; player does not move.
2. **Pay fine**: pay `jail_fine`, then roll and move normally.
3. **Use Get Out of Jail Free card**: spend one card, then roll and move normally.
4. **Jailbreak** *(optional rule -- see below)*: move freely but spawn a police pawn that hunts the player.

After `jail_turns` consecutive failed rolls, player *must* pay the fine on their next turn and move.

| Config key | Default | Notes |
|------------|---------|-------|
| `jail_fine` | 50 | Amount to pay to leave jail |
| `jail_turns` | 3 | Failed rolls before forced payment |
| `jail_doubles_escape` | true | If false, player must pay or use card -- cannot roll out |
| `collect_go_while_in_jail` | false | If true, player collects Go salary while unable to move in jail |

---

### Jailbreak

Enabled via `jailbreak_enabled: true`. Adds a fourth escape option: the player breaks out and moves freely, but a police pawn is spawned and pursues them each turn.

#### Activation

Player selects jailbreak on any of their jail turns (including mandatory turns -- see Caught section below). No cost to activate. Player rolls dice and moves normally. A police pawn associated with that player spawns at square 10 (jail) immediately.

Up to one police pawn per player can be active at a time. With 8 players all jailbreaking simultaneously, 8 police pawns are on the board. Any jailbreaking player can be caught by any police pawn -- not only the one associated with them.

#### Police Pawn Movement

Each police pawn rolls on the turn of the player who spawned it, after that player moves and resolves their square action. Sequence per turn:

1. Active player rolls and moves
2. Square action resolved (rent, card, etc.)
3. Server checks: does this player occupy the same square as any active police pawn? If yes, caught (see Catch Conditions)
4. The police pawn spawned by the active player (if any) rolls and moves
5. Server checks: does any jailbreaking player occupy the same square as this pawn? If yes, caught

Step 5 can catch any jailbreaking player -- not just the pawn's owner. Police pawns owned by other players do not move on this turn; they move on their owner's turn.

Police movement is server-generated. No player controls any police pawn.

| Config key | Default | Options |
|------------|---------|---------|
| `police_check_mode` | `final` | `final` -- landing square only; `path` -- every square passed through |

`path` mode applies to both player movement (step 3) and police movement (step 5). In `path` mode, a player running into a stationary police pawn mid-move is caught.

#### Catch Conditions

A catch is triggered when a jailbreaking player and any police pawn occupy the same square. This includes:

- Police pawn lands on a jailbreaking player's square (pursuit)
- Jailbreaking player moves onto a police pawn's current square (player walks into police, including lapping the board and landing on the police from behind)
- In `path` mode: player passes through a square occupied by a police pawn, or police pawn passes through a square occupied by a jailbreaking player

The caught player is always the jailbreaking player on the shared square. The pawn's owner is irrelevant to the penalty -- catch count and fine escalation apply to whoever was caught.

#### Police Pawn Duration

Each pawn has its own duration clock, counting the turns of the player who spawned it.

| Config key | Default | Notes |
|------------|---------|-------|
| `police_duration` | `null` | `null` = indefinite; integer N = disappears after N of the spawning player's turns |

**Indefinite** (`null`): pawn persists until it catches a jailbreaking player, or until its spawning player is sent to jail by any means (Go To Jail square, third consecutive doubles, jail card). Non-catch jail entry removes the pawn without applying caught penalties to anyone.

**N turns**: pawn disappears after N of the spawning player's turns. Any jailbreaking player who survives until the pawn expires is free of that pawn. Other pawns on the board remain active.

When the spawning player is caught (by their own or another pawn), their pawn is removed. Other players' pawns are unaffected.

#### Being Caught

If police pawn lands on (or passes through, in `path` mode) the jailbreaking player's square:

1. Player is immediately returned to jail
2. Police pawn is removed from the board
3. Player serves `jailbreak_mandatory_turns` turns in which no escape option is available (not even another jailbreak)
4. After mandatory turns, the standard `jail_turns` escape window begins
5. The player's `jail_fine` is permanently doubled for the rest of the game (stacking -- each catch doubles the current fine again)

| Config key | Default | Notes |
|------------|---------|-------|
| `jailbreak_enabled` | false | Enables the jailbreak option |
| `jailbreak_mandatory_turns` | 3 | Turns in jail with no escape options after being caught |
| `jailbreak_fine_multiplier` | 2 | Fine multiplier applied on each catch (default: doubles each time) |

**Fine stacking example** (default `jail_fine: 50`, `jailbreak_fine_multiplier: 2`):

| Catches | Effective fine |
|---------|---------------|
| 0 | £50 |
| 1 | £100 |
| 2 | £200 |
| 3 | £400 |

The escalating fine applies only to the pay-to-leave option, not to GOOJF cards (which remain free).

#### Natural Escape

The police pawn persists indefinitely until it catches the player. There is no turn limit on how long a jailbreak can run. Players can theoretically evade the police pawn for the remainder of the game.

If the jailbreaking player is sent to jail by another means (Go To Jail square, third consecutive doubles, jail card) while already being pursued, the police pawn is removed and the standard caught penalty applies (mandatory turns + fine doubles).

#### State Tracking

Police pawns tracked at game level (not per-player) since any pawn can catch any player. Stored on `game_state`:

```json
{
  "active_police_pawns": [
    {
      "owner_id": "player-uuid-a",
      "position": 14,
      "turns_remaining": null
    },
    {
      "owner_id": "player-uuid-b",
      "position": 27,
      "turns_remaining": 2
    }
  ]
}
```

Per-player jail state stored on `game_state.jail_status[player_id]`:

```json
{
  "in_jail": false,
  "is_jailbreaking": true,
  "turns_in_jail": 0,
  "mandatory_turns_remaining": 0,
  "catch_count": 1,
  "effective_fine": 100,
  "has_card": false
}
```

`effective_fine` is the current jail fine for this player after catch-count multipliers. Starts at `jail_fine` config value and multiplies by `jailbreak_fine_multiplier` on each catch.

---

## Turn Time Limit

| Config key | Default | Notes |
|------------|---------|-------|
| `max_turn_time_secs` | null | null = no limit; integer = seconds before auto-action |

When a turn timer expires, the server applies the default action for the current phase:

| Phase | Auto-action on timeout |
|-------|----------------------|
| `roll` | Server rolls dice automatically |
| `action` (unowned property) | Decline to buy → triggers auction |
| `action` (card drawn) | Card effect already applied; proceed to end_turn |
| `trade` | All pending trade offers cancelled; proceed to end_turn |
| `end_turn` | Turn ends, next player begins |

---

## End of Turn

Player submits `end_turn` action. Server:

1. Validates no outstanding actions remain (unpaid rent, pending trades)
2. Advances `current_player_id` to next non-bankrupt player in `seat_order`
3. Increments `turn_number` when turn cycles back to seat 0
4. Sets phase to `roll`
5. Writes updated `game_state`
6. Supabase broadcasts to all clients

---

[properties]: ./03-properties.md
[board-setup]: ./01-board-and-setup.md
