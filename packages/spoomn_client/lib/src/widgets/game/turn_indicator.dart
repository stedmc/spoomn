import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/spoomn_game.dart';
import '../../providers/providers.dart';

class TurnIndicatorWidget extends ConsumerWidget {
  const TurnIndicatorWidget({super.key, required this.roomId, required this.game});
  final String roomId;
  final SpoomnGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(gameRoomProvider(roomId)).value;
    final players = ref.watch(roomPlayersProvider(roomId)).value ?? [];
    final currentId = room?.currentPlayerId;
    if (currentId == null) return const SizedBox.shrink();

    final player = players.where((p) => p.playerId == currentId).firstOrNull;
    final name = player?.displayName ?? 'Player';

    return ValueListenableBuilder<Map<String, Color>>(
      valueListenable: game.playerColoursNotifier,
      builder: (_, colours, __) {
        final colour = colours[currentId] ?? Colors.grey;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "$name's turn",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
