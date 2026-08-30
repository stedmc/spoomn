import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:spoomn_core/spoomn_core.dart';

class BoardComponent extends PositionComponent with HasGameRef {
  late List<Rect> squareRects;
  Map<int, Color> highlightedSquares = {};
  Map<int, Color> squareOwnerColours = {};
  Map<int, int> squareHouseCounts = {};
  Set<int> squareHotels = {};
  Set<int> mortgagedSquares = {};

  static const int _sidesSquares = 9;
  static const int _totalPerSide = 11;

  @override
  Future<void> onLoad() async {
    final boardWidth = gameRef.size.x < gameRef.size.y
        ? gameRef.size.x
        : gameRef.size.y;
    size = Vector2.all(boardWidth);
    position = Vector2(
      (gameRef.size.x - boardWidth) / 2,
      (gameRef.size.y - boardWidth) / 2,
    );
    squareRects = _computeSquareRects(boardWidth);
  }

  @override
  void render(Canvas canvas) {
    for (var i = 0; i < Board.boardSize; i++) {
      _drawSquare(canvas, i, squareRects[i], Board.squares[i]);
    }
  }

  int? squareAtLocalPosition(Offset local) {
    for (var i = 0; i < squareRects.length; i++) {
      if (squareRects[i].contains(local)) return i;
    }
    return null;
  }

