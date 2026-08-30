import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

class DiceComponent extends PositionComponent {
  List<int> _values = [1, 1];
  bool _rolling = false;
  List<int>? _lastShown;

  static const double _dieSize = 40;
  static const double _gap = 8;

  void showValues(List<int>? values) {
    if (values == null) {
      _lastShown = null; // cleared at end of turn — next roll will animate
      return;
    }
    if (_rolling) return;
    if (_lastShown != null && _listEquals(_lastShown!, values)) return;
    _lastShown = List.of(values);
    _rolling = true;

    // Cycle random values for 0.8s then settle
    final rand = Random();
    var elapsed = 0.0;
    add(
      TimerComponent(
        period: 0.08,
        repeat: true,
        onTick: () {
          elapsed += 0.08;
          _values = List.generate(values.length, (_) => rand.nextInt(6) + 1);
          if (elapsed >= 0.8) {
            _values = values;
            _rolling = false;
            removeWhere((c) => c is TimerComponent);
          }
        },
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    for (var i = 0; i < _values.length; i++) {
      final x = i * (_dieSize + _gap);
      _drawDie(canvas, Offset(x, 0), _values[i]);
    }
  }

  void _drawDie(Canvas canvas, Offset origin, int value) {
    final rect = Rect.fromLTWH(origin.dx, origin.dy, _dieSize, _dieSize);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final dotPaint = Paint()..color = Colors.black;
    const dotR = 4.0;
    final cx = origin.dx + _dieSize / 2;
    final cy = origin.dy + _dieSize / 2;
    const q = _dieSize * 0.28;

    final dotPositions = switch (value) {
      1 => [Offset(cx, cy)],
      2 => [Offset(cx - q, cy - q), Offset(cx + q, cy + q)],
      3 => [Offset(cx - q, cy - q), Offset(cx, cy), Offset(cx + q, cy + q)],
      4 => [Offset(cx - q, cy - q), Offset(cx + q, cy - q), Offset(cx - q, cy + q), Offset(cx + q, cy + q)],
      5 => [Offset(cx - q, cy - q), Offset(cx + q, cy - q), Offset(cx, cy), Offset(cx - q, cy + q), Offset(cx + q, cy + q)],
      _ => [Offset(cx - q, cy - q), Offset(cx + q, cy - q), Offset(cx - q, cy), Offset(cx + q, cy), Offset(cx - q, cy + q), Offset(cx + q, cy + q)],
    };

    for (final dot in dotPositions) {
      canvas.drawCircle(dot, dotR, dotPaint);
    }
  }

  @override
  Future<void> onLoad() async {
    size = Vector2(
      _values.length * _dieSize + (_values.length - 1) * _gap,
      _dieSize,
    );
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
