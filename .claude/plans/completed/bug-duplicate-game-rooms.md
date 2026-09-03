# Bug: Duplicate Game Rooms in Dashboard List

**Status:** Fixed

## Root Cause

`dashboard_screen.dart` `_loadGames()` queried `room_players` without filtering by `player_id`. The RLS policy `room_players_select_member` allows any room member to read all `room_players` rows for that room, so the join returned N rows per room (one per player). Each row was rendered as a separate `_GameCard`.

## Fix

Added `.eq('player_id', userId)` to the query (consistent with the server-side `listMyGames` handler). Now returns exactly one row per room the current user is in.

**File:** `packages/spoomn_client/lib/src/screens/dashboard_screen.dart` — `_loadGames()`
