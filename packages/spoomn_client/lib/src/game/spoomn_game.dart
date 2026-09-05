import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:spoomn_core/spoomn_core.dart';

import '../providers/settings_provider.dart';
import 'components/board_component.dart';
import 'components/dice_component.dart';
import 'components/police_pawn_component.dart';
import 'components/token_component.dart';
import 'components/trap_component.dart';

class SpoomnGame extends FlameGame with MouseMovementDetector, TapCallbacks {
  SpoomnGame({required this.roomId});

  final String roomId;

  late BoardComponent board;
  late DiceComponent dice;

  // Pending flags handle the race where a Supabase state update arrives and
  // triggers an animation BEFORE the game_log entry fires _beginRollSequence
  // and registers the completion callbacks. If a callback is null when the
  // animation fires, the flag is set so the callback fires as soon as it is
  // registered (which happens synchronously in _beginRollSequence).
  bool _pendingDiceComplete = false;
  bool _pendingTokenComplete = false;

  bool get pendingDiceComplete => _pendingDiceComplete;
  bool get pendingTokenComplete => _pendingTokenComplete;

  VoidCallback? _onDiceAnimationComplete;
  VoidCallback? get onDiceAnimationComplete => _onDiceAnimationComplete;
  set onDiceAnimationComplete(VoidCallback? cb) {
    _onDiceAnimationComplete = cb;
    if (cb != null && _pendingDiceComplete) {
      debugPrint('[ROLL] dice: pending flag consumed — firing immediately');
      _pendingDiceComplete = false;
      cb();
    }
  }

  VoidCallback? _onTokenAnimationComplete;
  VoidCallback? get onTokenAnimationComplete => _onTokenAnimationComplete;
  set onTokenAnimationComplete(VoidCallback? cb) {
    _onTokenAnimationComplete = cb;
    if (cb != null && _pendingTokenComplete) {
      debugPrint('[ROLL] token: pending flag consumed — firing immediately');
      _pendingTokenComplete = false;
      cb();
    }
  }

  final ValueNotifier<int?> hoveredSquare = ValueNotifier(null);
  final ValueNotifier<int?> tappedSquare = ValueNotifier(null);
  final ValueNotifier<Offset?> squareTapAnchor = ValueNotifier(null);
  final ValueNotifier<String?> hoveredPlayerIdNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, Color>> playerColoursNotifier = ValueNotifier({});

  double boardFontSize = 12.0;
  BoardColorScheme colorScheme = BoardColorScheme.pastel;
  bool freeParkingJackpotEnabled = false;

  void setBoardFontSize(double size) {
    boardFontSize = size;
  }

  void setColorScheme(BoardColorScheme scheme) {
    colorScheme = scheme;
  }

  void setFreeParkingJackpot(bool enabled) {
    freeParkingJackpotEnabled = enabled;
    if (board.isMounted) board.freeParkingJackpotEnabled = enabled;
  }

  final Map<String, TokenComponent> _tokens = {};
  final Map<String, PolicePawnComponent> _policePawns = {};
  final Map<String, TrapComponent> _traps = {};
  final Map<String, Color> _playerColours = {};
  final Map<String, bool> _prevInJail = {};
  Map<String, String> _playerNames = {};
  Map<String, String> _propertyOwnership = {};
  String? _hoveredPlayerId;
  bool _highlightLocked = false;
  Timer? _lockTimer;
  bool _gameLoaded = false;

