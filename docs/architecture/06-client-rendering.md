# Client Rendering

The Flutter client is split into two rendering layers: standard Flutter widgets for UI chrome (lobby, menus, trade panels, notifications) and a Flame game component for the board. Both layers are driven by Riverpod state derived from Supabase Realtime streams.

---

## Layer Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Flutter Widget Tree                 │
│                                                      │
│  ┌──────────────┐  ┌────────────────────────────┐  │
│  │  Game Chrome │  │     GameWidget (Flame)      │  │
│  │              │  │                             │  │
│  │  - Top bar   │  │  BoardComponent             │  │
│  │  - Player    │  │  TokenComponent (×N)        │  │
│  │    panels    │  │  PropertyComponent (×40)    │  │
│  │  - Event     │  │  DiceComponent              │  │
│  │    feed      │  │  PolicePawnComponent (×N)   │  │
│  │  - Trade UI  │  │  TrapComponent (×N)         │  │
│  │  - Card      │  │  CameraComponent            │  │
│  │    drawer    │  │                             │  │
│  └──────┬───────┘  └────────────┬───────────────┘  │
│         │                       │                   │
│         └──────────┬────────────┘                   │
│                    │                                 │
│            Riverpod Providers                        │
│                    │                                 │
│         ┌──────────▼──────────┐                    │
│         │  Supabase Realtime  │                    │
│         │  Streams            │                    │
│         └─────────────────────┘                    │
└─────────────────────────────────────────────────────┘
```

Flame's `GameWidget` is embedded as a Flutter widget. It fills the board area. All other UI (player panels, event feed, trade modals) sits above it in the Flutter widget tree using standard widgets.

---

## Riverpod Providers

All game state arrives via Supabase streams. Providers expose typed models to both Flame components and Flutter widgets.

```dart
// Core providers
@riverpod
Stream<GameRoom> gameRoom(GameRoomRef ref, String roomId);

@riverpod
Stream<GameState> gameState(GameStateRef ref, String roomId);

@riverpod
Stream<List<RoomPlayer>> roomPlayers(RoomPlayersRef ref, String roomId);

@riverpod
Stream<List<PendingTrade>> pendingTrades(PendingTradesRef ref, String roomId);

@riverpod
Stream<List<GameLogEntry>> gameLog(GameLogRef ref, String roomId);

@riverpod
Stream<List<ActiveTrap>> activeTraps(ActiveTrapsRef ref, String roomId);

// Derived providers
@riverpod
RoomPlayer? myPlayer(MyPlayerRef ref, String roomId) {
  final players = ref.watch(roomPlayersProvider(roomId)).valueOrNull ?? [];
  final myId = ref.watch(authProvider).userId;
  return players.firstWhereOrNull((p) => p.playerId == myId);
}

@riverpod
bool isMyTurn(IsMyTurnRef ref, String roomId) {
  final room = ref.watch(gameRoomProvider(roomId)).valueOrNull;
  final myId = ref.watch(authProvider).userId;
  return room?.currentPlayerId == myId;
}

@riverpod
GamePhase currentPhase(CurrentPhaseRef ref, String roomId) {
  return ref.watch(gameStateProvider(roomId)).valueOrNull?.phase ?? GamePhase.roll;
}
```

---

## Flame Game Structure

```dart
class SpoomnGame extends FlameGame with HasGameRef {
  final String roomId;
  final WidgetRef ref;  // bridge to Riverpod

  late BoardComponent board;
  late DiceComponent dice;
  late Map<String, TokenComponent> tokens;
  late Map<String, PolicePawnComponent> policePawns;
  late List<TrapComponent> traps;

  @override
  Future<void> onLoad() async {
    board = BoardComponent();
    await add(board);
    // Components added as game state arrives
  }
}
```

### Riverpod → Flame Bridge

Flame's game loop is isolated from Flutter's widget rebuild cycle. State changes are pushed into Flame via a notifier pattern: a Riverpod listener in the parent widget calls methods on the Flame game instance when state updates arrive.

```dart
class GameScreen extends ConsumerStatefulWidget { ... }

