import 'package:freezed_annotation/freezed_annotation.dart';
import '../enums/play_mode.dart';

part 'game_room.freezed.dart';
part 'game_room.g.dart';

enum GameRoomStatus { lobby, starting, active, paused, finished }

@freezed
abstract class GameRoom with _$GameRoom {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory GameRoom({
    required String id,
    required String roomCode,
    required GameRoomStatus status,
    required String hostId,
    String? currentPlayerId,
    required PlayMode playMode,
    DateTime? turnStartedAt,
    required int playerCount,
    required int maxPlayers,
    required DateTime createdAt,
    DateTime? startedAt,
    DateTime? pausedAt,
    DateTime? finishedAt,
  }) = _GameRoom;

  factory GameRoom.fromJson(Map<String, dynamic> json) =>
      _$GameRoomFromJson(json);
}
