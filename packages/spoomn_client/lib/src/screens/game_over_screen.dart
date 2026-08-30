import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';

class GameOverScreen extends ConsumerWidget {
  const GameOverScreen({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(roomPlayersProvider(roomId)).valueOrNull ?? [];
    final state = ref.watch(gameStateProvider(roomId)).valueOrNull;

    final rankings = [...players]..sort((a, b) {
        if (a.isBankrupt && !b.isBankrupt) return 1;
        if (!a.isBankrupt && b.isBankrupt) return -1;
        final balA = state?.balances[a.playerId] ?? 0;
        final balB = state?.balances[b.playerId] ?? 0;
        return balB.compareTo(balA);
      });

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Game Over', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            ...rankings.asMap().entries.map((e) {
              final pos = e.key + 1;
              final p = e.value;
              final balance = state?.balances[p.playerId] ?? 0;
              return ListTile(
                leading: CircleAvatar(child: Text('$pos')),
                title: Text(p.displayName ?? 'Guest'),
                subtitle: Text(p.isBankrupt ? 'Bankrupt' : '£$balance'),
              );
            }),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Back to Menu'),
            ),
          ],
        ),
      ),
    );
  }
}
