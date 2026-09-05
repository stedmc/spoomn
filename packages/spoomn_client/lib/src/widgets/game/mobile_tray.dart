import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../../game/spoomn_game.dart';
import '../../providers/providers.dart';
import 'action_bar.dart';
import 'activity_log.dart';
import 'debug_panel.dart';
import 'game_constants.dart';
import 'player_strip.dart';
import 'settings_sheet.dart';

enum _TrayPanel { none, players, log, settings }

/// Mobile equivalent of [GameSidePanel] (side_panel.dart): the player list,
/// activity log and settings collapse up from a bottom tray instead of
/// occupying a fixed-width sidebar, and the roll/buy/trade action bar
/// stays pinned to the very bottom as the always-visible "activity" tray.
class GameMobileTray extends ConsumerStatefulWidget {
  const GameMobileTray({super.key, required this.roomId, required this.game, required this.isAnimating});
  final String roomId;
  final SpoomnGame game;
  final bool isAnimating;

  @override
  ConsumerState<GameMobileTray> createState() => _GameMobileTrayState();
}

class _GameMobileTrayState extends ConsumerState<GameMobileTray> {
  _TrayPanel _panel = _TrayPanel.none;
  String? _actingAs;
  bool _useForced = false;
  int _forcedDie1 = 1;
  int _forcedDie2 = 1;

  void _toggle(_TrayPanel p) {
    setState(() => _panel = _panel == p ? _TrayPanel.none : p);
  }

  @override
  Widget build(BuildContext context) {
    final isDebug = ref.watch(isDebugModeProvider(widget.roomId));
    final isMyTurn = ref.watch(isMyTurnProvider(widget.roomId));
    final myId = ref.watch(currentUserIdProvider);
    final room = ref.watch(gameRoomProvider(widget.roomId)).value;
    final players = ref.watch(roomPlayersProvider(widget.roomId)).value ?? [];
    final stateAsync = ref.watch(gameStateProvider(widget.roomId));
    final phase = stateAsync.value?.phase.name ?? (stateAsync.isLoading ? GamePhaseName.roll : null);
    final auctionBidder = stateAsync.value?.activeAuction?['current_bidder'] as String?;
    final isMyAuctionTurn = phase == GamePhaseName.auction && auctionBidder == myId;

    ref.listen(gameRoomProvider(widget.roomId), (_, next) {
      next.whenData((r) {
        final currentPhase = ref.read(gameStateProvider(widget.roomId)).value?.phase;
        if (_actingAs != null &&
            _actingAs != r.currentPlayerId &&
            currentPhase != GamePhase.auction) {
          setState(() => _actingAs = null);
        }
      });
    });

    ref.listen(gameStateProvider(widget.roomId), (prev, next) {
      final state = next.value;
      if (state == null) return;
      final prevState = prev?.value;
      if (state.phase == GamePhase.auction && ref.read(isDebugModeProvider(widget.roomId))) {
        final bidder = state.activeAuction?['current_bidder'] as String?;
        if (bidder != null && _actingAs != bidder) {
          setState(() => _actingAs = bidder);
        }
      }
      if (prevState?.phase == GamePhase.auction && state.phase != GamePhase.auction) {
        setState(() => _actingAs = null);
      }
    });

    final effectiveActingAs = _actingAs ?? room?.currentPlayerId ?? '';
    final showActionBar =
        (isDebug || (isMyTurn && phase != GamePhaseName.auction) || isMyAuctionTurn) && !widget.isAnimating;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.bottomCenter,
              child: _panel == _TrayPanel.none
                  ? const SizedBox(width: double.infinity)
                  : ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    switch (_panel) {
                                      _TrayPanel.players => 'Players',
                                      _TrayPanel.log => 'Activity Log',
                                      _TrayPanel.settings => 'Settings',
                                      _TrayPanel.none => '',
                                    },
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                                  tooltip: 'Collapse',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() => _panel = _TrayPanel.none),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Flexible(
                            child: switch (_panel) {
                              _TrayPanel.players => SingleChildScrollView(
                                  child: GamePlayerStrip(roomId: widget.roomId, game: widget.game),
                                ),
                              _TrayPanel.log => GameActivityLog(roomId: widget.roomId),
                              _TrayPanel.settings => const SingleChildScrollView(child: GameSettingsSheet()),
                              _TrayPanel.none => const SizedBox.shrink(),
                            },
                          ),
                        ],
                      ),
                    ),
            ),
            const Divider(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _TrayToggleButton(
                  icon: Icons.people,
                  label: 'Players',
                  selected: _panel == _TrayPanel.players,
                  onTap: () => _toggle(_TrayPanel.players),
                ),
                _TrayToggleButton(
                  icon: Icons.history,
                  label: 'Activity',
                  selected: _panel == _TrayPanel.log,
                  onTap: () => _toggle(_TrayPanel.log),
                ),
                _TrayToggleButton(
                  icon: Icons.settings,
                  label: 'Settings',
                  selected: _panel == _TrayPanel.settings,
                  onTap: () => _toggle(_TrayPanel.settings),
                ),
              ],
            ),
            if (isDebug) ...[
              const Divider(height: 1),
              GameDebugPanel(
                roomId: widget.roomId,
                players: players,
                actingAs: effectiveActingAs,
                onActingAsChanged: (v) => setState(() => _actingAs = v),
              ),
            ],
            if (showActionBar) ...[
              const Divider(height: 1),
              if (phase == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: GameActionBar(
                    roomId: widget.roomId,
                    phase: phase,
                    debugActingAs: isDebug ? effectiveActingAs : null,
                    forcedRoll: (isDebug && _useForced) ? [_forcedDie1, _forcedDie2] : null,
                    isDebug: isDebug,
                    useForced: _useForced,
                    forcedDie1: _forcedDie1,
                    forcedDie2: _forcedDie2,
                    onDiceChanged: (d1, d2, use) => setState(() {
                      _forcedDie1 = d1;
                      _forcedDie2 = d2;
                      _useForced = use;
                    }),
                    onActiveSheetChanged: (_) {},
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrayToggleButton extends StatelessWidget {
  const _TrayToggleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}
