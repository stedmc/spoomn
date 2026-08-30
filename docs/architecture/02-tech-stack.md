# Tech Stack

## Client

### Flutter

Cross-platform UI framework. Single Dart codebase targets iOS, Android, and Web. All three platforms share identical game logic, state management, and rendering -- no platform-specific forks.

- **Minimum targets**: iOS 13, Android 6.0 (API 23), modern evergreen browsers (Chrome, Firefox, Safari, Edge)
- **Channel**: stable
- **Version**: latest stable at project init; pin in `.fvmrc` via [Flutter Version Manager][fvm]

### Flame

2D game engine built on Flutter. Handles the game loop, sprite rendering, animations, and input routing for the board. Flame runs inside a `FlameGame` widget embedded in the Flutter widget tree -- surrounding UI (lobby, trade panels, menus) remains standard Flutter widgets.

- **Package**: `flame` (pub.dev)
- **Version**: `^1.x` (latest stable)
- **Scope**: board rendering, token animation, dice animation, card reveal effects. No game logic.

### Riverpod

Reactive state management. Game state arrives from Supabase Realtime as a stream; Riverpod `StreamProvider`s expose it to both Flame components (via notifiers) and Flutter widgets (via `ref.watch`).

- **Package**: `flutter_riverpod` + `riverpod_annotation` + `riverpod_generator`
- **Code generation**: `build_runner` + `riverpod_generator` for `@riverpod` annotations
- **Why not Bloc**: less boilerplate for stream-driven state; better provider composition across board, bank, players, and trade slices

### Supabase Flutter SDK

Handles auth, database queries, and Realtime subscriptions. Anonymous sessions are persisted automatically in device secure storage (uses `flutter_secure_storage` under the hood on mobile; `localStorage` on web).

- **Package**: `supabase_flutter`
- **Auth methods**: anonymous session (default), email magic link, Google OAuth
- **Realtime**: subscribes to `game_state` and `game_rooms` table changes for the active room

### Networking

All action requests (roll dice, buy property, trade) are HTTP POST to the Dart Shelf server. Supabase Realtime handles all inbound state updates. No direct WebSocket connection to the game server from clients -- Supabase acts as the broadcast layer.

### Deep Linking

- **Mobile**: `app_links` package handles `spoomn://join/{room_code}` deep links on iOS and Android
- **Web**: standard URL routing via `go_router`; `/join/{room_code}` resolves directly in browser

### Navigation

`go_router` for declarative routing across: splash → lobby → room → game → pause screen.

---

## Server

### Dart Shelf

Lightweight HTTP server framework in Dart. Hosts all game logic. Exposes a REST-ish API -- clients POST actions, server validates and writes to Supabase, Supabase Realtime broadcasts to clients.

- **Package**: `shelf` + `shelf_router`
- **Why Dart**: same language as client -- game rule logic (e.g. rent calculation, card effects) lives in a shared `spoomn_core` Dart package imported by both server and client (client uses it for display logic only -- never for computing outcomes)
- **No WebSockets from server**: server writes to Supabase; Supabase Realtime delivers to clients. Server does not maintain client connections.

### Shared Core Package

`packages/spoomn_core` -- pure Dart package (no Flutter dependency) containing:

- Game rule constants (board squares, card decks, rent tables, starting money)
- Data transfer objects (DTOs) shared between client and server
- No business logic that produces outcomes -- constants and types only

### Hosting: Fly.io

Containerised deployment via Dockerfile. One persistent instance handles all active games. Scale to multiple instances when concurrent game count requires it (Fly.io makes this straightforward).

- **Instance size**: `shared-cpu-1x` with 512MB RAM to start (~$5--10/mo)
- **Region**: closest to majority user base (e.g. `lax` for US West, `lhr` for Europe)
- **Deploy**: `fly deploy` from CI on merge to `main`
- **Health check**: `GET /health` endpoint returns 200

---

## Backend: Supabase

### Postgres

Primary data store. All game state, player records, room metadata, and game logs live here. Row-level security (RLS) policies enforce that players can only read rooms they belong to and cannot write game state directly (all writes go through the server with the service role key).

### Supabase Realtime

Broadcasts Postgres row changes to subscribed clients. Clients subscribe to their room's `game_state` row. On any server write, all clients receive the updated state within ~100ms.

- **Channels used**: one channel per room, filtered by `room_id`
- **Events listened**: `UPDATE` on `game_state`, `UPDATE` on `game_rooms` (for status changes like pause)

### Supabase Auth

Manages anonymous and named user sessions. Anonymous sessions are created silently on first launch. Users can upgrade to a named account at any time -- Supabase links the anonymous session to the new account, preserving game history.

- **Providers enabled**: anonymous, email (magic link), Google OAuth
- **JWT**: passed as `Authorization: Bearer` header on all requests to the Dart Shelf server for identity verification

### Row-Level Security

All tables have RLS enabled. Key policies:

| Table | Policy |
|-------|--------|
| `game_rooms` | Players can read rooms they belong to; no direct writes |
| `game_state` | Players can read state for their room; writes via server service key only |
| `players` | Players can read all players in their room; write own row only (display name) |
| `game_log` | Read-only for players |

---

## Tooling

### Version Management

| Tool | Purpose |
|------|---------|
| [FVM][fvm] | Pin Flutter version per project via `.fvmrc` |
| `dart pub` | Dart/Flutter package management |
| `melos` | Monorepo script orchestration across `spoomn_client`, `spoomn_server`, `spoomn_core` |

### Code Generation

| Tool | Purpose |
|------|---------|
| `build_runner` | Drives all code gen |
| `riverpod_generator` | Generates Riverpod providers from `@riverpod` annotations |
| `freezed` | Immutable data classes + union types for game state DTOs |
| `json_serializable` | JSON encode/decode for DTOs |

Run all generators:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### CI/CD

GitHub Actions. On PR: lint, format check, unit tests, integration tests. On merge to `main`: run tests, build, deploy server to Fly.io.

### Linting

`flutter_lints` (client) + `dart_code_metrics` for complexity checks. All warnings treated as errors in CI.

---

## Package Summary

```yaml
# client (pubspec.yaml)
dependencies:
  flame: ^1.x
  flutter_riverpod: ^2.x
  riverpod_annotation: ^2.x
  supabase_flutter: ^2.x
  go_router: ^14.x
  app_links: ^6.x
  freezed_annotation: ^2.x
  json_annotation: ^4.x

dev_dependencies:
  build_runner: ^2.x
  riverpod_generator: ^2.x
  freezed: ^2.x
  json_serializable: ^6.x
  flutter_lints: ^4.x

# server (pubspec.yaml)
dependencies:
  shelf: ^1.x
  shelf_router: ^1.x
  supabase: ^2.x          # Dart-only Supabase client (no Flutter)
  spoomn_core:
    path: ../packages/spoomn_core

# spoomn_core (pubspec.yaml)
dependencies:
  freezed_annotation: ^2.x
  json_annotation: ^4.x
```

---

[fvm]: https://fvm.app
