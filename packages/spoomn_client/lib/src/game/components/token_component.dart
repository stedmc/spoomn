import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

import 'board_component.dart';

class TokenComponent extends CircleComponent {
  TokenComponent({required this.playerId, required Color colour})
      : super(radius: 10, paint: Paint()..color = colour);

  final String playerId;
  int currentSquare = 0;
  bool isHovered = false;
  String? playerName;
  bool _positioned = false;
  int _currentSlot = 0;
  VoidCallback? onMoveComplete;

  set colour(Color value) => paint.color = value;

  static const _slotOffsets = [
    Offset(-8, -6),
    Offset(8, -6),
    Offset(-8, 6),
    Offset(8, 6),
    Offset(0, -12),
    Offset(0, 12),
    Offset(-16, 0),
    Offset(16, 0),
  ];

  Vector2 _slotVector(int slot) {
    final o = slot < _slotOffsets.length ? _slotOffsets[slot] : Offset.zero;
    return Vector2(o.dx, o.dy);
  }

  void moveTo(
    int squareIndex, {
    required BoardComponent board,
    bool teleport = false,
    int slot = 0,
    bool forward = true,
  }) {
    if (_positioned && squareIndex == currentSquare && slot == _currentSlot && !teleport) {
      return;
    }

    removeWhere((c) => c is TimerComponent);
    removeAll(children.whereType<Effect>().toList());

    final slotOff = _slotVector(slot);
    final destCenter = board.squareRects[squareIndex].center;
    final destTarget = board.position + Vector2(destCenter.dx, destCenter.dy) + slotOff;

    // Teleport, initial placement, or same-square slot change: snap directly.
    if (teleport || !_positioned || squareIndex == currentSquare) {
      position = destTarget;
      currentSquare = squareIndex;
      _currentSlot = slot;
      _positioned = true;
      return;
    }

    final boardSize = board.squareRects.length;
    final steps = <int>[];
    var sq = currentSquare;
    if (forward) {
      while (sq != squareIndex) {
        sq = (sq + 1) % boardSize;
        steps.add(sq);
      }
    } else {
      while (sq != squareIndex) {
        sq = (sq - 1 + boardSize) % boardSize;
        steps.add(sq);
      }
    }

    final effects = <MoveEffect>[];
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final center = board.squareRects[s].center;
      final isLast = i == steps.length - 1;
      final off = isLast ? slotOff : Vector2.zero();
      final target = board.position + Vector2(center.dx, center.dy) + off;
      effects.add(MoveEffect.to(target, EffectController(duration: 0.12)));
    }

    if (effects.isNotEmpty) {
      add(SequenceEffect(effects));
      add(TimerComponent(
        period: steps.length * 0.12 + 0.05,
        repeat: false,
        removeOnFinish: true,
        onTick: () => onMoveComplete?.call(),
      ));
    }
    currentSquare = squareIndex;
    _currentSlot = slot;
    _positioned = true;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (isHovered && playerName != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: playerName!,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const pad = 3.0;
      final bgRect = Rect.fromLTWH(
        -pad,
        -tp.height - pad * 2 - 2,
        tp.width + pad * 2,
        tp.height + pad * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
        Paint()..color = const Color(0xCC000000),
      );
      tp.paint(canvas, Offset(0, -tp.height - pad - 2));
    }
  }
}