class _GameScreenState extends ConsumerState<GameScreen> {
  late SpoomnGame _game;

  @override
  void initState() {
    super.initState();
    _game = SpoomnGame(roomId: widget.roomId, ref: ref);
  }

  @override
  Widget build(BuildContext context) {
    // Listen to state changes and push into Flame
    ref.listen(gameStateProvider(widget.roomId), (_, next) {
      next.whenData((state) => _game.onStateUpdate(state));
    });

    ref.listen(activeTrapsProvider(widget.roomId), (_, next) {
      next.whenData((traps) => _game.onTrapsUpdate(traps));
    });

    return Stack(
      children: [
        GameWidget(game: _game),
        GameChrome(roomId: widget.roomId),
      ],
    );
  }
}
```

---

## Board Component

The board is a fixed 40-square grid rendered on a square canvas. Squares are positioned mathematically -- no sprite atlas required, though one can be swapped in later.

```dart
class BoardComponent extends PositionComponent {
  static const int squareCount = 40;

  // Square positions precomputed at load time
  late final List<Rect> squareRects;

  @override
  Future<void> onLoad() async {
    squareRects = BoardLayout.computeSquareRects(size);
    // Add PropertyComponent for each square
    for (int i = 0; i < squareCount; i++) {
      await add(PropertyComponent(squareIndex: i, rect: squareRects[i]));
    }
  }
}
```

### BoardLayout

Computes square positions for a standard Monopoly board:
- 9 squares on each side (corners shared)
- Corner squares larger than side squares
- All positions relative to board size (responsive to screen)

```dart
class BoardLayout {
  static List<Rect> computeSquareRects(Vector2 boardSize) {
    // Bottom row: squares 00-10 (left to right)
    // Left column: squares 10-20 (bottom to top)
    // Top row: squares 20-30 (right to left)
    // Right column: squares 30-40/00 (top to bottom)
  }
}
```

---

## Token Component

One `TokenComponent` per player. Animated movement between squares.

```dart
class TokenComponent extends PositionComponent with HasGameRef {
  final String playerId;
  final Color colour;
  int _currentSquare = 0;

  void moveTo(int squareIndex, {bool animated = true}) {
    final target = gameRef.board.squareRects[squareIndex].center.toVector2();
    if (animated) {
      add(MoveEffect.to(target, EffectController(duration: 0.4, curve: Curves.easeInOut)));
    } else {
      position = target;
    }
    _currentSquare = squareIndex;
  }
}
```

When `game_state.board_positions` changes, each token's `moveTo` is called. If a player moves multiple squares (e.g. passing Go), the token animates through each intermediate square sequentially for visual clarity.

### Token Stacking

Multiple tokens on the same square are fanned slightly so all are visible. Position offset calculated from the list of players currently on that square.

---

## Police Pawn Component

Identical structure to `TokenComponent` but uses a distinct visual (badge/pawn icon). One component per entry in `active_police_pawns`.

Invisible trap owners can see their own pawn position. Other players see pawn movement but only for visible traps -- invisible trap pawns are not rendered for non-owners (RLS ensures the position is never sent to non-owners).

Wait -- police pawns are not traps. Police pawns are always visible to all players regardless of `jailbreak` config -- all players can see where the police pawn is. The pawn's position is stored in `game_state.active_police_pawns` which is broadcast to all players without redaction.

---

## Trap Component

One `TrapComponent` per entry in `active_traps` (filtered by RLS -- invisible traps owned by others not received).

```dart
class TrapComponent extends PositionComponent {
  final ActiveTrap trap;

  @override
  void render(Canvas canvas) {
    // Visible trap: render trap icon + owner colour ring
    // Own invisible trap: render with dashed border to indicate hidden state
    final isOwnInvisible = !trap.visible && trap.ownerId == gameRef.myPlayerId;
    // Non-own invisible traps: never received from server, never rendered
  }
}
```

---

## Dice Component

Displays dice values. Animated roll sequence plays before settling on the result.

```dart
class DiceComponent extends PositionComponent {
  List<int> _values = [1, 1];

