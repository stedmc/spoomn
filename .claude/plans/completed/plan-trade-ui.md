# Plan: Trade UI

## Context

Server fully implemented (`trade_handler.dart`): propose, accept, reject, cancel, counter.
`pending_trades` table exists with `id, room_id, proposer_id, participants[], legs[], status,
accepted_by[], created_at, resolved_at`.

Client has zero trade UI. Need: button, player selection, asset assignment with arrows,
offer submission, and live response view visible to all players.

Trade config keys to respect:
- `multi_party_trades` (default false) -- single vs multi select in player picker
- `trade_any_turn` (default false) -- show button outside trade phase
- `trade_futures` (default false) -- show rent immunity section
- `trade_mortgaged_properties` (default true) -- include mortgaged in asset list

---

## Step 1 -- Add trade action constants (`game_constants.dart`)

```dart
static const String proposeTrade = 'propose_trade';
static const String acceptTrade  = 'accept_trade';
static const String rejectTrade  = 'reject_trade';
static const String cancelTrade  = 'cancel_trade';
static const String counterTrade = 'counter_trade';
```

---

## Step 2 -- Add `pendingTradesProvider` (`providers.dart`)

Stream `pending_trades` where `room_id` matches and status is `pending` or `countered`.
Eager REST fetch pattern (same as `roomConfigProvider`).

```dart
final pendingTradesProvider = StreamProvider.family<List<Map<String, dynamic>>, String>(
  (ref, roomId) async* {
    try {
      final rows = await Supabase.instance.client
          .from('pending_trades')
          .select()
          .eq('room_id', roomId)
          .inFilter('status', ['pending', 'countered'])
          .order('created_at', ascending: false);
      yield (rows as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    yield* Supabase.instance.client
        .from('pending_trades')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .map((rows) => rows
            .where((r) => ['pending', 'countered'].contains(r['status'] as String?))
            .cast<Map<String, dynamic>>()
            .toList());
  },
);
```

---

## Step 3 -- Trade button in `action_bar.dart`

Add to the trade phase `Row`:

```dart
IconButton.outlined(
  onPressed: () => _showTradeOverlay(context, ref),
  icon: const Icon(Icons.swap_horiz),
  tooltip: 'Trade',
),
```

Also add to the roll phase row when `config['trade_any_turn'] == true`.

`_showTradeOverlay` shows `TradeOverlay` in initiation mode (phase 1 -- player selection).
Pass `debugActingAs` through as effective player id.

---

## Step 4 -- Create `trade_overlay.dart`

New file: `packages/spoomn_client/lib/src/widgets/game/trade_overlay.dart`

### Internal state machine

```
_TradePhase { playerSelection, assetAssignment, awaitingResponse }
```

The widget is used in two modes:
- **Initiation mode** (opened by Trade button): starts at `playerSelection`
- **Response mode** (shown by game_screen when pending trade detected): starts at
  `awaitingResponse`

### Phase 1 -- Player Selection

Full-screen overlay (dark scrim + centered card, same pattern as CardDrawOverlay).

Header: "Trade with..."

Player table -- for each other player one row, no column headers:

```
[pawn circle] | [name] | [prop chips] | [station chips] | [utility chips] | [GOOJF×N]
```

- Pawn circle: 14px, filled with player token colour
- Property chips: small rounded rectangles, coloured by property group colour, show street
  abbreviation. If mortgaged and `trade_mortgaged_properties` is false: greyed out, not shown.
- Station chips: train icon + abbreviated name
- Utility chips: bolt/droplet icon + abbreviated name
- GOOJF: badge showing count (hidden if 0)

Tap row: selects player. If `multi_party_trades` false: single select (tap second deselects
first). If true: multi select with checkboxes.

Buttons at bottom:
- "Continue" (filled, disabled until >=1 selected) -> advance to asset assignment
- "Cancel" (outlined) -> close overlay

### Phase 2 -- Asset Assignment

Non-selected rows hidden with animated removal.

Layout: `Column` of player sections. Each section:

```
[Player name + token colour header]
[Scrollable Row of asset chips]
[Money field: "Send £___ →"]
```

Asset chips are the same small chips from phase 1 but now interactive.

**Click-to-route flow**:
1. Tap unassigned chip -> chip highlighted (pulsing border), overlay enters "routing mode"
2. Tap a different player's name header -> assigns chip to that player, arrow appears
3. Tap same chip again -> cancel routing mode (no assignment)
4. Tap already-assigned chip -> clear its assignment (remove arrow)

**Drag-to-route flow**:
- `GestureDetector` with `onPanStart`/`onPanUpdate`/`onPanEnd` on each chip
- `onPanStart`: record chip's global position, begin drawing a "ghost arrow" that follows
  the pointer
- `onPanEnd`: hit-test against player header areas, if hit -> assign, else -> cancel

**Arrow rendering**:
- `Stack` wrapping the entire overlay content
- `CustomPaint` on top (pointer-events passthrough via `IgnorePointer`)
- Painter receives list of `_TradeArrow(Offset source, Offset dest, Color color)` where
  color is the destination player's token colour
