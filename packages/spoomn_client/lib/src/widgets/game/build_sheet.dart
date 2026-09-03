import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../../providers/providers.dart';
import 'game_constants.dart';
import 'group_colour.dart';

class GameBuildSheet extends ConsumerWidget {
  const GameBuildSheet({
    super.key,
    required this.roomId,
    required this.effectivePlayerId,
    required this.onAct,
  });
  final String roomId;
  final String effectivePlayerId;
  final Future<void> Function(String, Map<String, dynamic>) onAct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(roomId)).value;
    if (state == null) return const SizedBox.shrink();

    final config = ref.watch(roomConfigProvider(roomId)).value;
    final houseLimit = (config?['house_limit'] as int?) ?? 32;
    final hotelLimit = (config?['hotel_limit'] as int?) ?? 12;

    final totalHousesInPlay = state.houses.values
        .fold<int>(0, (sum, v) => sum + ((v as num?)?.toInt() ?? 0));
    final totalHotelsInPlay = state.hotels.values.where((v) => v == true).length;

    final housesRemaining = houseLimit - totalHousesInPlay;
    final hotelsRemaining = hotelLimit - totalHotelsInPlay;

    final owned = state.propertyOwnership.entries
        .where((e) => e.value == effectivePlayerId)
        .map((e) => int.tryParse(e.key))
        .whereType<int>()
        .where((idx) => Board.squares[idx].type == SquareType.property)
        .toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Build / Sell', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SupplyChip(
                  icon: Icons.house,
                  label: 'Houses',
                  remaining: housesRemaining,
                  total: houseLimit,
                ),
                const SizedBox(width: 12),
                _SupplyChip(
                  icon: Icons.apartment,
                  label: 'Hotels',
                  remaining: hotelsRemaining,
                  total: hotelLimit,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (owned.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No buildable properties.', style: TextStyle(color: Colors.grey)),
          ),
        ...owned.map((idx) {
          final sq = Board.squares[idx];
          final houses = state.houses['$idx'] ?? 0;
          final hasHotel = state.hotels['$idx'] == true;
          final colour = groupColour(sq.colourGroup);

          final groupIndices = sq.colourGroup != null
              ? (Board.colourGroups[sq.colourGroup] ?? <int>[])
              : <int>[];
          final groupComplete = groupIndices.isNotEmpty &&
              groupIndices.every((gi) => state.propertyOwnership['$gi'] == effectivePlayerId);
          final isMortgaged = state.mortgaged.contains(idx);
          final canBuild = groupComplete && !isMortgaged;

          final statusText = hasHotel
              ? 'Hotel'
              : houses > 0
                  ? '$houses house${houses == 1 ? '' : 's'}'
                  : 'No buildings';
          final costText = !hasHotel && sq.houseCost != null
              ? '  ·  £${houses < 4 ? sq.houseCost : sq.hotelCost} to build next'
              : '';

          return Opacity(
            opacity: canBuild ? 1.0 : 0.45,
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: colour != null
                    ? Container(
                        width: 12,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colour,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    : const SizedBox(width: 12),
                title: Text(sq.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text('$statusText$costText', style: const TextStyle(fontSize: 12)),
                trailing: !canBuild
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (houses > 0)
                            TextButton(
                              onPressed: () => onAct(GameAction.sellHouse, {'square': idx}),
                              child: const Text('-House'),
                            ),
                          if (hasHotel)
                            TextButton(
                              onPressed: () => onAct(GameAction.sellHotel, {'square': idx}),
                              child: const Text('-Hotel'),
                            ),
                          if (!hasHotel && houses < 4)
                            TextButton(
                              onPressed: () => onAct(GameAction.buildHouse, {'square': idx}),
                              child: const Text('+House'),
                            ),
                          if (houses == 4 && !hasHotel)
                            TextButton(
                              onPressed: () => onAct(GameAction.buildHotel, {'square': idx}),
                              child: const Text('+Hotel'),
                            ),
                        ],
                      ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _SupplyChip extends StatelessWidget {
  const _SupplyChip({
    required this.icon,
    required this.label,
    required this.remaining,
    required this.total,
  });

  final IconData icon;
  final String label;
  final int remaining;
  final int total;

  @override
  Widget build(BuildContext context) {
    final isLow = remaining <= (total * 0.25).ceil();
    final color = isLow ? Colors.orange : Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(
              '$remaining / $total remaining',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ],
    );
  }
}
