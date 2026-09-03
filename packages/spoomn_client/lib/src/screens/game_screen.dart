import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../game/spoomn_game.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import '../services/game_service.dart';
import '../widgets/game/card_draw_overlay.dart';
import '../widgets/game/game_constants.dart';
import '../widgets/game/game_toast.dart';
import '../widgets/game/order_reveal_overlay.dart';
import '../widgets/game/property_card.dart';
import '../widgets/game/side_panel.dart';
import '../widgets/game/start_game_overlay.dart';
import '../widgets/game/trade_overlay.dart';
import '../widgets/game/turn_indicator.dart';

enum _MovePhase {
  idle,
  diceAnimating,
  tokenMoving,
  cardShowing,
  cardMoveWaiting,
  cardTokenMoving,
  cardHoldAfterMove,
}

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> with WidgetsBindingObserver {
  late final SpoomnGame _game;
  bool _showReveal = false;
  bool _showCardDraw = false;
  bool _showEndGameOverlay = false;
  String? _endGameWinnerId;
  Map<String, dynamic>? _cardDrawEntry;
  String? _lastShownCardEntryId;
  String? _lastToastEntryId;
  final List<_ToastEntry> _toasts = [];
  Timer? _cardDismissTimer;
  Timer? _sequenceTimer;
  Timer? _tradeCloseTimer;
  Map<String, dynamic>? _activeTrade;
  bool _isAnimating = false;
  _MovePhase _movePhase = _MovePhase.idle;
  bool _diceComplete = false;
  bool _tokenComplete = false;

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
    _cardDismissTimer?.cancel();
    _sequenceTimer?.cancel();
    _tradeCloseTimer?.cancel();
    _game.onDiceAnimationComplete = null;
    _game.onTokenAnimationComplete = null;
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
    ref.listen(gameLogProvider(widget.roomId), (_, next) {
      next.whenData((entries) {
        if (entries.isEmpty) return;
        final top = entries.first;
        final id = top['id']?.toString();

        debugPrint('[GameLog] action=${top['action']} id=$id');

        if (top['action'] == GameAction.rollDice && !_isAnimating) {
          _beginRollSequence(top);
        } else if (top['action'] == GameAction.drawCard) {
          _handleCardDraw(top);
        }

        if (id != null && id != _lastToastEntryId) {
          _lastToastEntryId = id;
          final msg = _formatToast(top);
          if (msg != null) setState(() => _toasts.add(_ToastEntry(msg)));
        }
      });
    });
    ref.listen(activeTrapsProvider(widget.roomId), (_, next) {
      next.whenData(_game.onTrapsUpdate);
    });
    ref.listen(gameRoomProvider(widget.roomId), (prev, next) {
      next.whenData((room) {
        if (room.status == GameRoomStatus.finished && context.mounted && !_showEndGameOverlay) {
          final players = ref.read(roomPlayersProvider(widget.roomId)).valueOrNull ?? [];
          final state = ref.read(gameStateProvider(widget.roomId)).valueOrNull;
          final active = players.where((p) => !p.isBankrupt).toList()
            ..sort((a, b) {
              final balA = state?.balances[a.playerId] ?? 0;
              final balB = state?.balances[b.playerId] ?? 0;
              return balB.compareTo(balA);
            });
          setState(() {
            _showEndGameOverlay = true;
            _endGameWinnerId = active.isNotEmpty ? active.first.playerId : null;
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (context.mounted) context.go('/game-over/${widget.roomId}');
          });
        }
        final prevRoom = prev?.valueOrNull;
        if (room.status == GameRoomStatus.active &&
            prevRoom?.status == GameRoomStatus.starting) {
          setState(() => _showReveal = true);
        }
        if (prevRoom?.currentPlayerId != null &&
            prevRoom?.currentPlayerId != room.currentPlayerId) {
          _cardDismissTimer?.cancel();
          setState(() {
            _showCardDraw = false;
            _isAnimating = false;
            _movePhase = _MovePhase.idle;
          });
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
    ref.listen(pendingTradesProvider(widget.roomId), (_, next) {
      next.whenData((trades) {
        if (trades.isNotEmpty) {
          _tradeCloseTimer?.cancel();
          setState(() => _activeTrade = trades.first);
        } else {
          // Debounce clearing to prevent flicker during counter trade transitions
          _tradeCloseTimer?.cancel();
          _tradeCloseTimer = Timer(const Duration(milliseconds: 400), () {
            if (mounted) setState(() => _activeTrade = null);
          });
        }
      });
    });
    ref.listen(boardFontSizeProvider, (_, size) {
      _game.setBoardFontSize(size);
    });
    ref.listen(roomConfigProvider(widget.roomId), (_, next) {
      next.whenData((config) {
        if (config == null) return;
        _game.setFreeParkingJackpot(config['free_parking_jackpot'] as bool? ?? false);
      });
    });

    final room = ref.watch(gameRoomProvider(widget.roomId)).valueOrNull;
    final isStarting = room?.status == GameRoomStatus.starting;
    final myId = ref.watch(currentUserIdProvider) ?? '';

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(child: GameWidget(game: _game)),
              SizedBox(
                width: 310,
                child: GameSidePanel(roomId: widget.roomId, game: _game, isAnimating: _isAnimating),
              ),
            ],
          ),
          // Turn indicator — top-left of board area
          Positioned(
            top: 12,
            left: 12,
            child: TurnIndicatorWidget(roomId: widget.roomId, game: _game),
          ),
          // Floating property card — near tap/hover position
          ListenableBuilder(
            listenable: Listenable.merge([_game.tappedSquare, _game.hoveredSquare, _game.squareTapAnchor]),
            builder: (context, _) {
              final squareIdx = _game.tappedSquare.value ?? _game.hoveredSquare.value;
              final anchor = _game.squareTapAnchor.value;
              if (squareIdx == null || anchor == null) return const SizedBox.shrink();
              const cardW = 220.0;
              const cardH = 360.0;
              final screenSize = MediaQuery.sizeOf(context);
              final popupPos = _smartPopupPos(anchor, cardW, cardH, screenSize);
              return Positioned(
                left: popupPos.dx,
                top: popupPos.dy,
                width: cardW,
                child: GameSquareHoverCard(roomId: widget.roomId, game: _game),
              );
            },
          ),
          // Toast notifications — centred over board area
          if (_toasts.isNotEmpty)
            Positioned(
              top: 72,
              left: 0,
              right: 310,
              child: Center(
                child: GameToastBanner(
                  key: _toasts.first.key,
                  message: _toasts.first.message,
                  onDone: () => setState(() => _toasts.removeAt(0)),
                ),
              ),
            ),
          if (isStarting) GameStartOverlay(roomId: widget.roomId),
          if (_showReveal)
            GameOrderRevealOverlay(
              roomId: widget.roomId,
              onDismiss: () => setState(() => _showReveal = false),
            ),
          if (_showCardDraw && _cardDrawEntry != null)
            CardDrawOverlay(
              entry: _cardDrawEntry!,
              onDismiss: () {
                _cardDismissTimer?.cancel();
                if (_movePhase == _MovePhase.cardMoveWaiting) {
                  setState(() => _movePhase = _MovePhase.cardTokenMoving);
                  _game.onTokenAnimationComplete = () {
                    _game.onTokenAnimationComplete = null;
                    if (!mounted) return;
                    setState(() => _movePhase = _MovePhase.cardHoldAfterMove);
                    _cardDismissTimer = Timer(const Duration(seconds: 2), () {
                      if (mounted) {
                        setState(() {
                          _showCardDraw = false;
                          _isAnimating = false;
                          _movePhase = _MovePhase.idle;
                        });
                      }
                    });
                  };
                } else {
                  setState(() {
                    _showCardDraw = false;
                    _isAnimating = false;
                    _movePhase = _MovePhase.idle;
                  });
                }
              },
            ),
          if (_activeTrade != null)
            TradeOverlay(
              roomId: widget.roomId,
              trade: _activeTrade!,
              myId: myId,
              effectivePlayerId: myId,
              onClose: () => setState(() => _activeTrade = null),
            ),
          if (_showEndGameOverlay)
            _EndGameOverlay(
              winnerId: _endGameWinnerId,
              roomId: widget.roomId,
            ),
        ],
      ),
    );
  }

  void _beginRollSequence(Map<String, dynamic> entry) {
    final payload = (entry['payload'] as Map<String, dynamic>?) ?? {};
    final noTokenMove = payload['failed_jail_roll'] == true ||
        payload['sent_to_jail'] == true ||
        payload['mandatory_turns_remaining'] != null;

    _sequenceTimer?.cancel();
    setState(() {
      _isAnimating = true;
      _movePhase = _MovePhase.diceAnimating;
      _diceComplete = false;
      _tokenComplete = noTokenMove;
    });

    _game.onDiceAnimationComplete = () {
      _game.onDiceAnimationComplete = null;
      if (!mounted) return;
      setState(() => _movePhase = _MovePhase.tokenMoving);
      _diceComplete = true;
      _checkAnimationsComplete();
    };

    if (!noTokenMove) {
      _game.onTokenAnimationComplete = () {
        _game.onTokenAnimationComplete = null;
        if (!mounted) return;
        _tokenComplete = true;
        _checkAnimationsComplete();
      };
    }
  }

  void _checkAnimationsComplete() {
    if (!_diceComplete || !_tokenComplete) return;
    if (!_showCardDraw) {
      setState(() {
        _isAnimating = false;
        _movePhase = _MovePhase.idle;
      });
    }
  }

  void _handleCardDraw(Map<String, dynamic> entry) {
    final id = entry['id']?.toString();
    if (id == null || id == _lastShownCardEntryId) return;
    _lastShownCardEntryId = id;
    _cardDismissTimer?.cancel();

    final effect = entry['payload']?['effect'] as Map<String, dynamic>?;
    final isMovementCard = effect != null &&
        ['move_to', 'move_relative', 'move_to_nearest'].contains(effect['type']);

    setState(() {
      _cardDrawEntry = entry;
      _showCardDraw = true;
      _movePhase = isMovementCard ? _MovePhase.cardMoveWaiting : _MovePhase.cardShowing;
    });

    if (isMovementCard) {
      _cardDismissTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _movePhase = _MovePhase.cardTokenMoving);
        _game.onTokenAnimationComplete = () {
          _game.onTokenAnimationComplete = null;
          if (!mounted) return;
          setState(() => _movePhase = _MovePhase.cardHoldAfterMove);
          _cardDismissTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _showCardDraw = false;
                _isAnimating = false;
                _movePhase = _MovePhase.idle;
              });
            }
          });
        };
      });
    } else {
      _cardDismissTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _showCardDraw = false;
            _isAnimating = false;
            _movePhase = _MovePhase.idle;
          });
        }
      });
    }
  }

  String? _formatToast(Map<String, dynamic> entry) {
    final action = entry['action'] as String?;
    final payload = (entry['payload'] as Map<String, dynamic>?) ?? {};
    final playerId = entry['player_id'] as String?;
    final players = ref.read(roomPlayersProvider(widget.roomId)).valueOrNull ?? [];
    final name = players.where((p) => p.playerId == playerId).firstOrNull?.displayName ?? 'Someone';

    return switch (action) {
      GameAction.rollDice => () {
          final roll = (payload['roll'] as List?)?.cast<int>() ?? [];
          final total = roll.fold(0, (a, b) => a + b);
          return '$name rolled ${roll.join(' + ')} = $total';
        }(),
      GameAction.buyProperty => () {
          final sq = payload['square'];
          final sqIdx = sq is int ? sq : int.tryParse('$sq');
          final sqName = sqIdx != null ? Board.squares[sqIdx].name : 'a property';
          return '$name bought $sqName';
        }(),
      GameAction.rentPayment => () {
          final amount = payload['amount'];
          return amount != null ? '$name paid £$amount rent' : null;
        }(),
      GameAction.drawCard => '$name drew a card',
      GameAction.goToJail => '$name was sent to Jail',
      GameAction.jailbreak => '$name broke out of Jail',
      GameAction.useGoojfCard => '$name used their Get Out of Jail Free card',
      _ => null,
    };
  }

  Offset _smartPopupPos(Offset anchor, double cardW, double cardH, Size screen) {
    final boardW = screen.width - 310;
    double left;
    if (anchor.dx + 16 + cardW > boardW) {
      left = (anchor.dx - cardW - 16).clamp(0.0, screen.width - cardW);
    } else {
      left = anchor.dx + 16;
    }
    double top;
    if (anchor.dy + cardH > screen.height - 20) {
      top = (anchor.dy - cardH - 8).clamp(0.0, screen.height - cardH);
    } else {
      top = (anchor.dy - 40).clamp(0.0, screen.height - cardH);
    }
    return Offset(left, top);
  }
}

class _ToastEntry {
  final String message;
  final UniqueKey key;
  _ToastEntry(this.message) : key = UniqueKey();
}

class _EndGameOverlay extends ConsumerStatefulWidget {
  const _EndGameOverlay({required this.winnerId, required this.roomId});
  final String? winnerId;
  final String roomId;

  @override
  ConsumerState<_EndGameOverlay> createState() => _EndGameOverlayState();
}

class _EndGameOverlayState extends ConsumerState<_EndGameOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(roomPlayersProvider(widget.roomId)).valueOrNull ?? [];
    final winner = players.where((p) => p.playerId == widget.winnerId).firstOrNull;
    final winnerName = winner?.displayName ?? 'Someone';

    return FadeTransition(
      opacity: _opacity,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏆', style: TextStyle(fontSize: 80)),
                const SizedBox(height: 16),
                Text(
                  '$winnerName wins!',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
