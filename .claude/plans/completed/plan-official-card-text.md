# Plan: Official Card Text

## Source

Standard UK Monopoly (London edition, Hasbro/Winning Moves). Cross-referenced against
multiple sources. 16 Chance cards, 16 Community Chest cards.

## Problems with current `cards.dart`

| ID | Problem |
|----|---------|
| All cards | Labels are terse slugs -- no amounts, no effect text visible in overlay |
| `cc_12` | School fees amount wrong: currently £50, standard UK is £150 |
| `cc_15` | Wrong card entirely: "You inherit £100" (collect 100) -- should be "Second prize in a beauty contest" (collect £10) |
| `ch_02` | Wrong destination: "Advance to Pall Mall" sq 11 -- should be "Advance to Mayfair" sq 39 |

## Fix

One file only: `packages/spoomn_core/lib/src/constants/cards.dart`

Replace all `label` strings with full official wording. Fix three broken cards (label + effect
where applicable).

---

## Complete corrected card data

### Community Chest (16 cards)

```dart
CardDefinition(id: 'cc_00', label: 'Advance to Go. Collect £200.',
    effect: {'type': 'move_to', 'square': 0}),
CardDefinition(id: 'cc_01', label: 'Bank error in your favour. Collect £200.',
    effect: {'type': 'collect', 'amount': 200}),
CardDefinition(id: 'cc_02', label: "Doctor's fees. Pay £50.",
    effect: {'type': 'pay', 'amount': 50}),
CardDefinition(id: 'cc_03', label: 'From sale of stock you get £50.',
    effect: {'type': 'collect', 'amount': 50}),
CardDefinition(id: 'cc_04', label: 'Get Out of Jail Free. Keep this card until needed or sold.',
    effect: {'type': 'keep_goojf'}, keep: true),
CardDefinition(id: 'cc_05', label: 'Go to Jail. Go directly to Jail. Do not pass Go. Do not collect £200.',
    effect: {'type': 'go_to_jail'}),
CardDefinition(id: 'cc_06', label: 'Grand Opera Night. Collect £50 from every player.',
    effect: {'type': 'collect_from_each', 'amount': 50}),
CardDefinition(id: 'cc_07', label: 'Holiday Fund matures. Receive £100.',
    effect: {'type': 'collect', 'amount': 100}),
CardDefinition(id: 'cc_08', label: 'Income tax refund. Collect £20.',
    effect: {'type': 'collect', 'amount': 20}),
CardDefinition(id: 'cc_09', label: 'It is your birthday! Collect £10 from every player.',
    effect: {'type': 'collect_from_each', 'amount': 10}),
CardDefinition(id: 'cc_10', label: 'Life insurance matures. Collect £100.',
    effect: {'type': 'collect', 'amount': 100}),
CardDefinition(id: 'cc_11', label: 'Pay hospital fees of £100.',
    effect: {'type': 'pay', 'amount': 100}),
CardDefinition(id: 'cc_12', label: 'Pay school fees of £150.',           // was £50
    effect: {'type': 'pay', 'amount': 150}),
CardDefinition(id: 'cc_13', label: 'Receive consultancy fee. Collect £25.',
    effect: {'type': 'collect', 'amount': 25}),
CardDefinition(id: 'cc_14', label: 'You are assessed for street repairs. Pay £40 per house and £115 per hotel.',
    effect: {'type': 'pay_per_building', 'house_amount': 40, 'hotel_amount': 115}),
CardDefinition(id: 'cc_15', label: 'You have won second prize in a beauty contest. Collect £10.',  // was "You inherit £100" collect 100
    effect: {'type': 'collect', 'amount': 10}),
```

### Chance (16 cards)

```dart
CardDefinition(id: 'ch_00', label: 'Advance to Go. Collect £200.',
    effect: {'type': 'move_to', 'square': 0}),
CardDefinition(id: 'ch_01', label: 'Advance to Trafalgar Square. If you pass Go, collect £200.',
    effect: {'type': 'move_to', 'square': 24}),
CardDefinition(id: 'ch_02', label: 'Advance to Mayfair.',                // was Pall Mall sq 11
    effect: {'type': 'move_to', 'square': 39}),
CardDefinition(id: 'ch_03', label: 'Advance to the nearest Station. If owned, pay double the normal rent.',
    effect: {'type': 'move_to_nearest', 'square_type': 'station', 'rent_multiplier': 2.0}),
CardDefinition(id: 'ch_04', label: 'Advance to the nearest Station. If owned, pay double the normal rent.',
    effect: {'type': 'move_to_nearest', 'square_type': 'station', 'rent_multiplier': 2.0}),
CardDefinition(id: 'ch_05', label: 'Advance to the nearest Utility. If owned, throw dice and pay owner 10 times the amount thrown.',
    effect: {'type': 'move_to_nearest', 'square_type': 'utility', 'rent_multiplier': 10.0}),
CardDefinition(id: 'ch_06', label: 'Bank pays you a dividend of £50.',
    effect: {'type': 'collect', 'amount': 50}),
CardDefinition(id: 'ch_07', label: 'Get Out of Jail Free. Keep this card until needed or sold.',
    effect: {'type': 'keep_goojf'}, keep: true),
CardDefinition(id: 'ch_08', label: 'Go back three spaces.',
    effect: {'type': 'move_relative', 'squares': -3}),
CardDefinition(id: 'ch_09', label: 'Go to Jail. Go directly to Jail. Do not pass Go. Do not collect £200.',
    effect: {'type': 'go_to_jail'}),
CardDefinition(id: 'ch_10', label: 'Make general repairs on all your property. Pay £25 per house and £100 per hotel.',
    effect: {'type': 'pay_per_building', 'house_amount': 25, 'hotel_amount': 100}),
CardDefinition(id: 'ch_11', label: 'Pay poor tax of £15.',
    effect: {'type': 'pay', 'amount': 15}),
CardDefinition(id: 'ch_12', label: "Take a trip to King's Cross Station. If you pass Go, collect £200.",
    effect: {'type': 'move_to', 'square': 5}),
CardDefinition(id: 'ch_13', label: 'Take a walk on the Old Kent Road. If you pass Go, collect £200.',
    effect: {'type': 'move_to', 'square': 1}),
CardDefinition(id: 'ch_14', label: 'You have been elected Chairman of the Board. Pay each player £50.',
    effect: {'type': 'pay_each', 'amount': 50}),
CardDefinition(id: 'ch_15', label: 'Your building loan matures. Collect £150.',
    effect: {'type': 'collect', 'amount': 150}),
```

---

## Files changed

| File | Change |
|------|--------|
| `packages/spoomn_core/lib/src/constants/cards.dart` | Update all labels; fix cc_12 amount; fix cc_15 card; fix ch_02 destination |

## Effect-only changes (game mechanic impact)

| Card | Old effect | New effect | Impact |
|------|-----------|------------|--------|
| cc_12 | pay 50 | pay 150 | Player pays £100 more |
| cc_15 | collect 100 | collect 10 | Player collects £90 less |
| ch_02 | move_to sq 11 (Pall Mall) | move_to sq 39 (Mayfair) | Advances further; higher rent risk |

## Verification

After hot reload, draw each card type and confirm:
1. Overlay shows full sentence with amount
2. Correct amount deducted/credited in balance
3. ch_02 lands on Mayfair not Pall Mall
