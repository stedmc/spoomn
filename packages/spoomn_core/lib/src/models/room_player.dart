import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_player.freezed.dart';
part 'room_player.g.dart';

@freezed
abstract class RoomPlayer with _$RoomPlayer {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory RoomPlayer({
    required String id,
    required String roomId,
    required String playerId,
    String? displayName,
    int? seatOrder,
    String? tokenColour,
    required bool isBankrupt,
    required bool isConnected,
    required DateTime joinedAt,
    DateTime? leftAt,
  }) = _RoomPlayer;

  factory RoomPlayer.fromJson(Map<String, dynamic> json) =>
      _$RoomPlayerFromJson(json);
}
