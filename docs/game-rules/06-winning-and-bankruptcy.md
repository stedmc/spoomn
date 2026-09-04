# Winning and Bankruptcy

## Winning Conditions

Multiple winning conditions are supported. One is active per game, selected in the lobby before start.

| Config key | Default | Options |
|------------|---------|---------|
| `winning_condition` | `last_player_standing` | `last_player_standing`, `net_worth_target`, `turn_limit`, `time_limit` |

---

### Last Player Standing

Default. Game ends when all players but one are bankrupt. The surviving player wins.

No additional configuration.

---

### Net Worth Target

First player to reach or exceed a target net worth wins immediately. Game ends at that moment -- no turn completes.

Net worth = cash balance + sum of property purchase prices (unmortgaged) + sum of building costs placed - nothing for mortgaged properties (mortgage debt offsets value).

| Config key | Default | Notes |
|------------|---------|-------|
| `net_worth_target` | 10000 | Target net worth in game currency |
| `net_worth_check` | `end_of_turn` | `end_of_turn` -- checked after each turn ends; `real_time` -- checked immediately on any balance or asset change |

`real_time` check triggers a win mid-turn (e.g. on receiving rent). `end_of_turn` avoids mid-turn wins -- cleaner but a player could technically exceed the target and go back below before their turn ends.

---

### Turn Limit

Game ends after a fixed number of complete rounds (one round = every player has taken one turn). At game end, net worth is calculated for all surviving players. Highest net worth wins. Ties broken by cash balance, then by number of properties owned.

| Config key | Default |
|------------|---------|
| `turn_limit` | 30 |

---

### Time Limit

Game ends after a fixed number of real-world minutes. Server tracks elapsed time from first roll. On expiry, the current player completes their turn, then the game ends. Net worth ranking determines winner. Same tiebreak as turn limit.

| Config key | Default |
|------------|---------|
| `time_limit_mins` | 60 |

---

## Net Worth Calculation

Used by `net_worth_target`, `turn_limit`, and `time_limit` winning conditions, and displayed to players throughout the game.

```
net_worth =
  cash_balance
  + sum(purchase_price for each unmortgaged property owned)
  + sum(build_cost × houses for each property)
  + sum(build_cost × 5 for each hotel -- hotel = 5 houses equivalent in value)
  + sum(total_remaining for each loan where player is lender)
  - sum(total_remaining for each loan where player is borrower)
  - 0  (mortgaged properties excluded entirely -- no asset, no debt counted)
```

Mortgaged properties are excluded from net worth entirely (not counted as asset, mortgage debt not subtracted) to avoid negative net worth calculations for players mid-liquidation. Loan receivables and obligations are included at their current outstanding balance.

---

## Bankruptcy

### Trigger

A player is bankrupt when they cannot pay a debt after fully liquidating all assets:

1. Sell all buildings (houses and hotels) at `sell_building_rate` of build cost
2. Mortgage all unmortgaged properties at `mortgage_rate` of purchase price
3. If cash balance still insufficient to pay the debt: bankrupt

### Asset Distribution

| Config key | Default | Options |
|------------|---------|---------|
| `bankruptcy_assets_to` | `creditor` | `creditor`, `bank` |

**`creditor`**: all remaining assets (cash, properties at current mortgage state, held cards including GOOJF and any held rent protection/discount cards) transfer directly to the creditor. Active traps owned by the bankrupt player also transfer to the creditor -- they become the new owner and receive future trigger benefits.

**`bank`**: all properties return to bank unmortgaged and available for future purchase. Buildings are removed. Cash goes to bank. Held cards discarded. Active traps removed from board.

If the creditor is the bank (e.g. unpaid tax, rent on bank-owned property in a house rule variant), `bankruptcy_assets_to` is irrelevant -- assets always return to bank.

### Bankrupt Player Elimination

On bankruptcy:

1. `room_players.is_bankrupt` set to `true`
2. Player removed from turn order
3. `game_state.balances[player_id]` set to `0`
4. All property ownership transferred per `bankruptcy_assets_to`
5. All active police pawns owned by the bankrupt player removed from board
6. All rent modifiers (protections, discounts) held by the bankrupt player discarded
7. Bankrupt player remains in the room as a spectator -- they can watch the rest of the game

### Bankruptcy Negotiation

