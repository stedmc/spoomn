import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_config.freezed.dart';
part 'room_config.g.dart';

@freezed
abstract class RoomConfig with _$RoomConfig {
  const factory RoomConfig({
    required String roomId,
    // Setup
    @Default(1500) int startingMoney,
    @Default(false) bool bankUnlimited,
    @Default(20580) int bankStartingAmount,
    @Default(32) int? houseLimit,
    @Default(12) int? hotelLimit,
    @Default('highest_roll') String turnOrderMethod,
    @Default(0) int warmupLaps,
    // Dice
    @Default(2) int diceCount,
    @Default(6) int diceSides,
    @Default(true) bool doublesEnabled,
    @Default(true) bool doublesExtraTurn,
    @Default(3) int? jailOnConsecutiveDoubles,
    // Movement
    @Default(200) int goSalary,
    @Default(0) int goLandingBonus,
    // Rent
    @Default(true) bool autoClaimRent,
    // Tax
    @Default('fixed') String incomeTaxType,
    @Default(200) int incomeTaxAmount,
    @Default(10) int incomeTaxPercentage,
    @Default(100) int superTaxAmount,
    // Free parking
    @Default(false) bool freeParkingJackpot,
    @Default(0) int freeParkingStartingAmount,
    // Turn timer
    int? maxTurnTimeSecs,
    // Jail
    @Default(50) int jailFine,
    @Default(3) int jailTurns,
    @Default(true) bool jailDoublesEscape,
    @Default(false) bool collectGoWhileInJail,
    // Jailbreak
    @Default(false) bool jailbreakEnabled,
    @Default(3) int jailbreakMandatoryTurns,
    @Default(2) int jailbreakFineMultiplier,
    @Default('final') String policeCheckMode,
    int? policeDuration,
    // Buildings
    @Default(true) bool mustBuildEvenly,
    @Default(true) bool hotelRequiresFourHouses,
    @Default(true) bool housesReturnedOnHotel,
    @Default(false) bool buildOwnTurnOnly,
    @Default(0.5) double sellBuildingRate,
    // Mortgage
    @Default(0.5) double mortgageRate,
    @Default(0.1) double unmortgageInterestRate,
    @Default(true) bool tradeMortgagedProperties,
    @Default(0.1) double mortgageTransferPenalty,
    // Auctions
    @Default(true) bool auctionOnDecline,
    @Default('ascending') String auctionStyle,
    @Default(1) int auctionStartingBid,
    @Default(1) int auctionMinRaise,
    @Default(30) int auctionTimePerBidSecs,
    @Default(60) int auctionBlindTimeSecs,
    @Default(1) int auctionMinBid,
    int? dutchStartPrice,
    @Default(10) int dutchDecrement,
    @Default(5) int dutchIntervalSecs,
    @Default(1) int dutchFloorPrice,
    // Trading
    @Default(false) bool tradeAnyTurn,
    @Default(false) bool multiPartyTrades,
    @Default(false) bool tradeFutures,
    int? tradeTimeoutSecs,
    // Cards
    List<Map<String, dynamic>>? customCommunityChest,
    List<Map<String, dynamic>>? customChance,
    // Winning
    @Default('last_player_standing') String winningCondition,
    @Default(10000) int netWorthTarget,
    @Default('end_of_turn') String netWorthCheck,
    @Default(30) int turnLimit,
    @Default(60) int timeLimitMins,
    // Bankruptcy
    @Default('creditor') String bankruptcyAssetsTo,
    @Default(false) bool allowBankruptcyNegotiation,
    @Default(120) int negotiationTimeoutSecs,
    @Default(0.0) double repaymentInterestRate,
    // Loans
    @Default(false) bool loansEnabled,
    @Default(200) int loanAmount,
    @Default(0.1) double loanInterestRate,
    @Default(3) int maxLoansPerPlayer,
    // Async
    int? asyncTurnTimeoutHours,
    int? asyncTurnReminderHours,
  }) = _RoomConfig;

  factory RoomConfig.fromJson(Map<String, dynamic> json) =>
      _$RoomConfigFromJson(json);
}
