import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../../game/spoomn_game.dart';
import '../../providers/providers.dart';
import '../../services/game_service.dart';
import 'game_constants.dart';
import 'group_colour.dart';

class GameSquareHoverCard extends ConsumerWidget {
  const GameSquareHoverCard({super.key, required this.roomId, required this.game});
  final String roomId;
  final SpoomnGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(roomId)).valueOrNull;
    final players = ref.watch(roomPlayersProvider(roomId)).valueOrNull ?? [];
    final isDebug = ref.watch(isDebugModeProvider(roomId));

    return ListenableBuilder(
      listenable: Listenable.merge([game.hoveredSquare, game.tappedSquare]),
      builder: (context, _) {
        final squareIndex = game.hoveredSquare.value ?? game.tappedSquare.value;
        if (squareIndex == null) return const SizedBox.shrink();
        final square = Board.squares[squareIndex];
        final ownerId = state?.propertyOwnership['$squareIndex'];
        final ownerColour = ownerId != null ? game.playerColours[ownerId] : null;
        final ownerName = ownerId != null
            ? (players.where((p) => p.playerId == ownerId).firstOrNull?.displayName ?? 'Unknown')
            : null;
        final houseCount = state?.houses['$squareIndex'] ?? 0;
        final hasHotel = state?.hotels['$squareIndex'] ?? false;
        final ownedStationCount = ownerId == null
            ? null
            : Board.stationIndices
                .where((i) => state?.propertyOwnership['$i'] == ownerId)
                .length;
        final ownedUtilityCount = ownerId == null
            ? null
            : Board.utilityIndices
                .where((i) => state?.propertyOwnership['$i'] == ownerId)
                .length;

        return Align(
          alignment: Alignment.topRight,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GamePropertyCard(
                  square: square,
                  ownerName: ownerName,
                  ownerColour: ownerColour,
                  houseCount: houseCount,
                  hasHotel: hasHotel,
                  ownedStationCount: ownedStationCount,
                  ownedUtilityCount: ownedUtilityCount,
                ),
                if (isDebug && square.price != null) ...[
                  const SizedBox(height: 8),
                  GameDebugAssignCard(
                    roomId: roomId,
                    squareIndex: squareIndex,
                    players: players,
                    currentOwner: ownerId,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class GameDebugAssignCard extends ConsumerStatefulWidget {
  const GameDebugAssignCard({
    super.key,
    required this.roomId,
    required this.squareIndex,
    required this.players,
    this.currentOwner,
  });
  final String roomId;
  final int squareIndex;
  final List<RoomPlayer> players;
  final String? currentOwner;

  @override
  ConsumerState<GameDebugAssignCard> createState() => _GameDebugAssignCardState();
}

class _GameDebugAssignCardState extends ConsumerState<GameDebugAssignCard> {
  String? _selected;

  @override
  void didUpdateWidget(GameDebugAssignCard old) {
    super.didUpdateWidget(old);
    if (old.squareIndex != widget.squareIndex || old.currentOwner != widget.currentOwner) {
      _selected = widget.currentOwner;
    }
  }

  @override
  Widget build(BuildContext context) {
    _selected ??= widget.currentOwner;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Assign owner',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String?>(
                    value: _selected,
                    isExpanded: true,
                    isDense: true,
                    dropdownColor: Colors.white,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Unowned', style: TextStyle(fontSize: 12, color: Colors.black87)),
                      ),
                      ...widget.players.map((p) => DropdownMenuItem(
                            value: p.playerId,
                            child: Text(
                              p.displayName ?? 'Guest',
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selected = v),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 30,
                  child: FilledButton(
                    onPressed: _assign,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Assign', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assign() async {
    try {
      await ref.read(gameServiceProvider).submitAction(
        widget.roomId,
        GameAction.debugAssignProperty,
        {'square': widget.squareIndex, 'player_id': _selected},
      );
    } on GameServiceException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class GamePropertyCard extends StatelessWidget {
  const GamePropertyCard({
    super.key,
    required this.square,
    this.ownerName,
    this.ownerColour,
    this.houseCount = 0,
    this.hasHotel = false,
    this.ownedStationCount,
    this.ownedUtilityCount,
  });
  final BoardSquare square;
  final String? ownerName;
  final Color? ownerColour;
  final int houseCount;
  final bool hasHotel;
  final int? ownedStationCount;
  final int? ownedUtilityCount;

  @override
  Widget build(BuildContext context) {
    final colour = groupColour(square.colourGroup);
    final int? activeRentIndex =
        ownerName != null ? (hasHotel ? 5 : houseCount.clamp(0, 4)) : null;

    final card = Card(
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      shape: ownerColour != null
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: ownerColour!, width: 2),
            )
          : null,
      child: SizedBox(
        width: 180,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (colour != null) Container(height: 24, color: colour),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    square.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  if (square.price != null) Text('Price: £${square.price}'),
                  if (square.mortgageValue != null) Text('Mortgage: £${square.mortgageValue}'),
                  if (square.houseCost != null) ...[
                    Text('House: £${square.houseCost}'),
                    Text('Hotel: £${square.hotelCost}'),
                  ],
                  if (square.rent != null) ...[
                    const Divider(),
                    const Text('Rent', style: TextStyle(fontWeight: FontWeight.w600)),
                    _rentRow('Base', square.rent![0], isActive: activeRentIndex == 0),
                    const Text(
                      'x2 if full set owned',
                      style: TextStyle(fontSize: 9, color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                    _rentRow('1 House', square.rent![1], isActive: activeRentIndex == 1),
                    _rentRow('2 Houses', square.rent![2], isActive: activeRentIndex == 2),
                    _rentRow('3 Houses', square.rent![3], isActive: activeRentIndex == 3),
                    _rentRow('4 Houses', square.rent![4], isActive: activeRentIndex == 4),
                    _rentRow('Hotel', square.rent![5], isActive: activeRentIndex == 5),
                  ],
                  if (square.type == SquareType.station) ...[
                    const Divider(),
                    const Text('Rent', style: TextStyle(fontWeight: FontWeight.w600)),
                    _rentRow('1 Station', 25, isActive: ownedStationCount == 1),
                    _rentRow('2 Stations', 50, isActive: ownedStationCount == 2),
                    _rentRow('3 Stations', 100, isActive: ownedStationCount == 3),
                    _rentRow('4 Stations', 200, isActive: ownedStationCount == 4),
                  ],
                  if (square.type == SquareType.utility) ...[
                    const Divider(),
                    const Text('Rent', style: TextStyle(fontWeight: FontWeight.w600)),
                    _textRow('1 Utility', '4× dice', isActive: ownedUtilityCount == 1),
                    _textRow('2 Utilities', '10× dice', isActive: ownedUtilityCount == 2),
                  ],
                  if (square.taxAmount != null) Text('Tax: £${square.taxAmount}'),
                  if (square.price == null && square.taxAmount == null)
                    Text(square.type.name, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (ownerName == null || ownerColour == null) return card;

    // Tab height ~22px; card offset by (tabHeight - 2) so tab overlaps card top by 2px,
    // covering the border join and making them look physically connected.
    const tabHeight = 22.0;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(padding: const EdgeInsets.only(top: tabHeight - 2), child: card),
        Positioned(
          top: 2,
          child: Container(
            height: tabHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ownerColour,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              'Owned by $ownerName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _rentRow(String label, int amount, {bool isActive = false}) {
    final textStyle = TextStyle(
      fontSize: 11,
      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
      color: isActive ? Colors.green.shade800 : null,
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textStyle),
          Text('£$amount', style: textStyle),
        ],
      ),
    );
    if (!isActive) return row;
    return Container(
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(3),
      ),
      child: row,
    );
  }

  Widget _textRow(String label, String value, {bool isActive = false}) {
    final textStyle = TextStyle(
      fontSize: 11,
      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
      color: isActive ? Colors.green.shade800 : null,
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textStyle),
          Text(value, style: textStyle),
        ],
      ),
    );
    if (!isActive) return row;
    return Container(
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(3),
      ),
      child: row,
    );
  }
}
