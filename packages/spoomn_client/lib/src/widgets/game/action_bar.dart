import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/game_service.dart';
import 'build_sheet.dart';
import 'game_constants.dart';
import 'mortgage_sheet.dart';
import 'trade_overlay.dart';

class GameActionBar extends ConsumerWidget {
  const GameActionBar({
    super.key,
    required this.roomId,
    required this.phase,
    this.debugActingAs,
    this.forcedRoll,
    this.isDebug = false,
    this.useForced = false,
    this.forcedDie1 = 1,
    this.forcedDie2 = 1,
    this.onDiceChanged,
    this.onActiveSheetChanged,
  });
  final String roomId;
  final String phase;
  final String? debugActingAs;
  final List<int>? forcedRoll;
  final bool isDebug;
  final bool useForced;
  final int forcedDie1;
  final int forcedDie2;
  final void Function(int d1, int d2, bool use)? onDiceChanged;
  final void Function(String?)? onActiveSheetChanged;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final extra = <String, dynamic>{};
    if (debugActingAs != null) extra['debug_as'] = debugActingAs;
    if (forcedRoll != null && action == GameAction.rollDice) extra['forced_roll'] = forcedRoll;
    try {
      await ref.read(gameServiceProvider).submitAction(roomId, action, {...payload, ...extra});
    } on GameServiceException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(gameStateProvider(roomId));
    final pending = stateAsync.value?.pendingAction?['type'] as String?;
    final config = ref.watch(roomConfigProvider(roomId)).value;
    final doublesEnabled = config?['doubles_enabled'] as bool? ?? true;
    final doublesExtraTurn = config?['doubles_extra_turn'] as bool? ?? true;
    final diceRoll = stateAsync.value?.diceRoll;
    final shouldRollAgain = doublesEnabled &&
        doublesExtraTurn &&
        diceRoll != null &&
        diceRoll.length >= 2 &&
        diceRoll.every((d) => d == diceRoll[0]) &&
        (stateAsync.value?.consecutiveDoubles ?? 0) > 0;
    final warmupLaps = (config?['warmup_laps'] as int?) ?? 0;
    final effectivePlayerId = debugActingAs ?? ref.watch(currentUserIdProvider) ?? '';
    final playerLaps = stateAsync.value?.lapsCompleted[effectivePlayerId] ?? 0;
    final inWarmup = warmupLaps > 0 && playerLaps < warmupLaps;

    return Container(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: switch (phase) {
        GamePhaseName.roll => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDebug) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: useForced,
                        onChanged: (v) => onDiceChanged?.call(forcedDie1, forcedDie2, v ?? false),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('Force dice:', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    _DieDropdown(
                      value: forcedDie1,
                      sides: (config?['dice_sides'] as int?) ?? 6,
                      onChanged: (v) => onDiceChanged?.call(v, forcedDie2, useForced),
                    ),
                    const SizedBox(width: 4),
                    _DieDropdown(
                      value: forcedDie2,
                      sides: (config?['dice_sides'] as int?) ?? 6,
                      onChanged: (v) => onDiceChanged?.call(forcedDie1, v, useForced),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _act(context, ref, GameAction.rollDice),
                      icon: const Icon(Icons.casino),
                      label: const Text('Roll Dice', softWrap: false, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: () => _showBuildSheet(context, ref),
                    icon: const Icon(Icons.house),
                    tooltip: 'Build',
                  ),
                  const SizedBox(width: 4),
                  IconButton.outlined(
                    onPressed: () => _showMortgageSheet(context, ref),
                    icon: const Icon(Icons.money),
                    tooltip: 'Mortgage',
                  ),
                  const SizedBox(width: 4),
                  IconButton.outlined(
                    onPressed: () => _showTradeOverlay(context, ref),
                    icon: const Icon(Icons.swap_horiz),
                    tooltip: 'Trade',
                  ),
                ],
              ),
            ],
          ),
        GamePhaseName.action when pending == GamePendingType.purchaseDecision => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (inWarmup)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Warm-up laps: $playerLaps/$warmupLaps -- buying unlocks after',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: inWarmup
                          ? null
                          : () => _act(context, ref, GameAction.buyProperty),
                      child: const Text('Buy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _act(context, ref, GameAction.declineProperty),
                      child: const Text('Decline'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        GamePhaseName.auction => _AuctionBar(
            roomId: roomId,
            onAct: (action, payload) => _act(context, ref, action, payload),
          ),
        GamePhaseName.trade => Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _act(context, ref, GameAction.endTurn),
                  child: Text(shouldRollAgain ? 'Roll Again' : 'End Turn', softWrap: false, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: () => _showBuildSheet(context, ref),
                icon: const Icon(Icons.house),
                tooltip: 'Build',
              ),
              const SizedBox(width: 4),
              IconButton.outlined(
                onPressed: () => _showMortgageSheet(context, ref),
                icon: const Icon(Icons.money),
                tooltip: 'Mortgage',
              ),
              const SizedBox(width: 4),
              IconButton.outlined(
                onPressed: () => _showTradeOverlay(context, ref),
                icon: const Icon(Icons.swap_horiz),
                tooltip: 'Trade',
              ),
            ],
          ),
        GamePhaseName.bankruptcyNegotiation => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('You cannot pay your debt', style: TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => _act(context, ref, GameAction.declareBankruptcy),
                child: const Text('Declare Bankruptcy', softWrap: false, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  void _showBuildSheet(BuildContext context, WidgetRef ref) {
    final effectiveId = debugActingAs ?? ref.read(currentUserIdProvider) ?? '';
    onActiveSheetChanged?.call('build');
    showModalBottomSheet(
      context: context,
      builder: (_) => GameBuildSheet(
        roomId: roomId,
        effectivePlayerId: effectiveId,
        onAct: (action, payload) => _act(context, ref, action, payload),
      ),
    ).whenComplete(() => onActiveSheetChanged?.call(null));
  }

  void _showMortgageSheet(BuildContext context, WidgetRef ref) {
    final effectiveId = debugActingAs ?? ref.read(currentUserIdProvider) ?? '';
    onActiveSheetChanged?.call('mortgage');
    showModalBottomSheet(
      context: context,
      builder: (_) => GameMortgageSheet(
        roomId: roomId,
        effectivePlayerId: effectiveId,
        onAct: (action, payload) => _act(context, ref, action, payload),
      ),
    ).whenComplete(() => onActiveSheetChanged?.call(null));
  }

  void _showTradeOverlay(BuildContext context, WidgetRef ref) {
    final myId = ref.read(currentUserIdProvider) ?? '';
    final effectiveId = debugActingAs ?? myId;
    onActiveSheetChanged?.call('trade');
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, __) => TradeOverlay(
        roomId: roomId,
        myId: myId,
        effectivePlayerId: effectiveId,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    ).whenComplete(() => onActiveSheetChanged?.call(null));
  }
}

