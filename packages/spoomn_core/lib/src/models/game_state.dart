import 'package:freezed_annotation/freezed_annotation.dart';
import '../enums/game_phase.dart';

part 'game_state.freezed.dart';
part 'game_state.g.dart';

@freezed
abstract class JailStatus with _$JailStatus {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory JailStatus({
    required bool inJail,
    required bool isJailbreaking,
    required int turnsInJail,
    required int mandatoryTurnsRemaining,
    required int catchCount,
    required int effectiveFine,
    required bool hasCard,
  }) = _JailStatus;

  factory JailStatus.fromJson(Map<String, dynamic> json) =>
      _$JailStatusFromJson(json);
}

@freezed
abstract class PolicePawn with _$PolicePawn {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory PolicePawn({
    required String ownerId,
    required int position,
    int? turnsRemaining,
  }) = _PolicePawn;

  factory PolicePawn.fromJson(Map<String, dynamic> json) =>
      _$PolicePawnFromJson(json);
}

@freezed
abstract class GameState with _$GameState {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory GameState({
    required String roomId,
    required int turnNumber,
    required GamePhase phase,
    List<int>? diceRoll,
    required int consecutiveDoubles,
    required Map<String, int> boardPositions,
    required Map<String, int> lapsCompleted,
    required Map<String, String> propertyOwnership,
    required Map<String, int> houses,
    required Map<String, bool> hotels,
    required List<int> mortgaged,
    required Map<String, int> balances,
    required Map<String, JailStatus> jailStatus,
    required Map<String, int> getOutOfJailCards,
    required int communityChestIndex,
    required int chanceIndex,
    required int freeParkingPot,
    required List<PolicePawn> activePolicePawns,
    required Map<String, dynamic> rentModifiers,
    required List<dynamic> repaymentPlans,
    Map<String, dynamic>? pendingAction,
    Map<String, dynamic>? activeAuction,
    required DateTime updatedAt,
  }) = _GameState;

  factory GameState.fromJson(Map<String, dynamic> json) =>
      _$GameStateFromJson(json);
}
