# Cards and Spaces

## Card Decks

Two decks exist by default: Community Chest and Chance. Each deck is shuffled at game start. Cards are drawn from the top; drawn cards go to the bottom unless they are "keep" cards (Get Out of Jail Free). When the deck is exhausted, it is reshuffled.

---

## Default Community Chest Deck

16 cards. Drew from squares 02, 17, 28.

| # | Card | Effect |
|---|------|--------|
| 1 | Advance to Go | Move to square 00, collect Go salary |
| 2 | Bank error in your favour | Collect £200 |
| 3 | Doctor's fee | Pay £50 |
| 4 | From sale of stock | Collect £50 |
| 5 | Get Out of Jail Free | Keep card; use to leave jail for free |
| 6 | Go to Jail | Go directly to jail |
| 7 | Grand Opera Night | Collect £50 from each player |
| 8 | Holiday fund matures | Collect £100 |
| 9 | Income tax refund | Collect £20 |
| 10 | It is your birthday | Collect £10 from each player |
| 11 | Life insurance matures | Collect £100 |
| 12 | Pay hospital fees | Pay £100 |
| 13 | Pay school fees | Pay £50 |
| 14 | Receive consultancy fee | Collect £25 |
| 15 | Street repairs | Pay £40 per house, £115 per hotel owned |
| 16 | You inherit £100 | Collect £100 |

---

## Default Chance Deck

16 cards. Drawn from squares 07, 22, 33, 36.

| # | Card | Effect |
|---|------|--------|
| 1 | Advance to Go | Move to square 00, collect Go salary |
| 2 | Advance to Trafalgar Square | Move to square 24; pay rent if owned |
| 3 | Advance to Pall Mall | Move to square 11; pay rent if owned |
| 4 | Advance to nearest station (×2 rent) | Move to nearest station; if owned pay double rent |
| 5 | Advance to nearest station (×2 rent) | Second copy of card 4 |
| 6 | Advance to nearest utility | Move to nearest utility; if owned pay 10× dice roll |
| 7 | Bank pays dividend | Collect £50 |
| 8 | Get Out of Jail Free | Keep card; use to leave jail for free |
| 9 | Go back 3 spaces | Move back 3 squares from current position |
| 10 | Go to Jail | Go directly to jail |
| 11 | Make general repairs | Pay £25 per house, £100 per hotel owned |
| 12 | Pay poor tax | Pay £15 |
| 13 | Take trip to King's Cross | Move to square 05; pay rent if owned |
| 14 | Take a walk on the Old Kent Road | Move to square 01; pay rent if owned |
| 15 | Elected chairman of the board | Pay £50 to each player |
| 16 | Building loan matures | Collect £150 |

### Nearest Station / Utility Logic

"Advance to nearest station" moves the player forward (clockwise) to the next station square. If they pass Go, they collect the Go salary. Same logic for nearest utility. Server calculates nearest by comparing current position to all station/utility square indices and selecting the smallest positive clockwise distance.

---

## Card Effect Types

All card effects are defined by type. Custom decks use these same types.

| Effect type | Parameters | Description |
|-------------|-----------|-------------|
| `move_to` | `square: int` | Move directly to square index; collect Go if passing |
| `move_relative` | `squares: int` | Move forward or backward N squares (negative = back) |
| `move_to_nearest` | `square_type: string`, `rent_multiplier?: float` | Move to nearest square of given type |
| `collect` | `amount: int` | Collect from bank |
| `pay` | `amount: int` | Pay to bank (or Free Parking pot if enabled) |
| `collect_from_each` | `amount: int` | Collect `amount` from every other player |
| `pay_each` | `amount: int` | Pay `amount` to every other player |
| `pay_per_building` | `house_amount: int`, `hotel_amount: int` | Pay per house and hotel owned |
| `go_to_jail` | -- | Send to jail |
| `keep_goojf` | -- | Player keeps card; returned to deck when used |
| `rent_protection` | see below | Grant rent immunity; player holds and activates |
| `rent_discount` | see below | Reduce rent owed; player holds and activates |
| `place_trap` | see below | Player places a booby trap on a chosen square |

---

## Rent Protection Cards