class _DieDropdown extends StatelessWidget {
  const _DieDropdown({required this.value, required this.sides, required this.onChanged});
  final int value;
  final int sides;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: value,
      isDense: true,
      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
      items: List.generate(
        sides,
        (i) => DropdownMenuItem(
          value: i + 1,
          child: Text('${i + 1}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
        ),
      ),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _AuctionBar extends ConsumerStatefulWidget {
  const _AuctionBar({required this.roomId, required this.onAct});
  final String roomId;
  final Future<void> Function(String action, Map<String, dynamic> payload) onAct;

  @override
  ConsumerState<_AuctionBar> createState() => _AuctionBarState();
}

class _AuctionBarState extends ConsumerState<_AuctionBar> {
  final _controller = TextEditingController();
  int? _lastCurrentPrice;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameStateProvider(widget.roomId)).value;
    final players = ref.watch(roomPlayersProvider(widget.roomId)).value ?? [];
    final auction = state?.activeAuction;
    if (auction == null) return const SizedBox.shrink();

    final currentPrice = (auction['current_price'] as int?) ?? 0;
    final leaderId = auction['current_leader'] as String?;
    final currentBidder = auction['current_bidder'] as String?;

    String playerName(String? id) => id == null
        ? 'Unknown'
        : players.where((p) => p.playerId == id).firstOrNull?.displayName ?? 'Unknown';

    if (_lastCurrentPrice != currentPrice) {
      _lastCurrentPrice = currentPrice;
      _controller.text = '${currentPrice + 1}';
    }

    final bidderBalance = currentBidder != null ? (state?.balances[currentBidder] ?? 0) : 0;
    final minBid = currentPrice + 1;
    final canAffordBid = bidderBalance >= minBid;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (currentBidder != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              "${playerName(currentBidder)}'s turn to bid",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Current bid: £$currentPrice${leaderId != null ? ' — ${playerName(leaderId)} leads' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        if (currentBidder != null)
          Text(
            'Budget: £$bidderBalance',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        const SizedBox(height: 8),
        if (canAffordBid)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixText: '£',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    widget.onAct(GameAction.bid, {'amount': int.tryParse(_controller.text) ?? 0}),
                child: const Text('Bid'),
              ),
              const SizedBox(width: 4),
              OutlinedButton(
                onPressed: () => widget.onAct(GameAction.passBid, {}),
                child: const Text('Pass'),
              ),
            ],
          )
        else
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Insufficient funds',
                  style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => widget.onAct(GameAction.passBid, {}),
                child: const Text('Pass'),
              ),
            ],
          ),
      ],
    );
  }
}
