import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../../providers/providers.dart';
import 'game_constants.dart';
import 'group_colour.dart';

class GameMortgageSheet extends ConsumerWidget {
  const GameMortgageSheet({
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
    final state = ref.watch(gameStateProvider(roomId)).valueOrNull;
    if (state == null) return const SizedBox.shrink();

    final owned = state.propertyOwnership.entries
        .where((e) => e.value == effectivePlayerId)
        .map((e) => int.tryParse(e.key))
        .whereType<int>()
        .toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Mortgage / Unmortgage',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (owned.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No properties owned.', style: TextStyle(color: Colors.grey)),
          ),
        ...owned.map((idx) {
          final sq = Board.squares[idx];
          final colour = groupColour(sq.colourGroup);
          final isMortgaged = state.mortgaged.contains(idx);

          return Card(
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
              subtitle: Text(
                isMortgaged
                    ? 'Mortgaged  ·  £${sq.mortgageValue} to unmortgage'
                    : 'Unmortgaged  ·  £${sq.mortgageValue} value',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: isMortgaged
                  ? TextButton(
                      onPressed: () => onAct(GameAction.unmortgageProperty, {'square': idx}),
                      child: const Text('Unmortgage'),
                    )
                  : TextButton(
                      onPressed: () => onAct(GameAction.mortgageProperty, {'square': idx}),
                      child: const Text('Mortgage'),
                    ),
            ),
          );
        }),
      ],
    );
  }
}