`keep: true` card. Player holds it and activates it manually at any point before paying rent (during another player's action phase or their own). Once activated, protection applies immediately.

```json
{
  "id": "rp_1",
  "label": "Rent Shield -- immunity for 3 landings",
  "effect": {
    "type": "rent_protection",
    "scope": "all",
    "colour_group": null,
    "square_indices": null,
    "duration_type": "landings",
    "duration": 3
  },
  "keep": true
}
```

| Parameter | Options | Description |
|-----------|---------|-------------|
| `scope` | `all`, `colour`, `specific` | Which properties the protection applies to |
| `colour_group` | string or null | Required when `scope` is `colour` (e.g. `"red"`) |
| `square_indices` | int[] or null | Required when `scope` is `specific` |
| `duration_type` | `landings`, `turns`, `one_use` | How protection duration is measured |
| `duration` | int | Number of landings or turns; ignored for `one_use` |

`landings`: counts each protected landing. `turns`: counts full turn cycles regardless of landings. `one_use`: activates automatically on the next applicable landing, then expires.

Protection state stored on `game_state.rent_modifiers[player_id]`:

```json
{
  "protections": [
    {
      "source_card_id": "rp_1",
      "scope": "all",
      "colour_group": null,
      "square_indices": null,
      "duration_type": "landings",
      "remaining": 3
    }
  ]
}
```

---

## Rent Discount Cards

`keep: true` card. Player holds and activates before paying rent. Reduces the rent owed by a fixed amount or percentage, down to a minimum of £0 (cannot produce negative rent / a payment from the owner).

```json
{
  "id": "rd_1",
  "label": "Haggler -- pay 50% rent on your next landing",
  "effect": {
    "type": "rent_discount",
    "scope": "all",
    "colour_group": null,
    "square_indices": null,
    "discount_type": "percentage",
    "discount_value": 50,
    "duration_type": "one_use",
    "duration": 1
  },
  "keep": true
}
```

| Parameter | Options | Description |
|-----------|---------|-------------|
| `discount_type` | `percentage`, `fixed` | How discount is calculated |
| `discount_value` | int | Percentage (0--100) or fixed amount |
| `scope`, `colour_group`, `square_indices`, `duration_type`, `duration` | same as rent protection | |

Multiple discount cards can be held simultaneously. If a player activates more than one on the same landing, discounts stack: percentage discounts apply to the base rent sequentially, fixed discounts are summed and subtracted after percentage discounts. Combined discount cannot reduce rent below £0.

---

## Booby Trap Cards

`keep: true` card. Player holds the trap until they choose to place it (during their turn or trade phase). Once placed, the trap sits on a square and triggers when any other player lands on it.

### Placement

| Parameter | Options | Description |
|-----------|---------|-------------|
| `placement` | `player_choice`, `random` | Whether the player selects the square or the server assigns one randomly |

`player_choice`: on activation, the client presents a square selector. Player picks any square except Go (00), Jail (10), Free Parking (20), and Go To Jail (30). Server validates the chosen square is legal before placing.

`random`: server selects a random square from all eligible squares (excludes Go, Jail, Free Parking, Go To Jail) at the moment of placement. Player does not choose.

Both placement modes are defined per card -- a deck can contain a mix.

### Visibility

Defined per card via the `visible` parameter.

| `visible` | Placer sees | Other players see |
|-----------|-------------|-------------------|
| `true` | Square highlighted, owner label shown | Square highlighted, owner label shown |
| `false` | Square highlighted, owner label shown | Notified a trap exists somewhere; square not revealed |

`visible: false` (invisible trap): when placed, all other players receive a game log entry ("A trap has been placed") but the square is not shown on their board. The placer always sees their own invisible traps. On trigger, the square is revealed to all players at the moment of firing.

Multiple invisible traps from different players produce one notification per placement -- players know how many invisible traps are active in total but not their locations.

The server enforces this by filtering `active_traps` before broadcasting: invisible traps have their `square_index` redacted (set to `null`) in the Realtime payload for non-owner clients. The placer always receives the full unredacted state for their own traps.

### Stacking

Multiple traps can occupy the same square simultaneously, from the same or different players. Each trap triggers independently when a player lands. A single landing can trigger multiple traps if several are stacked on that square. Effects are applied in placement order (oldest first).

### Trigger Count

| Parameter | Options | Description |
|-----------|---------|-------------|
| `trigger_count` | int or `null` | Number of times the trap triggers before being removed; `null` = unlimited |

`trigger_count: 1`: one-shot trap. Removed from board after first trigger.
`trigger_count: N`: triggers N times then removed.
`trigger_count: null`: permanent until removed by owner, traded away, or disarmed.

### Trigger Effects

When a player lands on a trapped square, each trap on that square fires its `trigger_effect`. The victim is always the landing player. The beneficiary of any financial effect is defined per card.

| `beneficiary` | Description |
|---------------|-------------|
| `placer` | Financial gain goes to the current trap owner |
| `bank` | Financial gain goes to bank (or Free Parking pot if enabled) |

Trigger effects use the same effect types as standard cards:

```json
{
  "type": "place_trap",
  "placement": "player_choice",
  "trigger_count": 1,
  "trigger_effect": {
    "type": "pay",
    "amount": 150,
    "beneficiary": "placer"
  }
}
```

Any card effect type is valid as a `trigger_effect` except `place_trap`, `rent_protection`, `rent_discount`, and `keep_goojf` (these cannot be triggered by a trap).

### Ownership and Trading

Traps are owned by the player who placed them. Ownership can be transferred via trade -- the new owner receives future trigger benefits. Trap remains on its square; only ownership changes. Traded traps retain their remaining trigger count.

Traps are listed as tradeable assets in the trade proposal UI alongside properties and money.

### Removal

Three ways to remove a trap:

1. **Owner removes it**: during their turn (trade phase), the owner can voluntarily remove any of their traps from the board. No cost. Removed trap is discarded -- not returned to deck.
2. **Traded**: ownership transferred (trap stays on board, new owner controls it).
3. **Disarmed by card**: a `disarm_trap` card effect removes a trap from the board entirely (see below).

### Disarm Card

A separate card type that removes traps from the board. Can target a specific square or clear all traps on a square.

```json
{
  "id": "disarm_1",
  "label": "Bomb disposal -- remove all traps from one square",
  "effect": {
    "type": "disarm_trap",
    "targeting": "player_choice",
    "scope": "all_on_square"
  },
  "keep": true
}
```

| Parameter | Options | Description |
|-----------|---------|-------------|
| `targeting` | `player_choice`, `random_square`, `all_board` | Which square(s) to disarm |
| `scope` | `all_on_square`, `oldest_on_square`, `newest_on_square` | Which traps to remove when multiple are stacked |

`all_board` with `all_on_square` removes every trap from every square -- a board wipe.

Disarmed traps are removed without triggering. Owners are notified via game log.

### State Tracking

Traps stored at game level in `game_state.active_traps`:

```json
{
  "active_traps": [
    {
      "trap_id": "uuid",
      "source_card_id": "trap_1",
      "square_index": 24,
      "owner_id": "player-uuid-a",
      "visible": false,
      "placed_turn": 12,
      "triggers_remaining": 3,
      "trigger_effect": {
        "type": "pay",
        "amount": 150,
        "beneficiary": "placer"
      }
    }
  ]
}
```

`triggers_remaining: null` = unlimited. Trap removed from array when `triggers_remaining` reaches 0 or when explicitly removed.

Server never writes `active_traps` directly to the Realtime broadcast. Instead, before writing `game_state`, the server constructs a per-player view: invisible traps owned by other players have `square_index` set to `null` and `trigger_effect` redacted. Each client receives only what they are permitted to see. The authoritative `square_index` always exists in the server-side Postgres row.

---

## Custom Card Decks

| Config key | Default | Notes |
|------------|---------|-------|
| `custom_community_chest` | null | Custom deck replaces default Community Chest entirely |
| `custom_chance` | null | Custom deck replaces default Chance entirely |

When a custom deck is provided, the default deck is discarded completely -- cards are not merged. Minimum deck size: 2 cards. No maximum.

### Custom Card Schema

```json
{
  "id": "unique-card-id",
  "label": "Display text shown to all players",
  "effect": {
    "type": "collect",
    "amount": 200
  },
  "keep": false
}
```

`keep: true` marks the card as a held card (like Get Out of Jail Free) -- it stays with the player until used and is not returned to the deck on draw.

### Custom Deck Example

```json
[
  {
    "id": "cc_custom_1",
    "label": "You found a fiver down the sofa",
    "effect": { "type": "collect", "amount": 5 },
    "keep": false
  },
  {
    "id": "cc_custom_2",
    "label": "Tax audit. Pay £300.",
    "effect": { "type": "pay", "amount": 300 },
    "keep": false
  },
  {
    "id": "cc_custom_3",
    "label": "Get Out of Jail Free",
    "effect": { "type": "keep_goojf" },
    "keep": true
  }
]
```

Custom decks stored as JSONB in `room_configs`. Server validates all card effect types and parameters before the game starts.

---

## Special Squares

### Go (square 00)

Player collects `go_salary` each time they pass or land. See [Turn Flow][turn-flow] for `go_landing_bonus` config.

### Jail / Just Visiting (square 10)

Players not sent to jail are just visiting -- no effect. See [Turn Flow][turn-flow] for full jail rules including jailbreak.

### Free Parking (square 20)

Default: no effect.

With `free_parking_jackpot: true`: player collects the accumulated pot. Pot is funded by all tax payments and fines paid to the bank during the game.

| Config key | Default |
|------------|---------|
| `free_parking_jackpot` | false |
| `free_parking_starting_amount` | 0 |

### Go To Jail (square 30)

Player sent directly to jail. Does not collect Go salary. Consecutive doubles counter resets.

### Income Tax (square 04)

| Config key | Default | Options |
|------------|---------|---------|
| `income_tax_type` | `fixed` | `fixed`, `percentage` |
| `income_tax_amount` | 200 | Used when type is `fixed` |
| `income_tax_percentage` | 10 | Used when type is `percentage`; applied to net worth |

With `percentage`: net worth = cash + property values (purchase price) + building values (build cost) - mortgage debts. Player sees calculated amount before confirming.

### Super Tax (square 38)

| Config key | Default |
|------------|---------|
| `super_tax_amount` | 100 |

---

## Get Out of Jail Free Cards

GOOJF cards can be held by players indefinitely. A player may hold multiple GOOJF cards simultaneously (one from each deck, or via trades).

GOOJF cards are tradeable (see [Trading][trading]). When traded, the card moves from one player's hand to another. The receiving player can use it to leave jail.

On use: card is returned to the bottom of its source deck.

`game_state.get_out_of_jail_cards[player_id]` tracks count only -- source deck tracked separately to ensure correct return on use.

---

[turn-flow]: ./02-turn-flow.md
[trading]: ./04-trading.md