- Each arrow drawn as a bezier curve with arrowhead: two lines at 30deg from the endpoint
- Positions obtained via `GlobalKey.currentContext!.findRenderObject()!` cast to
  `RenderBox`, then `.localToGlobal(Offset.zero) + size / 2`
- Each asset chip and each player header has a `GlobalKey`

**Clearing arrows**:
- Tapping an assigned chip -> clear assignment -> arrow removed
- Dragging same chip -> replaces existing assignment (old arrow removed, new drawn)

**Money fields**:
One `TextField` (numeric) per player below their asset row:
```
"Send £___ to [other player name]"
```
Two money fields for a 2-party trade (what A sends to B, what B sends to A).

**Rent immunity** (only if `config['trade_futures'] == true`):
Appears below money fields. For each property chip that has been assigned:
- Toggle: "Include rent immunity"
- If toggled: stepper for number of landings (1-10)

**Offer button**:
- Validates: at least one asset or money amount is non-zero in any direction
- Builds `legs` array:
  ```json
  [
    { "from": "playerA", "to": "playerB", "properties": [i,...], "money": 0, "jail_cards": 0 },
    { "from": "playerB", "to": "playerA", "properties": [j,...], "money": 100, "jail_cards": 1 }
  ]
  ```
- Calls `game_service.submitAction(roomId, 'propose_trade', { participants, legs })`
- On success: overlay transitions to awaitingResponse phase
- On error: shows SnackBar with server message

### Phase 3 -- Awaiting Response

Shows a read-only summary of the trade:

```
[Player A] offers:
  • Park Lane
  • £100
to [Player B] in exchange for:
  • Bow Street
```

One section per leg.

For the **proposer**:
- "Cancel Trade" button -> `cancel_trade` action
- Spinner / "Waiting for others to respond..."
- Shows which participants have already accepted (green tick) vs pending (clock icon)

For **recipients** (participants who haven't accepted/rejected yet):
- "Accept" button (green) -> `accept_trade`
- "Refuse" button (red) -> `reject_trade`
- "Counter" button (outlined) -> opens Phase 2 with this player as new proposer
  - Counter payload: `{ trade_id, counter: { participants, legs } }`

For **non-participant spectators**:
- Read-only banner at top of screen: "Trade in progress..." with a brief summary
- No interaction buttons

**Counter flow**:
- Pre-populate Phase 2 with the existing trade's legs as starting state (inverted: what
  the counter-proposer currently receives becomes what they offer, and vice versa as a
  starting suggestion they can edit)
- Submit as `counter_trade` action: `{ trade_id, counter: { participants, legs } }`

---

## Step 5 -- Wire into `game_screen.dart`

Add state:
```dart
Map<String, dynamic>? _activeTrade;
```

Add listener:
```dart
ref.listen(pendingTradesProvider(widget.roomId), (_, next) {
  next.whenData((trades) {
    setState(() => _activeTrade = trades.isNotEmpty ? trades.first : null);
  });
});
```

In the `Stack`:
```dart
if (_activeTrade != null)
  TradeOverlay(
    roomId: widget.roomId,
    trade: _activeTrade!,
    myId: myId,
    effectivePlayerId: /* debugActingAs if set */,
    onAct: (action, payload) => _act(context, ref, action, payload),
    onClose: () => setState(() => _activeTrade = null),
  ),
```

The `onClose` callback: only used when there is NO active pending trade (i.e., the overlay
was opened in initiation mode before a trade was submitted, and the user cancels out of
player selection).

---

## Files Created / Changed

| File | Action |
|------|--------|
| `widgets/game/trade_overlay.dart` | New, ~400 lines |
| `widgets/game/game_constants.dart` | +5 trade action constants |
| `providers/providers.dart` | +pendingTradesProvider (~18 lines) |
| `widgets/game/action_bar.dart` | +Trade button in trade phase row (~8 lines) |
| `screens/game_screen.dart` | +listener + Stack entry (~15 lines) |

---

## Not in Scope

- Trade houses/hotels: blocked by server config `trade_buildings` (default false per
  07-config-reference.md). Do not add to UI.
- Trade timeout countdown: display only -- no server changes needed, just read
  `trade_timeout_secs` from config and show a countdown if set.
- Animation for trade completion (assets flying between players): post-MVP.

---

## Verification

1. Player A clicks Trade button -> phase 1 opens, shows all other players with their assets
2. Select Player B -> Continue -> phase 2 opens
3. Tap a property chip -> routing mode
4. Tap Player B's header -> arrow appears from chip to B
5. All players see the overlay (read-only for C, D)
6. Click Offer -> pending trade created, phase 3 shown
7. Player B sees Accept / Refuse / Counter
8. Accept -> trade completes, overlay closes for all, assets transfer reflected in game state
9. Counter -> phase 2 reopens for B, B submits counter, A sees new offer
10. Cancel -> trade cancelled, overlay closes for all
