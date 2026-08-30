import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:spoomn_core/spoomn_core.dart';

import 'board_component.dart';

class TrapComponent extends PositionComponent {
  TrapComponent({required ActiveTrap trap}) : _trap = trap;

  ActiveTrap _trap;

  void refresh(ActiveTrap trap) {
    _trap = trap;
  }

  void placeOn(int squareIndex, {required BoardComponent board}) {
    final center = board.squareRects[squareIndex].center;
    position = Vector2(center.dx - 6, center.dy - 6);
  }

  @override
  void render(Canvas canvas) {
    final isOwnInvisible = !_trap.visible;

    final paint = Paint()
      ..color = isOwnInvisible
          ? Colors.orange.withValues(alpha: 0.6)
          : Colors.orange;

    if (isOwnInvisible) {
      // Dashed border to indicate hidden state
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;
    }

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 12, 12),
      paint,
    );
  }
}
