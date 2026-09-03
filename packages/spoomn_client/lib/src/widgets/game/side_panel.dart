import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../../game/spoomn_game.dart';
import '../../providers/providers.dart';
import 'action_bar.dart';
import 'activity_log.dart';
import 'debug_panel.dart';
import 'game_constants.dart';
import 'persistent_card_widget.dart';
import 'player_strip.dart';
import 'settings_sheet.dart';
import 'status_banner.dart';

class GameSidePanel extends ConsumerStatefulWidget {
  const GameSidePanel({super.key, required this.roomId, required this.game, required this.isAnimating});
  final String roomId;
  final SpoomnGame game;
  final bool isAnimating;

  @override
  ConsumerState<GameSidePanel> createState() => _GameSidePanelState();
}

class _GameSidePanelState extends ConsumerState<GameSidePanel> {
  String? _actingAs;
  bool _useForced = false;
  int _forcedDie1 = 1;
  int _forcedDie2 = 1;
  String? _activeSheet;

  @override
  Widget build(BuildContext context) {
    final isDebug = ref.watch(isDebugModeProvider(widget.roomId));
    final isMyTurn = ref.watch(isMyTurnProvider(widget.roomId));
    final myId = ref.watch(currentUserIdProvider);
    final room = ref.watch(gameRoomProvider(widget.roomId)).valueOrNull;
    final players = ref.watch(roomPlayersProvider(widget.roomId)).valueOrNull ?? [];
    final stateAsync = ref.watch(gameStateProvider(widget.roomId));
    // Show Roll Dice immediately while state is loading — server validates phase on every action.
    final phase = stateAsync.valueOrNull?.phase.name ?? (stateAsync.isLoading ? GamePhaseName.roll : null);
    final auctionBidder = stateAsync.valueOrNull?.activeAuction?['current_bidder'] as String?;
    final isMyAuctionTurn = phase == GamePhaseName.auction && auctionBidder == myId;

    // Auto-follow current player when the turn advances; hold off during auction
    // since auction has its own bidder-tracking listener below.
    ref.listen(gameRoomProvider(widget.roomId), (_, next) {
      next.whenData((r) {
        final currentPhase = ref.read(gameStateProvider(widget.roomId)).valueOrNull?.phase;
        if (_actingAs != null &&
            _actingAs != r.currentPlayerId &&
            currentPhase != GamePhase.auction) {
          setState(() => _actingAs = null);
        }
      });
    });

    // In debug mode, auto-switch actingAs to the current auction bidder so bots
    // can be driven by the host without touching the dropdown.
    ref.listen(gameStateProvider(widget.roomId), (prev, next) {
      final state = next.valueOrNull;
      if (state == null) return;
      final prevState = prev?.valueOrNull;
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

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: GamePlayerStrip(roomId: widget.roomId, game: widget.game),
          ),
          const Divider(height: 1),
          GameStatusBanner(roomId: widget.roomId, activeSheet: _activeSheet),
          const Divider(height: 1),
          if (isDebug) ...[
            GameDebugPanel(
              roomId: widget.roomId,
              players: players,
              actingAs: effectiveActingAs,
              onActingAsChanged: (v) => setState(() => _actingAs = v),
            ),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 0, 2),
            child: Text('Activity Log', style: Theme.of(context).textTheme.labelSmall),
          ),
          const Divider(height: 1),
          Expanded(child: GameActivityLog(roomId: widget.roomId)),
          PersistentCardWidget(roomId: widget.roomId),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.settings, size: 18),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => const GameSettingsSheet(),
              ),
            ),
          ),
          if ((isDebug || (isMyTurn && phase != GamePhaseName.auction) || isMyAuctionTurn) && !widget.isAnimating) ...[
            const Divider(height: 1),
            if (phase == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
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
                  onActiveSheetChanged: (s) => setState(() => _activeSheet = s),
                ),
              ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