| Config key | Default | Notes |
|------------|---------|-------|
| `allow_bankruptcy_negotiation` | false | If true, players facing bankruptcy may negotiate before declaring |
| `negotiation_timeout_secs` | 120 | Time window to propose a deal; forced bankruptcy if expired with no proposal accepted |
| `repayment_interest_rate` | 0 | Interest rate applied per turn on outstanding repayment plan balance |

When enabled and a player cannot pay a debt after full liquidation, instead of immediate bankruptcy the player enters a negotiation window. They must choose one of:

1. **Declare bankruptcy** -- skip negotiation, proceed to standard bankruptcy immediately
2. **Propose a trade** -- offer assets to the creditor in exchange for debt relief (full or partial)
3. **Propose a repayment plan** -- offer to pay the outstanding balance in instalments over future turns
4. **Propose a trade + repayment plan** -- offer assets now and a payment schedule for the remainder

All proposals are sent to the creditor. The creditor may accept, counter, or reject within the same negotiation window. If the creditor rejects all proposals and the negotiation window expires, bankruptcy is declared automatically.

Negotiation is only available when the creditor is another player. Debt owed to the bank (tax, fine) cannot be negotiated -- bankruptcy is immediate if assets are insufficient.

#### Trade Proposal

Follows standard trade rules (see [Trading][trading]). The proposed trade must reduce the debt to zero or below for it to satisfy the obligation -- partial trades that leave an unpayable remainder must be combined with a repayment plan for the balance.

On creditor acceptance: trade executes atomically, debt is cleared, player continues in the game.

#### Repayment Plan

Player proposes:

```
total_owed: int          -- full outstanding debt
instalment_amount: int   -- amount paid per turn
instalment_count: int    -- number of turns to pay (total must >= total_owed)
```

If `repayment_interest_rate > 0`, total repayment = `total_owed × (1 + repayment_interest_rate × instalment_count)`. Player sees the total cost before proposing.

On creditor acceptance: plan is written to `game_state.repayment_plans`. At the end of each of the debtor's turns, the instalment is auto-deducted from their balance and credited to the creditor. The debtor may not declare voluntary bankruptcy while a repayment plan is active.

#### Trade + Repayment Plan

Combined: assets transfer immediately on acceptance, repayment plan covers remaining balance. The trade component reduces the outstanding debt before the repayment schedule is calculated.

#### Missed Instalment

At end of debtor's turn, if their balance is insufficient to cover the instalment after any voluntary liquidation:

1. Server auto-liquidates remaining assets (sell buildings, mortgage properties) to cover as much as possible
2. If still insufficient: bankruptcy declared immediately
3. Outstanding repayment balance treated as the bankruptcy debt -- assets distributed per `bankruptcy_assets_to` config

#### Repayment Plan Transfer

If the creditor of a repayment plan is themselves eliminated before the plan completes, outstanding instalments transfer to whoever receives the creditor's assets. If assets go to bank, remaining instalments are paid to the bank.

#### Repayment Plan State

```json
{
  "repayment_plans": [
    {
      "plan_id": "uuid",
      "debtor_id": "player-uuid-a",
      "creditor_id": "player-uuid-b",
      "instalment_amount": 100,
      "instalments_remaining": 4,
      "total_remaining": 400,
      "created_turn": 18
    }
  ]
}
```

---

### Debt to Multiple Creditors

If a player owes debts to multiple players simultaneously (edge case: trap triggers and rent owed in same landing), debts are resolved in the order they were incurred. The player liquidates for the first debt; if bankrupt, remaining assets go to that creditor and subsequent debts are forfeit.

---

[trading]: ./04-trading.md

---

## Game End

On any winning condition being met:

1. Server sets `game_rooms.status = 'finished'`, `game_rooms.finished_at = now()`
2. Final rankings calculated (by net worth for all conditions; sole survivor for last player standing)
3. Final `game_state` write with `phase = 'finished'`
4. Supabase broadcasts to all clients
5. All clients display end screen with rankings
6. Room remains readable for 24 hours then archived (data retained, room removed from active listings)

### Final Rankings

All players ranked at game end, including eliminated players. Eliminated players ranked by net worth at time of bankruptcy -- earlier elimination = lower rank (ties in elimination turn broken by net worth at elimination).

```
1st: surviving player (or highest net worth at time limit/turn limit)
2nd--Nth: surviving players by net worth (time/turn limit games)
Last to Nth: eliminated players by elimination turn (earliest eliminated = last)
```

