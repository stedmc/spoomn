import 'package:freezed_annotation/freezed_annotation.dart';

part 'active_trap.freezed.dart';
part 'active_trap.g.dart';

@freezed
abstract class ActiveTrap with _$ActiveTrap {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory ActiveTrap({
    required String id,
    required String roomId,
    required String ownerId,
    required int squareIndex,
    required bool visible,
    required String sourceCardId,
    int? triggersRemaining,
    required int placedTurn,
    required Map<String, dynamic> triggerEffect,
    required DateTime createdAt,
  }) = _ActiveTrap;

  factory ActiveTrap.fromJson(Map<String, dynamic> json) =>
      _$ActiveTrapFromJson(json);
}
