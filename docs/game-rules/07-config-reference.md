# Config Reference

Complete list of every configurable option. This is the source of truth for `room_configs` schema and server rule engine defaults. All keys are optional -- omitting any key uses the default value shown.

Conditional keys are marked with a dependency. The server ignores conditional keys when their dependency condition is not met.

---

## Setup and Bank

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `starting_money` | `1500` | int | Per-player starting balance |
| `bank_unlimited` | `false` | bool | If true, bank never runs out of money or buildings |
| `bank_starting_amount` | `20580` | int | Ignored when `bank_unlimited` is true |
| `house_limit` | `32` | int\|null | Global house pool; null = unlimited |
| `hotel_limit` | `12` | int\|null | Global hotel pool; null = unlimited |
| `turn_order_method` | `"highest_roll"` | enum | `highest_roll`, `random`, `host_assigned` |

---

## Dice

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `dice_count` | `2` | int | Number of dice rolled per turn (1--4) |
| `dice_sides` | `6` | int | Sides per die: 4, 6, 8, 10, 12, or 20 |
| `doubles_enabled` | `true` | bool | If false, matching dice treated as a normal roll |
| `doubles_extra_turn` | `true` | bool | Roll again on doubles; ignored if `doubles_enabled` is false |
| `jail_on_consecutive_doubles` | `3` | int\|null | Jail after N consecutive doubles; null = never jail for doubles |

---

## Movement and Go

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `go_salary` | `200` | int | Collected each time player passes or lands on Go |
| `go_landing_bonus` | `0` | int | Extra collected for landing exactly on Go (added to `go_salary`) |

---

## Rent

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `auto_claim_rent` | `true` | bool | Server auto-deducts rent on landing; if false, owner must manually claim before next roll |

---

## Tax Squares

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `income_tax_type` | `"fixed"` | enum | `fixed` or `percentage` |
| `income_tax_amount` | `200` | int | Used when `income_tax_type` is `fixed` |
| `income_tax_percentage` | `10` | int | Percentage of net worth; used when `income_tax_type` is `percentage` |
| `super_tax_amount` | `100` | int | Fixed amount paid on Super Tax square |

---

## Free Parking

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `free_parking_jackpot` | `false` | bool | All tax and fine payments accumulate in a pot; landing player collects |
| `free_parking_starting_amount` | `0` | int | Starting pot value; used only when `free_parking_jackpot` is true |

---

## Turn Timer

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `max_turn_time_secs` | `null` | int\|null | Seconds per turn phase before auto-action; null = no limit |

---

## Jail

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `jail_fine` | `50` | int | Base cost to pay to leave jail |
| `jail_turns` | `3` | int | Failed roll attempts before forced payment |
| `jail_doubles_escape` | `true` | bool | If false, player cannot roll doubles to escape |
| `collect_go_while_in_jail` | `false` | bool | If true, player collects Go salary while serving jail turns |

---

## Jailbreak

All keys ignored when `jailbreak_enabled` is false.

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `jailbreak_enabled` | `false` | bool | Enables jailbreak escape option |
| `jailbreak_mandatory_turns` | `3` | int | Turns with no escape options after being caught |
| `jailbreak_fine_multiplier` | `2` | int | Multiplier applied to `effective_fine` on each catch |
| `police_check_mode` | `"final"` | enum | `final` -- landing square only; `path` -- every square passed through |
| `police_duration` | `null` | int\|null | Police pawn lifespan in jailbreaking player turns; null = indefinite |

---

## Buildings

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `must_build_evenly` | `true` | bool | Houses must be built and sold evenly across a colour group |
| `hotel_requires_four_houses` | `true` | bool | If false, hotel can be placed without four houses first |
| `houses_returned_on_hotel` | `true` | bool | If false, houses remain on board when hotel placed (cosmetic only) |
| `build_own_turn_only` | `false` | bool | If true, buildings can only be placed during the player's own turn |
| `sell_building_rate` | `0.5` | float | Fraction of build cost returned when selling buildings (0.0--1.0) |

---

## Mortgage

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `mortgage_rate` | `0.5` | float | Fraction of purchase price paid out on mortgage |
| `unmortgage_interest_rate` | `0.1` | float | Interest charged on top of mortgage value to unmortgage |
| `trade_mortgaged_properties` | `true` | bool | If false, mortgaged properties cannot be included in trades |
| `mortgage_transfer_penalty` | `0.1` | float | Interest rate new owner pays on unmortgage of a received mortgaged property |

---

## Auctions