  static const _colourPalette = [
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFF9A825),
    Color(0xFF8E24AA),
    Color(0xFFFF6D00),
    Color(0xFF00ACC1),
    Color(0xFF6D4C41),
  ];

  static Color tokenColourToColor(String? tokenColour) => switch (tokenColour) {
        'red'    => const Color(0xFFE53935),
        'blue'   => const Color(0xFF1E88E5),
        'green'  => const Color(0xFF43A047),
        'yellow' => const Color(0xFFF9A825),
        'purple' => const Color(0xFF8E24AA),
        'orange' => const Color(0xFFFF6D00),
        'pink'   => const Color(0xFFFF4081),
        'black'  => const Color(0xFF212121),
        _        => Colors.grey,
      };

  @override
  Future<void> onLoad() async {
    board = BoardComponent();
    await add(board);

    dice = DiceComponent()..position = Vector2(size.x * 0.5, size.y * 0.5);
    dice.onAnimationComplete = () {
      debugPrint('[ROLL] dice animation complete — cb=${_onDiceAnimationComplete != null}');
      if (_onDiceAnimationComplete != null) {
        _onDiceAnimationComplete!();
      } else {
        debugPrint('[ROLL] dice: no cb, setting pendingDiceComplete=true');
        _pendingDiceComplete = true;
      }
    };
    await add(dice);
    _gameLoaded = true;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!_gameLoaded) return;
    dice.position = Vector2(size.x * 0.5, size.y * 0.5);
    _snapTokensToBoard();
    _snapPolicePawnsToBoard();
  }

  void _snapTokensToBoard() {
    final squarePlayers = <int, List<String>>{};
    for (final entry in _tokens.entries) {
      squarePlayers.putIfAbsent(entry.value.currentSquare, () => []).add(entry.key);
    }
    for (final list in squarePlayers.values) {
      list.sort();
    }
    for (final entry in _tokens.entries) {
      if (entry.value.isAnimating) continue; // don't cancel mid-animation on resize
      final sq = entry.value.currentSquare;
      final slot = squarePlayers[sq]!.indexOf(entry.key);
      entry.value.moveTo(sq, board: board, teleport: true, slot: slot);
    }
  }

  void _snapPolicePawnsToBoard() {
    for (final pawn in _policePawns.values) {
      pawn.snapToBoard(board);
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!board.isMounted) return;
    final local = (event.localPosition - board.position).toOffset();
    final sq = board.squareAtLocalPosition(local);
    if (sq == tappedSquare.value) {
      tappedSquare.value = null;
      squareTapAnchor.value = null;
    } else if (sq != null) {
      tappedSquare.value = sq;
      squareTapAnchor.value = event.localPosition.toOffset();
    } else {
      tappedSquare.value = null;
      squareTapAnchor.value = null;
    }
  }

  @override
  void onMouseMove(PointerHoverInfo info) {
    if (!board.isMounted) return;
    final mousePos = info.eventPosition.widget;
    final local = (mousePos - board.position).toOffset();
    hoveredSquare.value = board.squareAtLocalPosition(local);
    if (tappedSquare.value == null) {
      squareTapAnchor.value = hoveredSquare.value != null ? mousePos.toOffset() : null;
    }

    String? hovered;
    for (final entry in _tokens.entries) {
      final token = entry.value;
      final center = token.position + Vector2(token.radius, token.radius);
      if ((mousePos - center).length <= token.radius + 4) {
        hovered = entry.key;
        break;
      }
    }
    if (hovered != _hoveredPlayerId) {
      _hoveredPlayerId = hovered;
      _updateHighlights();
    }
  }

  Map<String, Color> get playerColours => Map.unmodifiable(_playerColours);

  void setPlayerTokenColours(Map<String, Color> colours) {
    _playerColours
      ..clear()
      ..addAll(colours);
    for (final entry in _tokens.entries) {
      final colour = _playerColours[entry.key];
      if (colour != null) entry.value.colour = colour;
    }
    playerColoursNotifier.value = Map.unmodifiable(_playerColours);
  }

  void setPlayerNames(Map<String, String> names) {
    _playerNames = names;
    for (final entry in _tokens.entries) {
      entry.value.playerName = _playerNames[entry.key];
    }
  }

  final Map<String, String?> _pawnPhotoUrls = {};
  final Map<String, ui.Image> _pawnImageCache = {};

  void setPlayerPawnPhotos(Map<String, String?> urls) {
    _pawnPhotoUrls
      ..clear()
      ..addAll(urls);
    for (final entry in urls.entries) {
      _applyPawnPhoto(entry.key, entry.value);
    }
  }

  Future<void> _applyPawnPhoto(String playerId, String? url) async {
    final token = _tokens[playerId];
    if (url == null) {
      token?.pawnImage = null;
      return;
    }
    final cached = _pawnImageCache[url];
    if (cached != null) {
      token?.pawnImage = cached;
      return;
    }
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return;
      final codec = await ui.instantiateImageCodec(response.bodyBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      _pawnImageCache[url] = image;
      // Player may have swapped rooms/left by the time this resolves, or the
      // token may not exist yet if this fired before the token was created.
      if (_pawnPhotoUrls[playerId] == url) {
        _tokens[playerId]?.pawnImage = image;
      }
    } catch (_) {
      // Bad/unreachable URL: fall back to the colour disc, no error surfaced.
    }
  }

  void setHoveredPlayer(String? playerId) {
    if (_highlightLocked) return;
    if (playerId == _hoveredPlayerId) return;
    _hoveredPlayerId = playerId;
    _updateHighlights();
  }

  void lockHighlightForPlayer(String playerId) {
    _lockTimer?.cancel();
    _highlightLocked = true;
    _hoveredPlayerId = playerId;
    _updateHighlights();
    _lockTimer = Timer(const Duration(seconds: 10), () {
      _highlightLocked = false;
      _hoveredPlayerId = null;
      _updateHighlights();
    });
  }

  void onStateUpdate(GameState state) {
    debugPrint('[ROLL] onStateUpdate phase=${state.phase.name} pending=${state.pendingAction?['type']} positions=${state.boardPositions}');
    _propertyOwnership = state.propertyOwnership;
    _updateTokenPositions(state.boardPositions, state.jailStatus);
    _updatePolicePawns(state.activePolicePawns);
    dice.showValues(state.diceRoll);
    _updateHighlights();
    _updateOwnershipColours();
    _updateHousesOnBoard(state.houses, state.hotels);
    if (board.isMounted) {
      board.mortgagedSquares = state.mortgaged.toSet();
      board.freeParkingPot = state.freeParkingPot;
      board.freeParkingJackpotEnabled = freeParkingJackpotEnabled;
    }

    for (final e in state.jailStatus.entries) {
      _prevInJail[e.key] = e.value.inJail;
    }
  }

  void _updateHousesOnBoard(Map<String, int> houses, Map<String, bool> hotels) {
    if (!board.isMounted) return;
    board.squareHouseCounts = {
      for (final e in houses.entries)
        if (int.tryParse(e.key) != null && e.value > 0) int.parse(e.key): e.value,
    };
    board.squareHotels = {
      for (final e in hotels.entries)
        if (int.tryParse(e.key) != null && (e.value == true)) int.parse(e.key),
    };
  }

  void _onAnyTokenMoveComplete() {
    debugPrint('[ROLL] token move complete — cb=${_onTokenAnimationComplete != null} pendingAlready=$_pendingTokenComplete');
    if (_onTokenAnimationComplete != null) {
      _onTokenAnimationComplete!();
    } else {
      debugPrint('[ROLL] token: no cb, setting pendingTokenComplete=true');
      _pendingTokenComplete = true;
    }
  }

  void onTrapsUpdate(List<ActiveTrap> traps) {
    _updateTraps(traps);
  }

  Color _colourForPlayer(String playerId) => _playerColours.putIfAbsent(
        playerId,
        () => _colourPalette[_playerColours.length % _colourPalette.length],
      );

  void _updateTokenPositions(
    Map<String, int> positions,
    Map<String, JailStatus> jailStatus,
  ) {
    // Assign slots: sort player IDs per square for stable ordering
    final squarePlayers = <int, List<String>>{};
    for (final e in positions.entries) {
      squarePlayers.putIfAbsent(e.value, () => []).add(e.key);
    }
    for (final list in squarePlayers.values) {
      list.sort();
    }

    for (final entry in positions.entries) {
      final playerId = entry.key;
      final squareIndex = entry.value;
      final slot = squarePlayers[squareIndex]!.indexOf(playerId);

      final wasInJail = _prevInJail[playerId] ?? false;
      final nowInJail = jailStatus[playerId]?.inJail ?? false;
      final teleport = !wasInJail && nowInJail;

      if (!_tokens.containsKey(playerId)) {
        final token = TokenComponent(
          playerId: playerId,
          colour: _colourForPlayer(playerId),
        );
        token.playerName = _playerNames[playerId];
        token.onMoveComplete = _onAnyTokenMoveComplete;
        final pawnUrl = _pawnPhotoUrls[playerId];
        if (pawnUrl != null) {
          final cached = _pawnImageCache[pawnUrl];
          if (cached != null) {
            token.pawnImage = cached;
          } else {
            _applyPawnPhoto(playerId, pawnUrl);
          }
        }
        _tokens[playerId] = token;
        add(token);
      }

      final prevSquare = _tokens[playerId]!.currentSquare;
      final fwdSteps = (squareIndex - prevSquare + Board.boardSize) % Board.boardSize;
      final bwdSteps = (prevSquare - squareIndex + Board.boardSize) % Board.boardSize;
      // "Advance to Go" (square 0) must always animate clockwise regardless of
      // which side of the board the token is on; bwdSteps would be shorter from
      // squares 1-19 but going backward to Go is never the correct direction.
      final forward = teleport ||
          (squareIndex == 0 && prevSquare != 0) ||
          fwdSteps <= bwdSteps;
      _tokens[playerId]!.moveTo(squareIndex, board: board, teleport: teleport, slot: slot, forward: forward);
    }

    // Notify colour changes if palette was used
    playerColoursNotifier.value = Map.unmodifiable(_playerColours);
  }

  void _updateHighlights() {
    if (!board.isMounted) return;
    final playerId = _hoveredPlayerId;

    for (final entry in _tokens.entries) {
      entry.value.isHovered = entry.key == playerId;
    }

    hoveredPlayerIdNotifier.value = playerId;

    if (playerId == null) {
      board.highlightedSquares = {};
      return;
    }
    final colour = _colourForPlayer(playerId);
    board.highlightedSquares = {
      for (final e in _propertyOwnership.entries)
        if (e.value == playerId && int.tryParse(e.key) != null)
          int.parse(e.key): colour,
    };
  }

  void _updateOwnershipColours() {
    if (!board.isMounted) return;
    board.squareOwnerColours = {
      for (final e in _propertyOwnership.entries)
        if (int.tryParse(e.key) != null)
          int.parse(e.key): _colourForPlayer(e.value),
    };
  }

  void _updatePolicePawns(List<PolicePawn> pawns) {
    final activeIds = pawns.map((p) => p.ownerId).toSet();

    for (final id in _policePawns.keys.toList()) {
      if (!activeIds.contains(id)) {
        _policePawns.remove(id)?.removeFromParent();
      }
    }

    for (final pawn in pawns) {
      if (!_policePawns.containsKey(pawn.ownerId)) {
        final component = PolicePawnComponent(ownerId: pawn.ownerId);
        _policePawns[pawn.ownerId] = component;
        add(component);
      }
      _policePawns[pawn.ownerId]!.moveTo(pawn.position, board: board);
    }
  }

  void _updateTraps(List<ActiveTrap> traps) {
    final activeIds = traps.map((t) => t.id).toSet();

    for (final id in _traps.keys.toList()) {
      if (!activeIds.contains(id)) {
        _traps.remove(id)?.removeFromParent();
      }
    }

    for (final trap in traps) {
      if (!_traps.containsKey(trap.id)) {
        final component = TrapComponent(trap: trap);
        _traps[trap.id] = component;
        add(component);
      }
      _traps[trap.id]!.refresh(trap);
    }
  }
}
