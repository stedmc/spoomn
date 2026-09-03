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
