# Board and Setup

## Default Board

Standard Monopoly layout: 40 squares arranged in a loop. Players start on Go (square 0) and move clockwise.

### Square Index Map

```
00  Go
01  Old Kent Road          (Brown)
02  Community Chest
03  Whitechapel Road       (Brown)
04  Income Tax
05  King's Cross Station
06  The Angel Islington    (Light Blue)
07  Chance
08  Euston Road            (Light Blue)
09  Pentonville Road       (Light Blue)
10  Jail / Just Visiting
11  Pall Mall              (Pink)
12  Electric Company       (Utility)
13  Whitehall              (Pink)
14  Northumberland Avenue  (Pink)
15  Marylebone Station
16  Bow Street             (Orange)
17  Community Chest
18  Marlborough Street     (Orange)
19  Vine Street            (Orange)
20  Free Parking
21  Strand                 (Red)
22  Chance
23  Fleet Street           (Red)
24  Trafalgar Square       (Red)
25  Fenchurch Street Station
26  Piccadilly             (Yellow)
27  Coventry Street        (Yellow)
28  Community Chest
29  Leicester Square       (Yellow)
30  Go To Jail
31  Bond Street            (Green)
32  Oxford Street          (Green)
33  Chance
34  Regent Street          (Green)
35  Liverpool Street Station
36  Chance
37  Park Lane              (Dark Blue)
38  Super Tax
39  Mayfair                (Dark Blue)
```

### Colour Groups

| Colour | Squares | Group Size |
|--------|---------|------------|
| Brown | 01, 03 | 2 |
| Light Blue | 06, 08, 09 | 3 |
| Pink | 11, 13, 14 | 3 |
| Orange | 16, 18, 19 | 3 |
| Red | 21, 23, 24 | 3 |
| Yellow | 26, 27, 29 | 3 |
| Green | 31, 32, 34 | 3 |
| Dark Blue | 37, 39 | 2 |

### Property Values (Default)

| Square | Name | Price | Mortgage | House Cost | Hotel Cost |
|--------|------|-------|----------|------------|------------|
| 01 | Old Kent Road | £60 | £30 | £50 | £50 |
| 03 | Whitechapel Road | £60 | £30 | £50 | £50 |
| 06 | Angel Islington | £100 | £50 | £50 | £50 |
| 08 | Euston Road | £100 | £50 | £50 | £50 |
| 09 | Pentonville Road | £120 | £60 | £50 | £50 |
| 11 | Pall Mall | £140 | £70 | £100 | £100 |
| 13 | Whitehall | £140 | £70 | £100 | £100 |
| 14 | Northumberland Ave | £160 | £80 | £100 | £100 |
| 16 | Bow Street | £180 | £90 | £100 | £100 |
| 18 | Marlborough Street | £180 | £90 | £100 | £100 |
| 19 | Vine Street | £200 | £100 | £100 | £100 |
| 21 | Strand | £220 | £110 | £150 | £150 |
| 23 | Fleet Street | £220 | £110 | £150 | £150 |
| 24 | Trafalgar Square | £240 | £120 | £150 | £150 |
| 26 | Piccadilly | £260 | £130 | £150 | £150 |
| 27 | Coventry Street | £260 | £130 | £150 | £150 |
| 29 | Leicester Square | £280 | £140 | £150 | £150 |
| 31 | Bond Street | £300 | £150 | £200 | £200 |
| 32 | Oxford Street | £300 | £150 | £200 | £200 |
| 34 | Regent Street | £320 | £160 | £200 | £200 |
| 37 | Park Lane | £350 | £175 | £200 | £200 |
| 39 | Mayfair | £400 | £200 | £200 | £200 |

### Stations (Default)

Price: £200. Mortgage: £100.

Rent by stations owned:

| Owned | Rent |
|-------|------|
| 1 | £25 |
| 2 | £50 |
| 3 | £100 |
| 4 | £200 |

### Utilities (Default)

Price: £150. Mortgage: £75.

Rent:
- 1 utility owned: 4× current dice roll
- 2 utilities owned: 10× current dice roll

---

## Rent Tables (Default)

| Colour | Base | Colour Set | 1H | 2H | 3H | 4H | Hotel |
|--------|------|-----------|----|----|----|----|-------|
| Brown | £2 / £4 | 2× | £10 / £20 | £30 / £60 | £90 / £180 | £160 / £320 | £250 / £450 |
| Light Blue | £6 / £6 / £8 | 2× | £30 / £30 / £40 | £90 / £90 / £100 | £270 / £270 / £300 | £400 / £400 / £450 | £550 / £550 / £600 |
| Pink | £10 / £10 / £12 | 2× | £50 / £50 / £60 | £150 / £150 / £180 | £450 / £450 / £500 | £625 / £625 / £700 | £750 / £750 / £900 |
| Orange | £14 / £14 / £16 | 2× | £70 / £70 / £80 | £200 / £200 / £220 | £550 / £550 / £600 | £750 / £750 / £800 | £950 / £950 / £1000 |
| Red | £18 / £18 / £20 | 2× | £90 / £90 / £100 | £250 / £250 / £300 | £700 / £700 / £750 | £875 / £875 / £925 | £1050 / £1050 / £1100 |
| Yellow | £22 / £22 / £24 | 2× | £110 / £110 / £120 | £330 / £330 / £360 | £800 / £800 / £850 | £975 / £975 / £1025 | £1150 / £1150 / £1200 |
| Green | £26 / £26 / £28 | 2× | £130 / £130 / £150 | £390 / £390 / £450 | £900 / £900 / £1000 | £1100 / £1100 / £1200 | £1275 / £1275 / £1400 |
| Dark Blue | £35 / £50 | 2× | £175 / £200 | £500 / £600 | £1100 / £1400 | £1300 / £1700 | £1500 / £2000 |

> Note: values separated by `/` represent each property in the group in index order.

---

## Starting State

### Bank

Bank starts with:
- £20,580 total (or unlimited in custom mode)
- 32 houses
- 12 hotels

All properties owned by bank. All cards shuffled.

### Players

Each player receives default starting money: **£1500**, distributed as:

| Note | Qty | Total |
|------|-----|-------|
| £500 | 2 | £1000 |
| £100 | 4 | £400 |
| £50 | 1 | £50 |
| £20 | 1 | £20 |
| £10 | 2 | £20 |
| £5 | 1 | £5 |
| £1 | 5 | £5 |

Starting position: square 00 (Go). No properties owned.

### Turn Order

Determined at game start: each player rolls one die; highest goes first. Ties re-roll. Turn order fixed for entire game.

---

## Configurable Setup Options

Board layout and property values are fixed (standard Monopoly). The following starting conditions are configurable per room.

### Money

| Config key | Default | Notes |
|------------|---------|-------|
| `starting_money` | 1500 | Per-player starting balance |
| `bank_unlimited` | false | If true, bank never runs out of money |
| `bank_starting_amount` | 20580 | Ignored when `bank_unlimited` is true |

### Buildings

| Config key | Default | Notes |
|------------|---------|-------|
| `house_limit` | 32 | Global house pool; set to `null` for unlimited |
| `hotel_limit` | 12 | Global hotel pool; set to `null` for unlimited |

When the house pool is exhausted, no more houses can be built anywhere on the board until another player sells or demolishes. Same rule applies to hotels. If `bank_unlimited` is true, building pools are also treated as unlimited.

### Turn Order

| Config key | Default | Options |
|------------|---------|---------|
| `turn_order_method` | `highest_roll` | `highest_roll`, `random`, `host_assigned` |

`host_assigned`: host sets seat order manually in the lobby before game starts.
