# Plan: Refactor game_screen.dart

Items from needtofix.md: 15

---

## Goal

Break `game_screen.dart` into focused, single-responsibility files. No magic strings. DRY. Good OOP.

---

## Step 1 — Audit before touching

- Read `game_screen.dart` in full.
- List every logical region: board rendering, player info, dice, overlays, action buttons, phase logic, etc.
- Map each region to a proposed file name.

## Step 2 — Extract constants / strings

- Create `game_constants.dart` (or use an existing constants file).
- Move all magic strings (phase names, event names, route names, label text) to typed constants or enums.

## Step 3 — Extract widgets

Split each major UI region into its own file under `lib/features/game/widgets/` (or equivalent structure):

| Proposed file | Responsibility |
|---|---|
| `game_board.dart` | Board tile layout and rendering |
| `player_info_panel.dart` | Player tokens, money, status |
| `dice_widget.dart` | Dice display and roll button |
| `action_buttons.dart` | Build / mortgage / trade / end-turn buttons |
| `turn_indicator.dart` | Phase label and active player text |
| `game_overlays.dart` | Coordinator for all overlay widgets |

## Step 4 — Extract logic / controllers

- Move phase transition logic into a `GameController` or `GameNotifier` (if using Riverpod/BLoC/Provider).
- Move overlay show/hide state out of `game_screen.dart` and into the controller.

## Step 5 — Verify

- Confirm no behaviour change: game plays identically before and after refactor.
- Run all existing tests; add widget tests for newly extracted components.
- Confirm no magic strings remain in `game_screen.dart`.

---

## Rules

- No functionality changes during refactor — pure structural move.
- Each extracted file should be independently readable without needing to open `game_screen.dart`.
- Follow existing project naming conventions (check neighbouring files for style).
