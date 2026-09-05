import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBoardFontSize = 'board_font_size';
const double kDefaultBoardFontSize = 12.0;

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main()'),
);

final boardFontSizeProvider = NotifierProvider<BoardFontSizeNotifier, double>(
  BoardFontSizeNotifier.new,
);

class BoardFontSizeNotifier extends Notifier<double> {
  @override
  double build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return prefs.getDouble(_kBoardFontSize) ?? kDefaultBoardFontSize;
  }

  Future<void> set(double size) async {
    state = size;
    await ref.read(sharedPreferencesProvider).setDouble(_kBoardFontSize, size);
  }
}

// ---------------------------------------------------------------------------
// Board colour scheme
// ---------------------------------------------------------------------------

class BoardColorScheme {
  const BoardColorScheme({
    required this.brown,
    required this.lightBlue,
    required this.pink,
    required this.orange,
    required this.red,
    required this.yellow,
    required this.green,
    required this.darkBlue,
    required this.boardBackground,
    required this.hotel,
    required this.house,
    required this.communityChestFace,
    required this.communityChestLabel,
    required this.chanceFace,
    required this.chanceLabel,
    required this.freeParkingText,
  });

  final Color brown;
  final Color lightBlue;
  final Color pink;
  final Color orange;
  final Color red;
  final Color yellow;
  final Color green;
  final Color darkBlue;
  final Color boardBackground;
  final Color hotel;
  final Color house;
  final Color communityChestFace;
  final Color communityChestLabel;
  final Color chanceFace;
  final Color chanceLabel;
  final Color freeParkingText;

  Color? groupColour(String? group) => switch (group) {
    'brown'     => brown,
    'lightBlue' => lightBlue,
    'pink'      => pink,
    'orange'    => orange,
    'red'       => red,
    'yellow'    => yellow,
    'green'     => green,
    'darkBlue'  => darkBlue,
    _           => null,
  };

  static const pastel = BoardColorScheme(
    brown:     Color(0xFFC9956A),
    lightBlue: Color(0xFF7DD3FC),
    pink:      Color(0xFFFB7185),
    orange:    Color(0xFFFDBA74),
    red:       Color(0xFFF87171),
    yellow:    Color(0xFFFDE68A),
    green:     Color(0xFF6EE7B7),
    darkBlue:  Color(0xFF818CF8),
    boardBackground:     Color(0xFFF0EEFF),
    hotel:               Color(0xFFE11D48),
    house:               Color(0xFF34D399),
    communityChestFace:  Color(0xFFFFF7ED),
    communityChestLabel: Color(0xFF9A3412),
    chanceFace:          Color(0xFFFDF4FF),
    chanceLabel:         Color(0xFF7E22CE),
    freeParkingText:     Color(0xFFF59E0B),
  );
}

final boardColorSchemeProvider =
    NotifierProvider<BoardColorSchemeNotifier, BoardColorScheme>(
  BoardColorSchemeNotifier.new,
);

class BoardColorSchemeNotifier extends Notifier<BoardColorScheme> {
  @override
  BoardColorScheme build() => BoardColorScheme.pastel;
}
