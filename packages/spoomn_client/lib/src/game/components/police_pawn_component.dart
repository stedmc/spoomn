import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

import 'board_component.dart';

class PolicePawnComponent extends CircleComponent {
  PolicePawnComponent({required this.ownerId})
      : super(
          radius: 8,
          paint: Paint()..color = Colors.blue.shade800,
        );

  final String ownerId;
  int _currentSquare = 0;

  void moveTo(int squareIndex, {required BoardComponent board}) {
    _currentSquare = squareIndex;
    final center = board.squareRects[squareIndex].center;
    final target = board.position + Vector2(center.dx, center.dy);
    add(
      MoveEffect.to(
        target,
        EffectController(duration: 0.3, curve: Curves.easeIn),
      ),
    );
  }

  void snapToBoard(BoardComponent board) {
    removeAll(children.whereType<Effect>().toList());
    final center = board.squareRects[_currentSquare].center;
    position = board.position + Vector2(center.dx, center.dy);
  }
}
