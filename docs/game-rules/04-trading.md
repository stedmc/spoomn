# Trading

## Overview

Players may trade properties, money, and Get Out of Jail Free cards with each other. Trades are negotiated in real time -- any player may propose a trade to any other player at any point during the trade phase.

The server validates all trades before applying them. No trade takes effect until all involved parties accept.

---

## When Trading is Allowed

| Config key | Default | Notes |
|------------|---------|-------|
| `trade_any_turn` | false | If false, trades may only be initiated during the active player's trade phase; if true, any player may initiate a trade at any time |

With `trade_any_turn: false`: trade proposals can be submitted at any time, but they cannot be accepted until the active player's trade phase. Proposals sit as `pending` until then.

With `trade_any_turn: true`: trades can be proposed and accepted at any point in the game, including mid-turn of another player. The active player's turn is paused while a trade resolves, then resumes.

---

## Participants

| Config key | Default | Notes |
|------------|---------|-------|
| `multi_party_trades` | false | If true, trades may involve any number of players; if false, trades are 2-way only |

**2-way trade**: one proposer, one recipient. Standard Monopoly. Always available.

**Multi-party trade** (enabled by `multi_party_trades: true`): one proposer, any number of recipients up to all other players in the game. All participants must accept for the trade to complete. Any participant rejecting cancels the entire trade. Assets flow as specified in the offer -- each participant defines what they give and what they receive.

Multi-party trade example (3-way):

```
Player A gives: Park Lane + £100   receives: Bow Street
Player B gives: Bow Street          receives: £200
Player C gives: £200                receives: Park Lane + £100
```

Server validates the trade is balanced (every item given has a corresponding receiver) before presenting to participants.

---

## Tradeable Assets

| Asset | Tradeable | Notes |
|-------|-----------|-------|
| Properties (unmortgaged) | Always | |
| Properties (mortgaged) | Configurable | See `trade_mortgaged_properties` in [Properties][properties] |
| Money | Always | Cannot trade more than current balance |
| Get Out of Jail Free cards | Always | |
| Future rent immunity | Configurable | See below |
| Buildings (houses/hotels) | Never | Buildings cannot be transferred directly; must be sold to bank first |

### Future Rent Immunity

| Config key | Default | Notes |
|------------|---------|-------|
| `trade_futures` | false | If true, players may include future rent immunity as a trade asset |

When enabled, a player may offer another player immunity from rent on specific properties for a specified number of landings or turns. Example: "free rent on Mayfair for your next 3 landings."

Immunity terms stored on `game_state` and enforced by the server on each landing. Immunity is non-transferable once granted -- it cannot be included in a subsequent trade.

```json
{
  "rent_immunities": [
    {
      "beneficiary_id": "player-uuid-b",
      "property_index": 39,
      "landings_remaining": 3
    }
  ]
}
```

---

## Trade Flow

### Proposing

Any player submits a trade proposal to the server:

```
POST /api/rooms/{room_id}/trades
{
  "participants": ["player-a", "player-b"],
  "legs": [
    { "from": "player-a", "to": "player-b", "properties": [39], "money": 100, "jail_cards": 0 },
    { "from": "player-b", "to": "player-a", "properties": [16], "money": 0, "jail_cards": 0 }
  ]
}
```

Server validates:
- All participants are in the room and not bankrupt
- Proposer owns all assets they are offering
- Money offered does not exceed proposer's balance
- `max_trade_participants` not exceeded
- No other pending trade exists between the same set of participants

Trade written to `pending_trades` with status `pending`. Supabase Realtime notifies all participants.

### Countering

Any recipient may counter rather than accept or reject outright. A counter replaces the existing `pending_trades` row with a new proposal (status `countered`). The original proposer is now a recipient and must accept, counter again, or reject.

Counter chain has no depth limit -- participants may counter indefinitely until someone accepts or rejects.

### Accepting

All non-proposing participants must accept. When the last required acceptance arrives, server:

1. Validates all assets are still owned by the offering party (state may have changed during negotiation)
2. Transfers all assets atomically in a single `game_state` write
3. Sets `pending_trades.status = 'accepted'`
4. Writes game_log entries for each asset transferred
5. Broadcasts updated `game_state`

If any asset is no longer valid at acceptance time (e.g. a property was used to pay a debt during negotiation), the trade is cancelled automatically and all participants notified.

### Rejecting

Any participant may reject at any time. Trade cancelled, status set to `rejected`. No assets move.

### Cancelling

The proposer may cancel a pending or countered trade at any time before all acceptances are received.

### Timeout

| Config key | Default | Notes |
|------------|---------|-------|
| `trade_timeout_secs` | null | Seconds before a pending trade auto-cancels; null = no timeout |

---

## Simultaneous Trades

Multiple trades can be `pending` simultaneously, provided no asset appears in more than one pending trade at a time. The server rejects a new proposal if any offered asset is already committed in another pending trade.

---

## Constraints Summary

| Rule | Config key | Default |
|------|------------|---------|
| Multi-party trades | `multi_party_trades` | false |
| Trade on any turn | `trade_any_turn` | false |
| Include mortgaged properties | `trade_mortgaged_properties` | true |
| Include future rent immunity | `trade_futures` | false |
| Auto-cancel timeout | `trade_timeout_secs` | null |

---

[properties]: ./03-properties.md
