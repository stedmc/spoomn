# Properties

## Buying

### Direct Purchase

When a player lands on an unowned property, station, or utility, they may buy it at face value. Server validates:

- Player has sufficient funds
- Property is unowned (bank-owned)
- It is the player's action phase

On purchase: player balance decreases by price, `property_ownership[square_index]` set to `player_id`, game_log entry written.

### Declining to Buy

If the player declines (or timer expires during action phase), the property goes to auction. See [Auctions](#auctions) below.

| Config key | Default | Notes |
|------------|---------|-------|
| `auction_on_decline` | true | If false, declined property returns to bank with no auction |

---

## Rent

### Collecting Rent

When a player lands on a property owned by another player, rent is owed immediately.

| Config key | Default | Notes |
|------------|---------|-------|
| `auto_claim_rent` | true | Server auto-deducts rent; if false, owner must manually claim before next roll |

If `auto_claim_rent` is false and the owner fails to claim before the next player rolls, rent is forfeit for that landing.

### Colour Set Bonus

If a player owns all properties in a colour group, base rent (no houses) doubles. Building houses or hotels replaces the base rent -- the colour set multiplier applies to base rent only.

### Rent with Buildings

Rent increases with each house built, and again when a hotel replaces the four houses. See rent tables in [Board and Setup][board-setup].

### Stations

Rent based on total stations owned by the same player:

| Stations owned | Rent |
|---------------|------|
| 1 | £25 |
| 2 | £50 |
| 3 | £100 |
| 4 | £200 |

### Utilities

Rent is a multiplier of the current dice roll total (the roll that moved the landing player, not a fresh roll):

| Utilities owned | Multiplier |
|----------------|------------|
| 1 | 4× |
| 2 | 10× |

---

## Building

### Eligibility

A player may build houses or hotels on a property only when they own the entire colour group. No buildings on stations or utilities.

### Even Building Rule

Houses must be built evenly across the colour group. No property in a group may have more than one house more than any other property in the same group. Same rule applies when selling -- must sell evenly.

| Config key | Default | Notes |
|------------|---------|-------|
| `must_build_evenly` | true | If false, player may build unevenly across a colour group |

### Building Limits

Houses and hotels are drawn from a global pool shared across all players (see [Board and Setup][board-setup]). If the pool is exhausted, no further buildings of that type can be placed anywhere until another player sells or demolishes.

### Placing a Hotel

When a player places a hotel on a property, the four houses on that property return to the bank (global pool). One hotel token is placed.

| Config key | Default | Notes |
|------------|---------|-------|
| `hotel_requires_four_houses` | true | If false, hotel can be placed directly without four houses first |
| `houses_returned_on_hotel` | true | If false, houses stay on board alongside hotel (cosmetic only -- rent uses hotel value) |

### Building During Whose Turn

| Config key | Default | Notes |
|------------|---------|-------|
| `build_own_turn_only` | false | If true, player may only build during their own turn |

Default: players may build at any time (between other players' actions), which allows strategic building to block house supply.

### Selling Buildings

Player may sell houses or hotels back to the bank at half the build cost. Must sell evenly across the colour group. On hotel sale, player receives houses from the bank to replace it (4 houses back onto the property) if houses are available in the pool. If house pool is exhausted, hotel cannot be sold until houses are available.

| Config key | Default | Notes |
|------------|---------|-------|
| `sell_building_rate` | 0.5 | Fraction of build cost returned on sale (default: 50%) |

---

## Mortgage

### Mortgaging

Player may mortgage an unimproved property to the bank for its mortgage value (50% of purchase price by default). No houses or hotels may be present on any property in the same colour group when mortgaging.

On mortgage: player receives mortgage value, property marked `mortgaged[square_index] = true`. No rent can be collected on a mortgaged property.

| Config key | Default | Notes |
|------------|---------|-------|
| `mortgage_rate` | 0.5 | Fraction of purchase price paid out on mortgage |

### Unmortgaging

Player pays mortgage value plus interest to lift the mortgage.

| Config key | Default | Notes |
|------------|---------|-------|
| `unmortgage_interest_rate` | 0.1 | Interest charged on top of mortgage value to unmortgage (default: 10%) |

Total unmortgage cost = `purchase_price × mortgage_rate × (1 + unmortgage_interest_rate)`

Default example: £300 property → mortgage £150 → unmortgage £165.

### Mortgaged Properties in Trades

Mortgaged properties can be traded. When received in a trade, the new owner must either:

1. Pay the 10% interest immediately (lift the mortgage at the standard cost), or
2. Hold the property mortgaged and pay a 10% penalty to the bank at time of unmortgage

| Config key | Default | Notes |
|------------|---------|-------|
| `trade_mortgaged_properties` | true | If false, mortgaged properties cannot be included in trades |
| `mortgage_transfer_penalty` | 0.1 | Interest rate new owner pays on unmortgage of a traded mortgaged property |

---

## Auctions

Triggered when a player declines to buy a property (if `auction_on_decline` is true). All players -- including the player who declined -- may participate.

### Auction Styles

| Config key | Default | Options |
|------------|---------|---------|
| `auction_style` | `ascending` | `ascending`, `blind`, `dutch` |

#### Ascending

Open ascending bid. Players take turns raising the bid. Minimum raise configurable. Auction ends when all but one player have passed. Winning bidder pays their bid.

| Config key | Default |
|------------|---------|
| `auction_starting_bid` | 1 |
| `auction_min_raise` | 1 |
| `auction_time_per_bid_secs` | 30 |

#### Blind

All players submit a sealed bid simultaneously within a time limit. Highest bid wins. Ties broken by earliest submission. Winning bidder pays their bid.

| Config key | Default |
|------------|---------|
| `auction_blind_time_secs` | 60 |
| `auction_min_bid` | 1 |

#### Dutch

Auction starts at a high price (configurable) and decreases by a fixed amount each interval. First player to claim wins at the current price.

| Config key | Default | Notes |
|------------|---------|-------|
| `dutch_start_price` | purchase_price | Starting price; defaults to face value |
| `dutch_decrement` | 10 | Amount price drops per interval |
| `dutch_interval_secs` | 5 | Seconds between price drops |
| `dutch_floor_price` | 1 | Minimum price; auction cancelled if no buyer at floor |

### Auction Bankruptcy

If a winning bidder cannot pay (edge case: bid exceeds balance due to simultaneous game events), standard bankruptcy rules apply. Property goes to the next highest bidder if buyer cannot pay after asset liquidation.

---

## Bankruptcy and Property Liquidation

When a player cannot pay a debt, they must liquidate assets. Liquidation order:

1. Sell buildings (houses/hotels) back to bank at sell rate
2. Mortgage unimproved properties
3. If still unable to pay: bankrupt

On bankruptcy:

- **Debt owed to bank**: all remaining properties returned to bank (unmortgaged). Buildings sold at sell rate. Cash goes to bank.
- **Debt owed to player**: all remaining assets (properties, mortgaged or not, cash) transfer directly to the creditor. Creditor receives properties at their current mortgage state -- standard `mortgage_transfer_penalty` applies on future unmortgage.

| Config key | Default | Options |
|------------|---------|---------|
| `bankruptcy_assets_to` | `creditor` | `creditor` -- assets to the player owed; `bank` -- all assets always return to bank |

See [Winning and Bankruptcy][winning] for full elimination rules.

---

[board-setup]: ./01-board-and-setup.md
[winning]: ./06-winning-and-bankruptcy.md
