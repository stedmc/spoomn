import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../../game/spoomn_game.dart';
import '../../providers/providers.dart';

class GamePlayerStrip extends ConsumerStatefulWidget {
  const GamePlayerStrip({super.key, required this.roomId, required this.game});
  final String roomId;
  final SpoomnGame game;

  @override
  ConsumerState<GamePlayerStrip> createState() => _GamePlayerStripState();
}

class _GamePlayerStripState extends ConsumerState<GamePlayerStrip> {
  final Map<String, int> _balanceDeltas = {};
  final Map<String, Timer> _deltaTimers = {};

  @override
  void dispose() {
    for (final t in _deltaTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  List<Widget> _buildImmunityIcons(
    GameState? state,
    String playerId,
    List<RoomPlayer> allPlayers,
  ) {
    if (state == null) return [];
    final mods = state.rentModifiers[playerId] as Map<String, dynamic>?;
    if (mods == null) return [];
    final protections = (mods['protections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (protections.isEmpty) return [];

    final icons = <Widget>[];
    for (final p in protections) {
      final fromId = p['from_player_id'] as String?;
      final turns = (p['turns'] as int?) ?? 0;
      final fromPlayer = fromId != null
          ? allPlayers.where((pl) => pl.playerId == fromId).firstOrNull
          : null;
      final fromName = fromPlayer?.displayName ?? (fromId != null ? 'a player' : 'a card');
      final iconColor = fromId != null
          ? (widget.game.playerColours[fromId] ?? Colors.white54)
          : Colors.white54;
      final tooltipMsg = 'Immunity from rent from $fromName'
          '${turns > 0 ? ' ($turns turn${turns == 1 ? '' : 's'} remaining)' : ''}';

      icons.add(
        Tooltip(
          message: tooltipMsg,
          child: Icon(Icons.shield, size: 12, color: iconColor),
        ),
      );
    }
    if (icons.isNotEmpty) icons.add(const SizedBox(width: 4));
    return icons;
  }

  @override
  Widget build(BuildContext context) {
    final rawPlayers = ref.watch(roomPlayersProvider(widget.roomId)).value ?? [];
    final players = [...rawPlayers]
      ..sort((a, b) {
        final ao = a.seatOrder, bo = b.seatOrder;
        if (ao == null && bo == null) return 0;
        if (ao == null) return 1;
        if (bo == null) return -1;
        return ao.compareTo(bo);
      });
    final state = ref.watch(gameStateProvider(widget.roomId)).value;
    final room = ref.watch(gameRoomProvider(widget.roomId)).value;

    ref.listen(gameStateProvider(widget.roomId), (prev, next) {
      if (prev == null) return;
      prev.whenData((prevState) {
        next.whenData((nextState) {
          final currentPlayers =
              ref.read(roomPlayersProvider(widget.roomId)).value ?? [];
          for (final p in currentPlayers) {
            final oldBal = prevState.balances[p.playerId] ?? 0;
            final newBal = nextState.balances[p.playerId] ?? 0;
            if (oldBal != newBal) {
              setState(() => _balanceDeltas[p.playerId] = newBal - oldBal);
              _deltaTimers[p.playerId]?.cancel();
              _deltaTimers[p.playerId] = Timer(const Duration(seconds: 3), () {
                if (mounted) setState(() => _balanceDeltas.remove(p.playerId));
              });
            }
          }
        });
      });
    });

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.game.hoveredPlayerIdNotifier,
        widget.game.playerColoursNotifier,
      ]),
      builder: (context, _) {
        final hoveredPlayerId = widget.game.hoveredPlayerIdNotifier.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: players.map((p) {
            final balance = state?.balances[p.playerId] ?? 0;
            final isActive = room?.currentPlayerId == p.playerId;
            final isGameHovered = hoveredPlayerId == p.playerId;
            final delta = _balanceDeltas[p.playerId];
            final playerColour = widget.game.playerColours[p.playerId] ?? Colors.grey;

            return MouseRegion(
              onEnter: (_) => widget.game.setHoveredPlayer(p.playerId),
              onExit: (_) => widget.game.setHoveredPlayer(null),
              child: ListTile(
                dense: true,
                tileColor: isActive
                    ? Theme.of(context).colorScheme.primaryContainer
                    : isGameHovered
                        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6)
                        : null,
                onTap: () => widget.game.lockHighlightForPlayer(p.playerId),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      child: isActive
                          ? Icon(Icons.play_arrow, size: 14,
                              color: Theme.of(context).colorScheme.primary)
                          : const SizedBox(width: 14),
                    ),
                    const SizedBox(width: 2),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: playerColour,
                        border: Border.all(
                          color: p.isConnected ? Colors.white54 : Colors.grey.shade600,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
                title: Text(
                  p.displayName ?? 'Guest',
                  style: TextStyle(
                    fontSize: 13,
                    decoration: p.isBankrupt ? TextDecoration.lineThrough : null,
                    color: p.isBankrupt ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4) : null,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ..._buildImmunityIcons(state, p.playerId, players),
                    if (delta != null)
                      Text(
                        delta > 0 ? '+£$delta' : '-£${delta.abs()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: delta > 0 ? Colors.greenAccent : Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (delta != null) const SizedBox(width: 4),
                    Text(
                      '£$balance',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: balance < 0 ? Colors.red : null,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
