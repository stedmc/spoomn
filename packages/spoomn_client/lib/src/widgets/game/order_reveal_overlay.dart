import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/spoomn_game.dart';
import '../../providers/providers.dart';

class GameOrderRevealOverlay extends ConsumerStatefulWidget {
  const GameOrderRevealOverlay({super.key, required this.roomId, required this.onDismiss});
  final String roomId;
  final VoidCallback onDismiss;

  @override
  ConsumerState<GameOrderRevealOverlay> createState() => _GameOrderRevealOverlayState();
}

class _GameOrderRevealOverlayState extends ConsumerState<GameOrderRevealOverlay> {
  Timer? _countdownTimer;
  int _secondsLeft = 5;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = (_secondsLeft - 1).clamp(0, 5);
      setState(() => _secondsLeft = next);
      if (next == 0) {
        _countdownTimer?.cancel();
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawPlayers = ref.watch(roomPlayersProvider(widget.roomId)).valueOrNull ?? [];
    final players = [...rawPlayers]
      ..sort((a, b) {
        final ao = a.seatOrder, bo = b.seatOrder;
        if (ao == null && bo == null) return 0;
        if (ao == null) return 1;
        if (bo == null) return -1;
        return ao.compareTo(bo);
      });

    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          elevation: 8,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Play Order',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    ...players.asMap().entries.map((entry) {
                      final i = entry.key;
                      final p = entry.value;
                      final colour = SpoomnGame.tokenColourToColor(p.tokenColour);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${i + 1}.',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
                            ),
                            Text(
                              p.displayName ?? 'Guest',
                              style: TextStyle(
                                fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (i == 0) ...[
                              const SizedBox(width: 8),
                              const Text('— rolls first!', style: TextStyle(color: Colors.green)),
                            ],
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 240,
                      child: LinearProgressIndicator(value: _secondsLeft / 5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Game starts in $_secondsLeft...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onDismiss,
                  tooltip: 'Close',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
