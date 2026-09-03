import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/game_service.dart';

class GameStartOverlay extends ConsumerStatefulWidget {
  const GameStartOverlay({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<GameStartOverlay> createState() => _GameStartOverlayState();
}

class _GameStartOverlayState extends ConsumerState<GameStartOverlay> {
  bool _starting = false;

  Future<void> _beginGame() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await ref.read(gameServiceProvider).beginGame(widget.roomId);
    } on GameServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        setState(() => _starting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(gameRoomProvider(widget.roomId)).value;
    final myId = ref.watch(currentUserIdProvider);
    final isHost = room?.hostId == myId;
    final playerCount = room?.playerCount ?? 0;

    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.casino, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Ready to play?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '$playerCount player${playerCount == 1 ? '' : 's'} joined',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (isHost)
                  FilledButton.icon(
                    onPressed: _starting ? null : _beginGame,
                    icon: _starting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('Start Game'),
                  )
                else
                  Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        'Waiting for host to start...',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