| Key | Default | Type | Condition | Notes |
|-----|---------|------|-----------|-------|
| `auction_on_decline` | `true` | bool | -- | If false, declined properties return to bank unsold |
| `auction_style` | `"ascending"` | enum | `auction_on_decline: true` | `ascending`, `blind`, `dutch` |
| `auction_starting_bid` | `1` | int | `auction_style: "ascending"` | Opening bid |
| `auction_min_raise` | `1` | int | `auction_style: "ascending"` | Minimum raise over current bid |
| `auction_time_per_bid_secs` | `30` | int | `auction_style: "ascending"` | Time per bid before player passes |
| `auction_blind_time_secs` | `60` | int | `auction_style: "blind"` | Window for all players to submit sealed bids |
| `auction_min_bid` | `1` | int | `auction_style: "blind"` | Minimum valid bid |
| `dutch_start_price` | purchase price | int\|null | `auction_style: "dutch"` | null = defaults to property face value |
| `dutch_decrement` | `10` | int | `auction_style: "dutch"` | Amount price drops per interval |
| `dutch_interval_secs` | `5` | int | `auction_style: "dutch"` | Seconds between price drops |
| `dutch_floor_price` | `1` | int | `auction_style: "dutch"` | Auction cancelled if floor reached with no buyer |

---

## Trading

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `trade_any_turn` | `false` | bool | If true, trades can be proposed and accepted at any time |
| `multi_party_trades` | `false` | bool | If true, trades may involve any number of players |
| `trade_futures` | `false` | bool | If true, future rent immunity can be included in trades |
| `trade_timeout_secs` | `null` | int\|null | Seconds before a pending trade auto-cancels; null = no timeout |

---

## Cards

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `custom_community_chest` | `null` | Card[]\|null | Replaces default Community Chest deck entirely when set |
| `custom_chance` | `null` | Card[]\|null | Replaces default Chance deck entirely when set |

See [Cards and Spaces][cards] for card schema and effect types.

---

## Winning Condition

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `winning_condition` | `"last_player_standing"` | enum | `last_player_standing`, `net_worth_target`, `turn_limit`, `time_limit` |
| `net_worth_target` | `10000` | int | Target net worth to win; used when `winning_condition` is `net_worth_target` |
| `net_worth_check` | `"end_of_turn"` | enum | `end_of_turn`, `real_time`; used when `winning_condition` is `net_worth_target` |
| `turn_limit` | `30` | int | Rounds before game ends; used when `winning_condition` is `turn_limit` |
| `time_limit_mins` | `60` | int | Minutes before game ends; used when `winning_condition` is `time_limit` |

---

## Bankruptcy

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `bankruptcy_assets_to` | `"creditor"` | enum | `creditor` -- assets to the player owed; `bank` -- all assets return to bank |
| `allow_bankruptcy_negotiation` | `false` | bool | If true, player facing bankruptcy may propose trade or repayment plan |
| `negotiation_timeout_secs` | `120` | int | Seconds to propose a deal; forced bankruptcy on expiry; used when `allow_bankruptcy_negotiation` is true |
| `repayment_interest_rate` | `0` | float | Interest per turn on repayment plan balance; used when `allow_bankruptcy_negotiation` is true |

---

## Loans

All keys ignored when `loans_enabled` is false.

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `loans_enabled` | `false` | bool | Enables player borrowing from the bank |
| `loan_amount` | `200` | int | Fixed amount per loan request |
| `loan_interest_rate` | `0.1` | float | Interest charged per full turn while loan outstanding |
| `max_loans_per_player` | `3` | int | Maximum simultaneous outstanding loans per player |

---

## Play Mode

| Key | Default | Type | Notes |
|-----|---------|------|-------|
| `play_mode` | `"realtime"` | enum | `realtime` -- all players online simultaneously; `async` -- players take turns at own pace |
| `async_turn_timeout_hours` | `null` | int\|null | Hours before auto-action on inactive async turn; null = no expiry |
| `async_turn_reminder_hours` | `null` | int\|null | Hours before expiry to send a reminder notification; null = no reminder |

`async_turn_timeout_hours` and `async_turn_reminder_hours` ignored when `play_mode` is `realtime`. Use `max_turn_time_secs` for real-time turn timers instead.

---

## Quick Reference: House Rules

Common presets for reference. These are not built-in modes -- set the individual keys manually.

| Preset | Keys to change from default |
|--------|-----------------------------|
| **Speed game** | `turn_limit: 20`, `starting_money: 2000`, `auction_on_decline: true`, `auto_claim_rent: true` |
| **Chaos mode** | `jailbreak_enabled: true`, `multi_party_trades: true`, `trade_futures: true`, `trade_any_turn: true`, `custom_community_chest: [...]`, `custom_chance: [...]` |
| **Classic strict** | `must_build_evenly: true`, `hotel_requires_four_houses: true`, `auction_on_decline: true`, `bankruptcy_assets_to: "creditor"`, `auto_claim_rent: false` |
| **Forgiving** | `allow_bankruptcy_negotiation: true`, `loans_enabled: true`, `bank_unlimited: true`, `jail_doubles_escape: true` |

---

[cards]: ./05-cards-and-spaces.md
