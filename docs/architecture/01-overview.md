# Architecture Overview

## What We're Building

Spoomn is a cross-platform Monopoly clone supporting 2--8 players in real-time multiplayer sessions across iOS, Android, and Web. Games can be paused and resumed across sessions. Players can join anonymously or with an account.

---

## Guiding Principles

**Server is authoritative.** All game logic runs on the server. Clients send intents (e.g. "roll dice"), server validates and computes outcomes, then broadcasts new state. Clients never compute game outcomes -- they only render what the server says.

**State lives in the database.** Game state is persisted in Supabase at every step. This enables pause/resume, rejoin after disconnect, and crash recovery at no extra cost.

**Low friction entry.** Anonymous play is first-class. No account required to start or join a game. Account creation is an optional upgrade that unlocks cross-device rejoin and game history.

---

## System Layers

```
┌─────────────────────────────────────────┐
│           Flutter Clients               │
│  (iOS · Android · Web)                  │
│                                         │
│  Flame engine    → board rendering      │
│  Riverpod        → reactive state       │
│  Supabase SDK    → auth + realtime      │
└────────────┬───────────────┬────────────┘
             │ HTTP actions  │ Realtime broadcast
             ▼               ▼
┌────────────────────┐   ┌──────────────────────┐
│   Dart Shelf       │   │   Supabase            │
│   Game Server      │──▶│   (Postgres +         │
│   (Fly.io)         │   │    Realtime)          │
│                    │   │                       │
│  - Validates turns │   │  - game_rooms         │
│  - Runs game logic │   │  - game_state         │
│  - Writes state    │   │  - players            │
│  - No client trust │   │  - game_log           │
└────────────────────┘   └──────────────────────┘
```

---

## Request / Broadcast Flow

```
1. Active player taps "Roll Dice"
2. Flutter client POSTs { action: "roll_dice", player_id } to Dart server
3. Server validates: is it this player's turn? Is game active?
4. Server rolls dice, computes movement, applies square effects
5. Server writes updated game_state to Supabase
6. Supabase Realtime broadcasts row change to all subscribed clients
7. All clients receive new state and re-render board
```

No client ever sees a game outcome before the server has committed it.

---

## Key Architectural Decisions

### Hosting: Fly.io

Fly.io hosts the Dart Shelf game server. Chosen over alternatives for:

- Native WebSocket / persistent connection support
- Low cost: ~$5--10/mo for a 1 CPU, 512MB--1GB instance
- Simple deploy from Dockerfile
- Horizontal scaling available when needed

Google Cloud Run was ruled out -- cold starts break persistent WebSocket connections. Railway is viable but more expensive under load.

### Database and Realtime: Supabase

Supabase provides Postgres for game state persistence and a Realtime channel for broadcasting state changes to all connected clients. Chosen because:

- Realtime subscriptions replace the need for a custom WebSocket broadcast layer
- Postgres gives full relational integrity for game state
- Free tier covers development and early production; Pro tier ($25/mo) unlocks more connections and bandwidth at scale

### Client Framework: Flutter + Flame

Flutter targets iOS, Android, and Web from a single Dart codebase. Flame is a 2D game engine built on Flutter that provides:

- Game loop management
- Sprite and animation handling
- Touch/click input routing
- Camera and viewport control

Flame handles rendering only. All game logic is server-side.

### State Management: Riverpod

Riverpod manages client-side reactive state. Game state arrives via Supabase Realtime stream; Riverpod providers expose it to the Flame components and UI widgets. Chosen over Bloc for:

- Less boilerplate for stream-based state
- Better composition for multiple independent state slices (board, bank, players, trade offers)
- Simpler async handling

### Auth: Anonymous + Optional Account

Supabase Auth supports anonymous sessions natively. Every player gets a Supabase session on first launch -- no sign-up required. This session is persisted in device secure storage.

Optional account creation (email magic link or Google OAuth) upgrades the anonymous session to a named account. This enables:

- Cross-device rejoin (not limited to the original device)
- Game history
- Future features (friends list, stats)

Anonymous users can still rejoin on the same device -- their Supabase anon session is used to re-associate them with their player record.

---

## Pause and Resume

Games can be paused by any player. On pause:

- Server sets `game_rooms.status = 'paused'`
- Supabase broadcasts the status change
- All clients display a paused screen and disconnect gracefully

On resume:

- Any player opens the game (via dashboard or rejoin link)
- Server sets `game_rooms.status = 'active'`
- All clients re-subscribe to the Realtime channel
- Full game state is loaded from Supabase -- no state is lost

Paused games appear in each player's "In Progress" dashboard (see [Auth and Rooms][auth-and-rooms]).

---

## Rejoin Links

Every room has a unique `room_code` (short alphanumeric, e.g. `K7X2MQ`). Rejoin links take the form:

- **Web**: `https://spoomn.app/join/K7X2MQ`
- **Mobile deep link**: `spoomn://join/K7X2MQ`

Following a link opens the game directly. The server validates that the player (by session or account) is a member of that room before allowing entry. Anonymous players can only rejoin on the same device unless they have created an account.

---

## Multiplayer Constraints

| Constraint | Value |
|------------|-------|
| Players per room | 2--8 |
| Session type | Real-time or async (configurable per room) |
| Async turns | Supported -- players notified on their turn, respond at own pace |
| Rejoin after disconnect | Supported |
| Pause and resume | Supported (no expiry) |

---

[auth-and-rooms]: ./07-auth-and-rooms.md