  void showRoll(List<int> values, {VoidCallback? onComplete}) {
    // Play random dice cycling animation for 0.8s
    // Settle on final values
    // Call onComplete when animation done
  }
}
```

Dice values arrive from `game_state.dice_roll`. The component animates them; it does not generate them.

---

## Camera and Zoom

The board is rendered at full size. On small screens (phones), the camera zooms in to the active area of the board.

```dart
class CameraComponent extends Component {
  void focusOnSquare(int squareIndex) {
    final rect = gameRef.board.squareRects[squareIndex];
    // Smooth pan and zoom to keep active square in view
    // Zoom level based on screen size: phones zoom more than tablets
  }
}
```

Camera follows the active player's token on their turn. Players can pan/zoom freely during other players' turns. Double-tap resets to full board view.

---

## Game Chrome (Flutter Widgets)

Overlaid above `GameWidget` using a `Stack`. All standard Flutter widgets -- no Flame.

### Player Panels

Strip of player cards showing: name, balance, token colour, property count, connection status. Active player highlighted. Bankrupt players dimmed.

### Event Feed

Scrollable list of `game_log` entries. New entries slide in from bottom. Feed auto-scrolls to latest. Tap any entry to see detail.

### Action Bar

Context-sensitive controls for the active player:

| Phase | Controls shown |
|-------|---------------|
| `roll` | Roll Dice button (+ Jailbreak / Pay Fine / Use Card if in jail) |
| `action` (purchase) | Buy / Decline buttons + property detail |
| `action` (rent) | Auto-resolved if `auto_claim_rent`; else Claim Rent for owner |
| `trade` | End Turn button + Trade / Build / Mortgage shortcuts |
| `auction` | Bid input + Pass button |
| `bankruptcy_negotiation` | Propose Trade / Propose Repayment / Declare Bankruptcy |

Non-active players see a "Waiting for {name}..." state in the action bar. They can still initiate trades, build, and mortgage during other players' turns (when `build_own_turn_only` is false).

### Trade Panel

Full-screen modal. Two-column layout: what you offer / what you request. Asset picker lists owned properties, money slider, GOOJF cards, rent immunity cards (if `trade_futures` enabled). Multi-party trade shows N columns for N participants.

### Card Drawer

Slides up when a card is drawn. Shows card text and effect. Auto-dismisses after effect is applied and acknowledged.

---

## Animations

| Event | Animation |
|-------|-----------|
| Token move | Smooth path along board squares, 0.4s per square |
| Go To Jail | Token jumps directly to jail square, bounce on landing |
| Dice roll | 0.8s cycling random values, settle on result |
| Property purchase | Colour fill on board square, brief pulse |
| House placed | House sprite appears on square with scale-in |
| Hotel placed | Houses replaced by hotel sprite |
| Trap placed | Trap icon appears with shake effect |
| Trap triggered | Flash effect on square, outcome text floats up |
| Police pawn move | Same smooth path as token, 0.3s per square |
| Police catch | Red flash on caught player's token, cut to jail |
| Bankruptcy | Token fades out, player panel dims |
| Win | Confetti overlay, winner panel expands |

All animations are additive -- if a state update arrives while an animation is in progress, the animation completes before the next state is applied. A short debounce (100ms) prevents animation queuing from growing unbounded under rapid state updates.

---

## Responsive Layout

| Screen size | Board layout | Player panels |
|-------------|-------------|---------------|
| Phone portrait | Board fills width, panels below | Horizontal strip below board |
| Phone landscape | Board fills height, panels right | Vertical strip right of board |
| Tablet portrait | Board fills width with margins, panels beside | Vertical strip right of board |
| Tablet landscape | Board + panels side by side | Full sidebar |
| Web desktop | Fixed max board size, full sidebar | Full sidebar with extra detail |

Camera zoom level adjusted per form factor so full board is visible without scrolling on tablet and desktop. Phones default to zoomed-in view with pan to explore.
