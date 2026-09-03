abstract final class GameAction {
  static const String rollDice = 'roll_dice';
  static const String buyProperty = 'buy_property';
  static const String declineProperty = 'decline_property';
  static const String endTurn = 'end_turn';
  static const String declareBankruptcy = 'declare_bankruptcy';
  static const String bid = 'bid';
  static const String passBid = 'pass_bid';
  static const String buildHouse = 'build_house';
  static const String buildHotel = 'build_hotel';
  static const String sellHouse = 'sell_house';
  static const String sellHotel = 'sell_hotel';
  static const String mortgageProperty = 'mortgage_property';
  static const String unmortgageProperty = 'unmortgage_property';
  static const String debugTeleport = 'debug_teleport';
  static const String debugAssignProperty = 'debug_assign_property';
  static const String payJailFine = 'pay_jail_fine';
  static const String useGoojfCard = 'use_goojf_card';
  static const String jailbreak = 'jailbreak';
  static const String drawCard = 'draw_card';
  static const String placeTrap = 'place_trap';
  static const String trapTriggered = 'trap_triggered';
  static const String rentPayment = 'rent_payment';
  static const String taxPayment = 'tax_payment';
  static const String goToJail = 'go_to_jail';
  static const String gameOver = 'game_over';
  static const String proposeTrade = 'propose_trade';
  static const String acceptTrade  = 'accept_trade';
  static const String rejectTrade  = 'reject_trade';
  static const String cancelTrade  = 'cancel_trade';
  static const String counterTrade = 'counter_trade';
}

abstract final class GamePhaseName {
  static const String roll = 'roll';
  static const String action = 'action';
  static const String auction = 'auction';
  static const String trade = 'trade';
  static const String bankruptcyNegotiation = 'bankruptcyNegotiation';
}

abstract final class GamePendingType {
  static const String purchaseDecision = 'purchase_decision';
  static const String rentPayment = 'rent_payment';
}
