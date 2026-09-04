import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBoardFontSize = 'board_font_size';
const double kDefaultBoardFontSize = 12.0;

const _kBoardColorScheme = 'board_color_scheme';

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
    required this.id,
    required this.displayName,
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

  final String id;
  final String displayName;
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

  static const classic = BoardColorScheme(
    id: 'classic',
    displayName: 'Classic',
    brown:     Color(0xFF955436),
    lightBlue: Color(0xFFAAE0FA),
    pink:      Color(0xFFD93A96),
    orange:    Color(0xFFF7941D),
    red:       Color(0xFFED1B24),
    yellow:    Color(0xFFFEF200),
    green:     Color(0xFF1FB25A),
    darkBlue:  Color(0xFF0072BB),
    boardBackground:     Color(0xFFCEE3CE),
    hotel:               Color(0xFFCC0000),
    house:               Color(0xFF228B22),
    communityChestFace:  Color(0xFFFFF9E6),
    communityChestLabel: Color(0xFFC87800),
    chanceFace:          Color(0xFFFFECEC),
    chanceLabel:         Color(0xFFCC2200),
    freeParkingText:     Color(0xFFDAA520),
  );

  static const jewel = BoardColorScheme(
    id: 'jewel',
    displayName: 'Jewel',
    brown:     Color(0xFF722F37),
    lightBlue: Color(0xFF20B2AA),
    pink:      Color(0xFF7C3AED),
    orange:    Color(0xFFD97706),
    red:       Color(0xFFE85D5D),
    yellow:    Color(0xFFEAB308),
    green:     Color(0xFF059669),
    darkBlue:  Color(0xFF4338CA),
    boardBackground:     Color(0xFFF5EDD4),
    hotel:               Color(0xFFB91C1C),
    house:               Color(0xFF047857),
    communityChestFace:  Color(0xFFF0FDF4),
    communityChestLabel: Color(0xFF065F46),
    chanceFace:          Color(0xFFF5F3FF),
    chanceLabel:         Color(0xFF4C1D95),
    freeParkingText:     Color(0xFFD97706),
  );

  static const pastel = BoardColorScheme(
    id: 'pastel',
    displayName: 'Pastel',
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

  static const bold = BoardColorScheme(
    id: 'bold',
    displayName: 'Bold',
    brown:     Color(0xFF6B3F2A),
    lightBlue: Color(0xFF06B6D4),
    pink:      Color(0xFFC026D3),
    orange:    Color(0xFFF97316),
    red:       Color(0xFFDC2626),
    yellow:    Color(0xFFA3E635),
    green:     Color(0xFF16A34A),
    darkBlue:  Color(0xFF1E40AF),
    boardBackground:     Color(0xFFEEF2F7),
    hotel:               Color(0xFFDC2626),
    house:               Color(0xFF16A34A),
    communityChestFace:  Color(0xFFF0F9FF),
    communityChestLabel: Color(0xFF0C4A6E),
    chanceFace:          Color(0xFFFFF0F3),
    chanceLabel:         Color(0xFF9D174D),
    freeParkingText:     Color(0xFFEAB308),
  );

  static const all = [classic, jewel, pastel, bold];

  static BoardColorScheme fromId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => classic);
}

final boardColorSchemeProvider =
    NotifierProvider<BoardColorSchemeNotifier, BoardColorScheme>(
  BoardColorSchemeNotifier.new,
);

class BoardColorSchemeNotifier extends Notifier<BoardColorScheme> {
  @override
  BoardColorScheme build() {
    final id = ref.read(sharedPreferencesProvider).getString(_kBoardColorScheme);
    return id != null ? BoardColorScheme.fromId(id) : BoardColorScheme.classic;
  }

  Future<void> set(BoardColorScheme scheme) async {
    state = scheme;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_kBoardColorScheme, scheme.id);
  }
}