  void _drawSquare(Canvas canvas, int index, Rect rect, BoardSquare square) {
    canvas.drawRect(rect, Paint()..color = const Color(0xFFCEE3CE));

    if (square.colourGroup != null) {
      final bandSize = rect.shortestSide * 0.28;
      // Band faces the board center
      final Rect band;
      if (index >= 1 && index <= 9) {
        // Left column → band at right
        band = Rect.fromLTWH(rect.right - bandSize, rect.top, bandSize, rect.height);
      } else if (index >= 11 && index <= 19) {
        // Top row → band at bottom
        band = Rect.fromLTWH(rect.left, rect.bottom - bandSize, rect.width, bandSize);
      } else if (index >= 21 && index <= 29) {
        // Right column → band at left
        band = Rect.fromLTWH(rect.left, rect.top, bandSize, rect.height);
      } else if (index >= 31 && index <= 39) {
        // Bottom row → band at top
        band = Rect.fromLTWH(rect.left, rect.top, rect.width, bandSize);
      } else {
        band = Rect.zero;
      }
      if (band != Rect.zero) {
        canvas.drawRect(band, Paint()..color = _groupColour(square.colourGroup!));
      }
    }

    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final highlight = highlightedSquares[index];
    if (highlight != null) {
      canvas.drawRect(
        rect.deflate(1.5),
        Paint()
          ..color = highlight
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    final ownerColour = squareOwnerColours[index];
    if (ownerColour != null) {
      final Offset dotPos;
      if (index >= 1 && index <= 9) {
        dotPos = Offset(rect.left + 5, rect.top + 5);
      } else if (index >= 11 && index <= 19) {
        dotPos = Offset(rect.left + 5, rect.top + 5);
      } else if (index >= 21 && index <= 29) {
        dotPos = Offset(rect.right - 5, rect.top + 5);
      } else if (index >= 31 && index <= 39) {
        dotPos = Offset(rect.left + 5, rect.bottom - 5);
      } else {
        dotPos = rect.center;
      }
      canvas.drawCircle(dotPos, 4, Paint()..color = ownerColour);
      canvas.drawCircle(
        dotPos,
        4,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    _drawHouses(canvas, index, rect, square);
    _drawLabel(canvas, index, rect, square);

    if (mortgagedSquares.contains(index)) {
      canvas.drawRect(rect, Paint()..color = Colors.grey.withValues(alpha: 0.55));
    }
  }

  void _drawHouses(Canvas canvas, int index, Rect rect, BoardSquare square) {
    if (square.colourGroup == null) return;
    final houses = squareHouseCounts[index] ?? 0;
    final hasHotel = squareHotels.contains(index);
    if (houses == 0 && !hasHotel) return;

    final bandSize = rect.shortestSide * 0.28;
    const dotSize = 4.0;
    const spacing = 6.0;

    if (hasHotel) {
      final Offset center;
      if (index >= 1 && index <= 9) {
        center = Offset(rect.right - bandSize / 2, rect.center.dy);
      } else if (index >= 11 && index <= 19) {
        center = Offset(rect.center.dx, rect.bottom - bandSize / 2);
      } else if (index >= 21 && index <= 29) {
        center = Offset(rect.left + bandSize / 2, rect.center.dy);
      } else {
        center = Offset(rect.center.dx, rect.top + bandSize / 2);
      }
      final hotelRect = Rect.fromCenter(center: center, width: 7, height: 5);
      canvas.drawRect(hotelRect, Paint()..color = const Color(0xFFCC0000));
      canvas.drawRect(hotelRect, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8);
    } else {
      for (var h = 0; h < houses; h++) {
        final Offset center;
        if (index >= 1 && index <= 9) {
          center = Offset(rect.right - bandSize / 2, rect.top + spacing / 2 + h * spacing);
        } else if (index >= 11 && index <= 19) {
          center = Offset(rect.left + spacing / 2 + h * spacing, rect.bottom - bandSize / 2);
        } else if (index >= 21 && index <= 29) {
          center = Offset(rect.left + bandSize / 2, rect.top + spacing / 2 + h * spacing);
        } else {
          center = Offset(rect.left + spacing / 2 + h * spacing, rect.top + bandSize / 2);
        }
        final houseRect = Rect.fromCenter(center: center, width: dotSize, height: dotSize);
        canvas.drawRect(houseRect, Paint()..color = const Color(0xFF228B22));
        canvas.drawRect(houseRect, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
      }
    }
  }

  void _drawLabel(Canvas canvas, int index, Rect rect, BoardSquare square) {
    final isCorner = index == 0 || index == 10 || index == 20 || index == 30;
    final isVertical = rect.height > rect.width * 1.4;
    final fontSize = isCorner ? 7.0 : 5.0;

    final tp = TextPainter(
      text: TextSpan(
        text: square.name,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: (isVertical ? rect.height : rect.width) - 4);

    canvas.save();
    canvas.clipRect(rect);

    if (isVertical) {
      // Left col (1-9): +90° reads from left edge; right col (21-29): -90° from right edge
      final angle = (index >= 1 && index <= 9) ? 1.5708 : -1.5708;
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(angle);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    } else {
      tp.paint(
        canvas,
        Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2),
      );
    }

    canvas.restore();
  }

  Color _groupColour(String group) => switch (group) {
        'brown'     => const Color(0xFF955436),
        'lightBlue' => const Color(0xFFAAE0FA),
        'pink'      => const Color(0xFFD93A96),
        'orange'    => const Color(0xFFF7941D),
        'red'       => const Color(0xFFED1B24),
        'yellow'    => const Color(0xFFFEF200),
        'green'     => const Color(0xFF1FB25A),
        'darkBlue'  => const Color(0xFF0072BB),
        _           => Colors.grey,
      };

  List<Rect> _computeSquareRects(double boardWidth) {
    final cornerSize = boardWidth / _totalPerSide;
    final sideSize = (boardWidth - 2 * cornerSize) / _sidesSquares;
    final rects = List<Rect>.filled(Board.boardSize, Rect.zero);

    // Square 0: Go at BL corner
    rects[0] = Rect.fromLTWH(0, boardWidth - cornerSize, cornerSize, cornerSize);

    // Left column: 1–9 bottom to top, 10 = TL corner
    for (var i = 1; i <= 10; i++) {
      final isCorner = i == 10;
      final h = isCorner ? cornerSize : sideSize;
      final y = i == 10 ? 0.0 : boardWidth - cornerSize - i * sideSize;
      rects[i] = Rect.fromLTWH(0, y, cornerSize, h);
    }

    // Top row: 11–19 left to right, 20 = TR corner
    for (var i = 11; i <= 20; i++) {
      final isCorner = i == 20;
      final w = isCorner ? cornerSize : sideSize;
      final x = i == 20 ? boardWidth - cornerSize : cornerSize + (i - 11) * sideSize;
      rects[i] = Rect.fromLTWH(x, 0, w, cornerSize);
    }

    // Right column: 21–29 top to bottom, 30 = BR corner
    for (var i = 21; i <= 30; i++) {
      final isCorner = i == 30;
      final h = isCorner ? cornerSize : sideSize;
      final y = i == 30 ? boardWidth - cornerSize : cornerSize + (i - 21) * sideSize;
      rects[i] = Rect.fromLTWH(boardWidth - cornerSize, y, cornerSize, h);
    }

    // Bottom row: 31–39 right to left (toward BL/Go)
    for (var i = 31; i <= 39; i++) {
      final x = boardWidth - cornerSize - (i - 30) * sideSize;
      rects[i] = Rect.fromLTWH(x, boardWidth - cornerSize, sideSize, cornerSize);
    }

    return rects;
  }
}
