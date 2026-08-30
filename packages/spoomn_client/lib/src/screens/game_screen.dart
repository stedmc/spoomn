import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../game/spoomn_game.dart';
import '../providers/providers.dart';
import '../services/game_service.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> with WidgetsBindingObserver {
  late final SpoomnGame _game;
  bool _showReveal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = SpoomnGame(roomId: widget.roomId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Force fresh REST fetch so we get the current DB state (e.g. debug_mode
      // set in the lobby) rather than the potentially stale cached value from
      // the lobby's stream (which may have errored before the update arrived).
      ref.invalidate(roomConfigProvider(widget.roomId));
      _connect();
      _applyCurrentPlayerColours();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _connect();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _disconnect();
      default:
        break;
    }
  }

  void _applyCurrentPlayerColours() {
    if (!mounted) return;
    final players = ref.read(roomPlayersProvider(widget.roomId)).valueOrNull;
    if (players == null) return;
    _game.setPlayerTokenColours({
      for (final p in players) p.playerId: SpoomnGame.tokenColourToColor(p.tokenColour),
    });
    _game.setPlayerNames({
      for (final p in players) p.playerId: p.displayName ?? 'Guest',
    });
  }

  Future<void> _connect() async {
    try {
      await ref.read(gameServiceProvider).connect(widget.roomId);
    } catch (_) {}
  }

  Future<void> _disconnect() async {
    try {
      await ref.read(gameServiceProvider).disconnect(widget.roomId);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(gameStateProvider(widget.roomId), (_, next) {
      next.whenData(_game.onStateUpdate);
    });
    ref.listen(activeTrapsProvider(widget.roomId), (_, next) {
      next.whenData(_game.onTrapsUpdate);
    });
    ref.listen(gameRoomProvider(widget.roomId), (prev, next) {
      next.whenData((room) {
        if (room.status == GameRoomStatus.finished && context.mounted) {
          context.go('/game-over/${widget.roomId}');
        }
        final prevRoom = prev?.valueOrNull;
        if (room.status == GameRoomStatus.active &&
            prevRoom?.status == GameRoomStatus.starting) {
          setState(() => _showReveal = true);
        }
      });
    });
    ref.listen(roomPlayersProvider(widget.roomId), (_, next) {
      next.whenData((players) {
        _game.setPlayerTokenColours({
          for (final p in players) p.playerId: SpoomnGame.tokenColourToColor(p.tokenColour),
        });
        _game.setPlayerNames({
          for (final p in players) p.playerId: p.displayName ?? 'Guest',
        });
      });
    });

    final room = ref.watch(gameRoomProvider(widget.roomId)).valueOrNull;
    final isStarting = room?.status == GameRoomStatus.starting;

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(child: GameWidget(game: _game)),
              SizedBox(
                width: 280,
                child: _SidePanel(roomId: widget.roomId, game: _game),
              ),
            ],
          ),
          if (isStarting) _StartGameOverlay(roomId: widget.roomId),
          if (_showReveal)
            _OrderRevealOverlay(
              roomId: widget.roomId,
              onDismiss: () => setState(() => _showReveal = false),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SidePanel extends ConsumerStatefulWidget {
  const _SidePanel({required this.roomId, required this.game});
  final String roomId;
  final SpoomnGame game;

  @override
  ConsumerState<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends ConsumerState<_SidePanel> {
  String? _actingAs;
  bool _useForced = false;
  int _forcedDie1 = 1;
  int _forcedDie2 = 1;

  @override
  Widget build(BuildContext context) {
    final isDebug = ref.watch(isDebugModeProvider(widget.roomId));
    final isMyTurn = ref.watch(isMyTurnProvider(widget.roomId));
    final myId = ref.watch(currentUserIdProvider);
    final room = ref.watch(gameRoomProvider(widget.roomId)).valueOrNull;
    final players = ref.watch(roomPlayersProvider(widget.roomId)).valueOrNull ?? [];
    final stateAsync = ref.watch(gameStateProvider(widget.roomId));
    // Show Roll Dice immediately while state is loading — server validates phase on every action.
    final phase = stateAsync.valueOrNull?.phase.name ?? (stateAsync.isLoading ? 'roll' : null);
    final auctionBidder = stateAsync.valueOrNull?.activeAuction?['current_bidder'] as String?;
    final isMyAuctionTurn = phase == 'auction' && auctionBidder == myId;

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
      if (state.phase == GamePhase.auction &&
          ref.read(isDebugModeProvider(widget.roomId))) {
        final bidder = state.activeAuction?['current_bidder'] as String?;
        if (bidder != null && _actingAs != bidder) {
          setState(() => _actingAs = bidder);
        }
      }
      final prevState = prev?.valueOrNull;
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
          SafeArea(bottom: false, child: _PlayerStrip(roomId: widget.roomId, game: widget.game)),
          const Divider(height: 1),
          _StatusBanner(roomId: widget.roomId),
          const Divider(height: 1),
          if (isDebug) ...[
            _DebugPanel(
              roomId: widget.roomId,
              players: players,
              actingAs: effectiveActingAs,
              onActingAsChanged: (v) => setState(() => _actingAs = v),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: _SquareHoverCard(roomId: widget.roomId, game: widget.game),
          ),
          if (isDebug || isMyTurn || isMyAuctionTurn) ...[
            const Divider(height: 1),
            if (phase == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: _ActionBar(
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
                ),
              ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StartGameOverlay extends ConsumerStatefulWidget {
  const _StartGameOverlay({required this.roomId});
  final String roomId;

  @override
  ConsumerState<_StartGameOverlay> createState() => _StartGameOverlayState();
}

class _StartGameOverlayState extends ConsumerState<_StartGameOverlay> {
  bool _starting = false;
  bool? _pendingDebugMode;

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

  Future<void> _setDebugMode(bool enabled) async {
    setState(() => _pendingDebugMode = enabled);
    try {
      await ref.read(gameServiceProvider).setDebugMode(widget.roomId, enabled: enabled);
    } on GameServiceException catch (e) {
      setState(() => _pendingDebugMode = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(gameRoomProvider(widget.roomId)).valueOrNull;
    final myId = ref.watch(currentUserIdProvider);
    final isHost = room?.hostId == myId;
    final playerCount = room?.playerCount ?? 0;
    final configAsync = ref.watch(roomConfigProvider(widget.roomId));
    final streamDebugMode = configAsync.valueOrNull?['debug_mode'] as bool? ?? false;
    if (_pendingDebugMode != null && _pendingDebugMode == streamDebugMode) {
      Future.microtask(() => setState(() => _pendingDebugMode = null));
    }
    final debugMode = _pendingDebugMode ?? streamDebugMode;

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
                if (isHost) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: debugMode,
                    onChanged: _starting ? null : (v) => _setDebugMode(v),
                    title: const Text('Debug mode'),
                    secondary: const Icon(Icons.bug_report),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
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

// ---------------------------------------------------------------------------

class _OrderRevealOverlay extends ConsumerStatefulWidget {
  const _OrderRevealOverlay({required this.roomId, required this.onDismiss});
  final String roomId;
  final VoidCallback onDismiss;

  @override
  ConsumerState<_OrderRevealOverlay> createState() => _OrderRevealOverlayState();
}

class _OrderRevealOverlayState extends ConsumerState<_OrderRevealOverlay> {
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Play Order',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: widget.onDismiss,
                      tooltip: 'Close',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DebugPanel extends ConsumerStatefulWidget {
  const _DebugPanel({
    required this.roomId,
    required this.players,
    required this.actingAs,
    required this.onActingAsChanged,
  });

  final String roomId;
  final List<RoomPlayer> players;
  final String actingAs;
  final ValueChanged<String?> onActingAsChanged;

  @override
  ConsumerState<_DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends ConsumerState<_DebugPanel> {
  String? _teleportTarget;
  final _squareController = TextEditingController(text: '0');

  @override
  void dispose() {
    _squareController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _teleportTarget ??= widget.actingAs;

    return Container(
      color: Colors.orange.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.bug_report, size: 13, color: Colors.deepOrange),
              SizedBox(width: 4),
              Text('Debug Mode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
            ],
          ),
          const SizedBox(height: 6),

          // Acting as
          Row(
            children: [
              const Text('Acting as:', style: TextStyle(fontSize: 12, color: Colors.black87)),
              const SizedBox(width: 6),
              Expanded(
                child: _debugDropdown<String>(
                  value: widget.actingAs.isEmpty ? null : widget.actingAs,
                  items: widget.players.map((p) => DropdownMenuItem(
                    value: p.playerId,
                    child: Text(p.displayName ?? 'Guest', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  )).toList(),
                  onChanged: widget.onActingAsChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Teleport
          Row(
            children: [
              const Text('Move:', style: TextStyle(fontSize: 12, color: Colors.black87)),
              const SizedBox(width: 6),
              Expanded(
                child: _debugDropdown<String>(
                  value: (_teleportTarget?.isEmpty ?? true) ? null : _teleportTarget,
                  items: widget.players.map((p) => DropdownMenuItem(
                    value: p.playerId,
                    child: Text(p.displayName ?? 'Guest', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  )).toList(),
                  onChanged: (v) => setState(() => _teleportTarget = v),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 44,
                child: TextField(
                  controller: _squareController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  cursorColor: Colors.black87,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    border: OutlineInputBorder(),
                    hintText: '0-39',
                    hintStyle: TextStyle(color: Colors.black45),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 30,
                child: FilledButton(
                  onPressed: _teleport,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Go', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _teleport() async {
    final sq = int.tryParse(_squareController.text);
    if (sq == null || sq < 0 || sq > 39) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Square must be 0–39')),
      );
      return;
    }
    try {
      await ref.read(gameServiceProvider).submitAction(
        widget.roomId,
        'debug_teleport',
        {'player_id': _teleportTarget ?? widget.actingAs, 'square': sq},
      );
    } on GameServiceException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  DropdownButton<T> _debugDropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        dropdownColor: Colors.white,
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        items: items,
        onChanged: onChanged,
      );
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
      dropdownColor: Colors.white,
      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
      items: List.generate(
        sides,
        (i) => DropdownMenuItem(
          value: i + 1,
          child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ),
      ),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _PlayerStrip extends ConsumerStatefulWidget {
  const _PlayerStrip({required this.roomId, required this.game});
  final String roomId;
  final SpoomnGame game;

  @override
  ConsumerState<_PlayerStrip> createState() => _PlayerStripState();
}

class _PlayerStripState extends ConsumerState<_PlayerStrip> {
  final Map<String, int> _balanceDeltas = {};
  final Map<String, Timer> _deltaTimers = {};

  @override
  void dispose() {
    for (final t in _deltaTimers.values) {
      t.cancel();
    }
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
    final state = ref.watch(gameStateProvider(widget.roomId)).valueOrNull;
    final room = ref.watch(gameRoomProvider(widget.roomId)).valueOrNull;

    ref.listen(gameStateProvider(widget.roomId), (prev, next) {
      if (prev == null) return;
      prev.whenData((prevState) {
        next.whenData((nextState) {
          final currentPlayers =
              ref.read(roomPlayersProvider(widget.roomId)).valueOrNull ?? [];
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
                tileColor: (isActive || isGameHovered)
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                onTap: () => widget.game.lockHighlightForPlayer(p.playerId),
                leading: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: playerColour,
                    border: Border.all(
                      color: p.isConnected
                          ? Colors.white54
                          : Colors.grey.shade600,
                      width: 1.5,
                    ),
                  ),
                ),
                title: Text(
                  p.displayName ?? 'Guest',
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
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

// ---------------------------------------------------------------------------

class _StatusBanner extends ConsumerWidget {
  const _StatusBanner({required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(roomId)).valueOrNull;
    final room = ref.watch(gameRoomProvider(roomId)).valueOrNull;
    final players = ref.watch(roomPlayersProvider(roomId)).valueOrNull ?? [];

    if (state == null || room == null) return const SizedBox.shrink();

    String playerName(String? id) => id == null
        ? 'Unknown'
        : (players.where((p) => p.playerId == id).firstOrNull?.displayName ??
            'Unknown');

    final messages = <({String text, Color color})>[];

    final currentName = playerName(room.currentPlayerId);
    messages.add((text: "$currentName's turn", color: Theme.of(context).colorScheme.onSurface));

    final pending = state.pendingAction;
    if (pending?['type'] == 'rent_payment') {
      final amount = pending!['amount'] as int? ?? 0;
      final ownerName = playerName(pending['owner_id'] as String?);
      messages.add((
        text: '£$amount rent owed to $ownerName',
        color: Colors.orangeAccent,
      ));
    }

    if (state.phase == GamePhase.trade) {
      messages.add((
        text: '$currentName is trading',
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

// ---------------------------------------------------------------------------

class _ActionBar extends ConsumerWidget {
  const _ActionBar({
    required this.roomId,
    required this.phase,
    this.debugActingAs,
    this.forcedRoll,
    this.isDebug = false,
    this.useForced = false,
    this.forcedDie1 = 1,
    this.forcedDie2 = 1,
    this.onDiceChanged,
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

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final extra = <String, dynamic>{};
    if (debugActingAs != null) extra['debug_as'] = debugActingAs;
    if (forcedRoll != null && action == 'roll_dice') extra['forced_roll'] = forcedRoll;
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
    final pending = stateAsync.valueOrNull?.pendingAction?['type'] as String?;

    return Container(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: switch (phase) {
        'roll' => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDebug) ...[
                Builder(builder: (context) {
                  final config = ref.watch(roomConfigProvider(roomId)).valueOrNull;
                  final diceSides = (config?['dice_sides'] as int?) ?? 6;
                  return Row(
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
                        sides: diceSides,
                        onChanged: (v) => onDiceChanged?.call(v, forcedDie2, useForced),
                      ),
                      const SizedBox(width: 4),
                      _DieDropdown(
                        value: forcedDie2,
                        sides: diceSides,
                        onChanged: (v) => onDiceChanged?.call(forcedDie1, v, useForced),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: () => _act(context, ref, 'roll_dice'),
                icon: const Icon(Icons.casino),
                label: const Text('Roll Dice'),
              ),
            ],
          ),
        'action' when pending == 'purchase_decision' => Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _act(context, ref, 'buy_property'),
                  child: const Text('Buy'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _act(context, ref, 'decline_property'),
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        'auction' => _AuctionBar(
            roomId: roomId,
            onAct: (action, payload) => _act(context, ref, action, payload),
          ),
        'trade' => Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _act(context, ref, 'end_turn'),
                  child: const Text('End Turn'),
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
            ],
          ),
        'bankruptcyNegotiation' => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('You cannot pay your debt', style: TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => _act(context, ref, 'declare_bankruptcy'),
                child: const Text('Declare Bankruptcy'),
              ),
            ],
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  void _showBuildSheet(BuildContext context, WidgetRef ref) {
    final effectiveId = debugActingAs ?? ref.read(currentUserIdProvider) ?? '';
    showModalBottomSheet(
      context: context,
      builder: (_) => _BuildSheet(
        roomId: roomId,
        effectivePlayerId: effectiveId,
        onAct: (action, payload) => _act(context, ref, action, payload),
      ),
    );
  }

  void _showMortgageSheet(BuildContext context, WidgetRef ref) {
    final effectiveId = debugActingAs ?? ref.read(currentUserIdProvider) ?? '';
    showModalBottomSheet(
      context: context,
      builder: (_) => _MortgageSheet(
        roomId: roomId,
        effectivePlayerId: effectiveId,
        onAct: (action, payload) => _act(context, ref, action, payload),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

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
    final state = ref.watch(gameStateProvider(widget.roomId)).valueOrNull;
    final players = ref.watch(roomPlayersProvider(widget.roomId)).valueOrNull ?? [];
    final auction = state?.activeAuction;
    if (auction == null) return const SizedBox.shrink();

    final currentPrice = (auction['current_price'] as int?) ?? 0;
    final leaderId = auction['current_leader'] as String?;
    final currentBidder = auction['current_bidder'] as String?;

    String playerName(String? id) => id == null
        ? 'Unknown'
        : players.where((p) => p.playerId == id).firstOrNull?.displayName ?? 'Unknown';

    // Reset suggested bid whenever current_price changes
    if (_lastCurrentPrice != currentPrice) {
      _lastCurrentPrice = currentPrice;
      _controller.text = '${currentPrice + 1}';
    }

    final bidderBalance = currentBidder != null ? (state?.balances[currentBidder] ?? 0) : 0;

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
              onPressed: () => widget.onAct('bid', {'amount': int.tryParse(_controller.text) ?? 0}),
              child: const Text('Bid'),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: () => widget.onAct('pass_bid', {}),
              child: const Text('Pass'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _BuildSheet extends ConsumerWidget {
  const _BuildSheet({
    required this.roomId,
    required this.effectivePlayerId,
    required this.onAct,
  });
  final String roomId;
  final String effectivePlayerId;
  final Future<void> Function(String, Map<String, dynamic>) onAct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(roomId)).valueOrNull;
    if (state == null) return const SizedBox.shrink();

    final owned = state.propertyOwnership.entries
        .where((e) => e.value == effectivePlayerId)
        .map((e) => int.tryParse(e.key))
        .whereType<int>()
        .where((idx) => Board.squares[idx].type == SquareType.property)
        .toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Build / Sell', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (owned.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No buildable properties.', style: TextStyle(color: Colors.grey)),
          ),
        ...owned.map((idx) {
          final sq = Board.squares[idx];
          final houses = state.houses['$idx'] ?? 0;
          final hasHotel = state.hotels['$idx'] == true;
          final colour = _groupColour(sq.colourGroup);

          final groupIndices = sq.colourGroup != null
              ? (Board.colourGroups[sq.colourGroup] ?? <int>[])
              : <int>[];
          final groupComplete = groupIndices.isNotEmpty &&
              groupIndices.every(
                  (gi) => state.propertyOwnership['$gi'] == effectivePlayerId);
          final isMortgaged = state.mortgaged.contains(idx);
          final canBuild = groupComplete && !isMortgaged;

          final statusText = hasHotel
              ? 'Hotel'
              : houses > 0
                  ? '$houses house${houses == 1 ? '' : 's'}'
                  : 'No buildings';
          final costText = !hasHotel && sq.houseCost != null
              ? '  ·  £${houses < 4 ? sq.houseCost : sq.hotelCost} to build next'
              : '';

          return Opacity(
            opacity: canBuild ? 1.0 : 0.45,
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: colour != null
                    ? Container(
                        width: 12,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colour,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    : const SizedBox(width: 12),
                title: Text(sq.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  '$statusText$costText',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: !canBuild
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (houses > 0)
                            TextButton(
                              onPressed: () => onAct('sell_house', {'square': idx}),
                              child: const Text('-House'),
                            ),
                          if (hasHotel)
                            TextButton(
                              onPressed: () => onAct('sell_hotel', {'square': idx}),
                              child: const Text('-Hotel'),
                            ),
                          if (!hasHotel && houses < 4)
                            TextButton(
                              onPressed: () => onAct('build_house', {'square': idx}),
                              child: const Text('+House'),
                            ),
                          if (houses == 4 && !hasHotel)
                            TextButton(
                              onPressed: () => onAct('build_hotel', {'square': idx}),
                              child: const Text('+Hotel'),
                            ),
                        ],
                      ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SquareHoverCard extends ConsumerWidget {
  const _SquareHoverCard({required this.roomId, required this.game});
  final String roomId;
  final SpoomnGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(roomId)).valueOrNull;
    final players = ref.watch(roomPlayersProvider(roomId)).valueOrNull ?? [];
    final isDebug = ref.watch(isDebugModeProvider(roomId));

    return ListenableBuilder(
      listenable: Listenable.merge([game.hoveredSquare, game.tappedSquare]),
      builder: (context, _) {
        final squareIndex = game.hoveredSquare.value ?? game.tappedSquare.value;
        if (squareIndex == null) return const SizedBox.shrink();
        final square = Board.squares[squareIndex];
        final ownerId = state?.propertyOwnership['$squareIndex'];
        final ownerColour = ownerId != null ? game.playerColours[ownerId] : null;
        final ownerName = ownerId != null
            ? (players.where((p) => p.playerId == ownerId).firstOrNull?.displayName ?? 'Unknown')
            : null;
        final houseCount = state?.houses['$squareIndex'] ?? 0;
        final hasHotel = state?.hotels['$squareIndex'] ?? false;

        return Align(
          alignment: Alignment.topRight,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _PropertyCard(square: square, ownerName: ownerName, ownerColour: ownerColour, houseCount: houseCount, hasHotel: hasHotel),
                if (isDebug && square.price != null) ...[
                  const SizedBox(height: 8),
                  _DebugAssignCard(
                    roomId: roomId,
                    squareIndex: squareIndex,
                    players: players,
                    currentOwner: ownerId,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DebugAssignCard extends ConsumerStatefulWidget {
  const _DebugAssignCard({
    required this.roomId,
    required this.squareIndex,
    required this.players,
    this.currentOwner,
  });
  final String roomId;
  final int squareIndex;
  final List<RoomPlayer> players;
  final String? currentOwner;

  @override
  ConsumerState<_DebugAssignCard> createState() => _DebugAssignCardState();
}

class _DebugAssignCardState extends ConsumerState<_DebugAssignCard> {
  String? _selected;

  @override
  void didUpdateWidget(_DebugAssignCard old) {
    super.didUpdateWidget(old);
    if (old.squareIndex != widget.squareIndex || old.currentOwner != widget.currentOwner) {
      _selected = widget.currentOwner;
    }
  }

  @override
  Widget build(BuildContext context) {
    _selected ??= widget.currentOwner;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Assign owner',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String?>(
                    value: _selected,
                    isExpanded: true,
                    isDense: true,
                    dropdownColor: Colors.white,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Unowned', style: TextStyle(fontSize: 12, color: Colors.black87))),
                      ...widget.players.map((p) => DropdownMenuItem(
                            value: p.playerId,
                            child: Text(p.displayName ?? 'Guest', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selected = v),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 30,
                  child: FilledButton(
                    onPressed: _assign,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Assign', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assign() async {
    try {
      await ref.read(gameServiceProvider).submitAction(
        widget.roomId,
        'debug_assign_property',
        {'square': widget.squareIndex, 'player_id': _selected},
      );
    } on GameServiceException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({
    required this.square,
    this.ownerName,
    this.ownerColour,
    this.houseCount = 0,
    this.hasHotel = false,
  });
  final BoardSquare square;
  final String? ownerName;
  final Color? ownerColour;
  final int houseCount;
  final bool hasHotel;

  @override
  Widget build(BuildContext context) {
    final colour = _groupColour(square.colourGroup);
    final activeRentIndex = hasHotel ? 5 : houseCount.clamp(0, 4);

    final card = Card(
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      shape: ownerColour != null
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: ownerColour!, width: 2),
            )
          : null,
      child: SizedBox(
        width: 180,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (colour != null) Container(height: 24, color: colour),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(square.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  if (square.price != null) Text('Price: £${square.price}'),
                  if (square.mortgageValue != null) Text('Mortgage: £${square.mortgageValue}'),
                  if (square.houseCost != null) ...[
                    Text('House: £${square.houseCost}'),
                    Text('Hotel: £${square.hotelCost}'),
                  ],
                  if (square.rent != null) ...[
                    const Divider(),
                    const Text('Rent', style: TextStyle(fontWeight: FontWeight.w600)),
                    _rentRow('Base', square.rent![0], isActive: activeRentIndex == 0),
                    const Text('x2 if full set owned', style: TextStyle(fontSize: 9, color: Colors.grey, fontStyle: FontStyle.italic)),
                    _rentRow('1 House', square.rent![1], isActive: activeRentIndex == 1),
                    _rentRow('2 Houses', square.rent![2], isActive: activeRentIndex == 2),
                    _rentRow('3 Houses', square.rent![3], isActive: activeRentIndex == 3),
                    _rentRow('4 Houses', square.rent![4], isActive: activeRentIndex == 4),
                    _rentRow('Hotel', square.rent![5], isActive: activeRentIndex == 5),
                  ],
                  if (square.type == SquareType.station) ...[
                    const Divider(),
                    const Text('Rent', style: TextStyle(fontWeight: FontWeight.w600)),
                    _rentRow('1 Station', 25),
                    _rentRow('2 Stations', 50),
                    _rentRow('3 Stations', 100),
                    _rentRow('4 Stations', 200),
                  ],
                  if (square.type == SquareType.utility) ...[
                    const Divider(),
                    const Text('Rent', style: TextStyle(fontWeight: FontWeight.w600)),
                    _textRow('1 Utility', '4× dice'),
                    _textRow('2 Utilities', '10× dice'),
                  ],
                  if (square.taxAmount != null) Text('Tax: £${square.taxAmount}'),
                  if (square.price == null && square.taxAmount == null)
                    Text(square.type.name, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (ownerName == null || ownerColour == null) return card;

    // Tab height ~22px; card offset by (tabHeight - 2) so tab overlaps card top by 2px,
    // covering the border join and making them look physically connected.
    const tabHeight = 22.0;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(padding: const EdgeInsets.only(top: tabHeight - 2), child: card),
        Positioned(
          top: 2,
          child: Container(
            height: tabHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ownerColour,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              'Owned by $ownerName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _rentRow(String label, int amount, {bool isActive = false}) {
    final textStyle = TextStyle(
      fontSize: 11,
      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
      color: isActive ? Colors.green.shade800 : null,
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textStyle),
          Text('£$amount', style: textStyle),
        ],
      ),
    );
    if (!isActive) return row;
    return Container(
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(3),
      ),
      child: row,
    );
  }

  Widget _textRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 11)),
            Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      );

}

// ---------------------------------------------------------------------------

class _MortgageSheet extends ConsumerWidget {
  const _MortgageSheet({
    required this.roomId,
    required this.effectivePlayerId,
    required this.onAct,
  });
  final String roomId;
  final String effectivePlayerId;
  final Future<void> Function(String, Map<String, dynamic>) onAct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(roomId)).valueOrNull;
    if (state == null) return const SizedBox.shrink();

    final owned = state.propertyOwnership.entries
        .where((e) => e.value == effectivePlayerId)
        .map((e) => int.tryParse(e.key))
        .whereType<int>()
        .toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Mortgage / Unmortgage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (owned.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No properties owned.', style: TextStyle(color: Colors.grey)),
          ),
        ...owned.map((idx) {
          final sq = Board.squares[idx];
          final colour = _groupColour(sq.colourGroup);
          final isMortgaged = state.mortgaged.contains(idx);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: colour != null
                  ? Container(
                      width: 12,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colour,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )
                  : const SizedBox(width: 12),
              title: Text(sq.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                isMortgaged
                    ? 'Mortgaged  ·  £${sq.mortgageValue} to unmortgage'
                    : 'Unmortgaged  ·  £${sq.mortgageValue} value',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: isMortgaged
                  ? TextButton(
                      onPressed: () => onAct('unmortgage_property', {'square': idx}),
                      child: const Text('Unmortgage'),
                    )
                  : TextButton(
                      onPressed: () => onAct('mortgage_property', {'square': idx}),
                      child: const Text('Mortgage'),
                    ),
            ),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

Color? _groupColour(String? group) => switch (group) {
  'brown'     => const Color(0xFF955436),
  'lightBlue' => const Color(0xFFAAE0FA),
  'pink'      => const Color(0xFFD93A96),
  'orange'    => const Color(0xFFF7941D),
  'red'       => const Color(0xFFED1B24),
  'yellow'    => const Color(0xFFFEF200),
  'green'     => const Color(0xFF1FB25A),
  'darkBlue'  => const Color(0xFF0072BB),
  _           => null,
};
