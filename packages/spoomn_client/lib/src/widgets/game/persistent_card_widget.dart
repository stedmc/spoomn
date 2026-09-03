import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/game_service.dart';
import 'game_constants.dart';

class PersistentCardWidget extends ConsumerWidget {
  const PersistentCardWidget({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserIdProvider) ?? '';
    final state = ref.watch(gameStateProvider(roomId)).valueOrNull;
    final room = ref.watch(gameRoomProvider(roomId)).valueOrNull;

    if (state == null || myId.isEmpty) return const SizedBox.shrink();

    final cardCount = state.getOutOfJailCards[myId] ?? 0;
    if (cardCount <= 0) return const SizedBox.shrink();

    final jailStatus = state.jailStatus[myId];
    final inJail = jailStatus?.inJail ?? false;
    final mandatoryTurns = jailStatus?.mandatoryTurnsRemaining ?? 0;
    final isMyTurn = room?.currentPlayerId == myId;
    final canUse = inJail && isMyTurn && mandatoryTurns == 0 &&
        state.phase.name == GamePhaseName.roll;

    final tooltipMsg = canUse
        ? 'Tap to escape jail'
        : inJail
            ? mandatoryTurns > 0
                ? 'Cannot use during mandatory jail turns'
                : 'Available on your roll turn'
            : 'Use when in jail';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.credit_card, size: 18,
              color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Get Out of Jail Free',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                if (cardCount > 1)
                  Text('×$cardCount',
                      style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.secondary)),
              ],
            ),
          ),
          Tooltip(
            message: tooltipMsg,
            child: TextButton(
              onPressed: canUse
                  ? () => ref
                      .read(gameServiceProvider)
                      .submitAction(roomId, GameAction.useGoojfCard, {})
                  : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Use', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}
