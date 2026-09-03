import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../../providers/providers.dart';
import 'game_constants.dart';

class GameStatusBanner extends ConsumerWidget {
  const GameStatusBanner({super.key, required this.roomId, this.activeSheet});
  final String roomId;
  final String? activeSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(roomId)).valueOrNull;
    final room = ref.watch(gameRoomProvider(roomId)).valueOrNull;
    final players = ref.watch(roomPlayersProvider(roomId)).valueOrNull ?? [];

    if (state == null || room == null) return const SizedBox.shrink();

    String playerName(String? id) => id == null
        ? 'Unknown'
        : (players.where((p) => p.playerId == id).firstOrNull?.displayName ?? 'Unknown');

    final messages = <({String text, Color color})>[];

    final currentName = playerName(room.currentPlayerId);
    messages.add((text: "$currentName's turn", color: Theme.of(context).colorScheme.onSurface));

    final pending = state.pendingAction;
    if (pending?['type'] == GamePendingType.rentPayment) {
      final amount = pending!['amount'] as int? ?? 0;
      final ownerName = playerName(pending['owner_id'] as String?);
      messages.add((
        text: '£$amount rent owed to $ownerName',
        color: Colors.orangeAccent,
      ));
    }

    if (activeSheet != null) {
      final verb = switch (activeSheet) {
        'build' => 'building',
        'mortgage' => 'mortgaging',
        _ => activeSheet,
      };
      messages.add((
        text: '$currentName is $verb',
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ));
    }

    if (state.phase == GamePhase.auction) {
      final auction = state.activeAuction;
      final bidderName = playerName(auction?['current_bidder'] as String?);
      final currentPrice = (auction?['current_price'] as int?) ?? 0;
      final leaderId = auction?['current_leader'] as String?;
      messages.add((text: 'Auction — $bidderName\'s turn to bid', color: Colors.deepPurpleAccent));
      messages.add((
        text: 'Current bid: £$currentPrice${leaderId != null ? ' (${playerName(leaderId)} leads)' : ''}',
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      ));
    }

    for (final p in players.where((p) => p.isBankrupt)) {
      messages.add((
        text: '${p.displayName ?? 'Player'} is bankrupt',
        color: Colors.redAccent,
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: messages
            .map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    m.text,
                    style: TextStyle(fontSize: 12, color: m.color),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
