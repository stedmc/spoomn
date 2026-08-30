import 'package:shelf/shelf.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../db/supabase_client.dart';
import '../middleware/auth_middleware.dart';

Future<Response> declineProperty(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) async {
  if (state['phase'] != 'action') {
    return errorJson(400, 'INVALID_PHASE', 'Expected phase: action');
  }

  final pending = state['pending_action'] as Map<String, dynamic>?;
  if (pending == null || pending['type'] != 'purchase_decision') {
    return errorJson(400, 'INVALID_PHASE', 'No purchase decision pending');
  }

  final squareIndex = pending['square'] as int;
  final auctionOnDecline = config['auction_on_decline'] as bool? ?? true;

  if (!auctionOnDecline) {
    await supabase.from('game_state').update({
      'pending_action': null,
      'phase': 'trade',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('room_id', roomId);
    return okJson({'declined': true, 'auction': false});
  }

  final auctionStyle = config['auction_style'] as String? ?? 'ascending';
  final allPlayers = (state['balances'] as Map<String, dynamic>).keys.toList();

  final activeAuction = <String, dynamic>{
    'square': squareIndex,
    'style': auctionStyle,
    'all_players': allPlayers,
    'passed': <String>[],
    'bids': <String, int>{},
    'current_leader': null,
    'current_price': config['auction_starting_bid'] as int? ?? 1,
    'current_bidder': allPlayers.isNotEmpty ? allPlayers[0] : null,
  };

  if (auctionStyle == 'dutch') {
    final square = Board.squares[squareIndex];
    activeAuction['dutch_current_price'] =
        (config['dutch_start_price'] as int?) ?? square.price ?? 1;
  }

  await supabase.from('game_state').update({
    'active_auction': activeAuction,
    'pending_action': null,
    'phase': 'auction',
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({'declined': true, 'auction': true, 'style': auctionStyle});
}

Future<Response> submitBid(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  if (state['phase'] != 'auction') {
    return errorJson(400, 'INVALID_PHASE', 'Expected phase: auction');
  }

  final auction = Map<String, dynamic>.from(
      state['active_auction'] as Map<String, dynamic>);
  final style = auction['style'] as String;
  final passed = List<String>.from(auction['passed'] as List);

  if (passed.contains(playerId)) {
    return errorJson(400, 'RULE_VIOLATION', 'Already passed on this auction');
  }

  return switch (style) {
    'ascending' => _bidAscending(roomId, playerId, state, config, auction, payload),
    'blind'     => _bidBlind(roomId, playerId, state, config, auction, payload),
    'dutch'     => _claimDutch(roomId, playerId, state, config, auction),
    _           => Future.value(errorJson(400, 'UNKNOWN_AUCTION_STYLE', 'Unknown auction style: $style')),
  };
}

Future<Response> passBid(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) async {
  if (state['phase'] != 'auction') {
    return errorJson(400, 'INVALID_PHASE', 'Expected phase: auction');
  }

  final auction = Map<String, dynamic>.from(
      state['active_auction'] as Map<String, dynamic>);
  final style = auction['style'] as String;
  final passed = List<String>.from(auction['passed'] as List);

  if (passed.contains(playerId)) {
    return errorJson(400, 'RULE_VIOLATION', 'Already passed');
  }

  if (style == 'ascending') {
    final currentBidder = auction['current_bidder'] as String?;
    if (currentBidder != null && playerId != currentBidder) {
      return errorJson(400, 'NOT_YOUR_TURN', 'Not your turn to bid');
    }
  }

  passed.add(playerId);
  auction['passed'] = passed;

  final allPlayers = List<String>.from(auction['all_players'] as List);
  final active = allPlayers.where((p) => !passed.contains(p)).toList();

  if (active.length == 1) {
    return _finaliseAuction(roomId, active.first, auction, state, config);
  }
  if (active.isEmpty) {
    // Everyone passed — property stays with bank
    await supabase.from('game_state').update({
      'active_auction': null,
      'phase': 'trade',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('room_id', roomId);
    return okJson({'passed': true, 'auction_cancelled': true});
  }

  if (style == 'ascending') {
    auction['current_bidder'] = _nextActiveBidder(allPlayers, passed, playerId);
  }

  await supabase.from('game_state').update({
    'active_auction': auction,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({'passed': true, 'remaining_bidders': active.length});
}

// ---------------------------------------------------------------------------
// Ascending
// ---------------------------------------------------------------------------

Future<Response> _bidAscending(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> auction,
  Map<String, dynamic> payload,
) async {
  final bidAmount = payload['amount'] as int?;
  if (bidAmount == null) {
    return errorJson(400, 'MISSING_FIELD', 'amount required');
  }

  final currentBidder = auction['current_bidder'] as String?;
  if (currentBidder != null && playerId != currentBidder) {
    return errorJson(400, 'NOT_YOUR_TURN', 'Not your turn to bid');
  }

  final currentPrice = auction['current_price'] as int;
  final minRaise = config['auction_min_raise'] as int? ?? 1;

  if (bidAmount < currentPrice + minRaise) {
    return errorJson(400, 'BID_TOO_LOW',
        'Bid must be at least ${currentPrice + minRaise}');
  }

  final balances = state['balances'] as Map<String, dynamic>;
  if (((balances[playerId] as int?) ?? 0) < bidAmount) {
    return errorJson(400, 'INSUFFICIENT_FUNDS', 'Not enough money to bid');
  }

  final bids = Map<String, dynamic>.from(auction['bids'] as Map);
  bids[playerId] = bidAmount;
  auction['bids'] = bids;
  auction['current_price'] = bidAmount;
  auction['current_leader'] = playerId;

  final allPlayers = List<String>.from(auction['all_players'] as List);
  final passed = List<String>.from(auction['passed'] as List);
  auction['current_bidder'] = _nextActiveBidder(allPlayers, passed, playerId);

  await supabase.from('game_state').update({
    'active_auction': auction,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({'bid': bidAmount, 'leading': true});
}

// ---------------------------------------------------------------------------
// Blind
// ---------------------------------------------------------------------------

Future<Response> _bidBlind(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> auction,
  Map<String, dynamic> payload,
) async {
  final bidAmount = payload['amount'] as int?;
  if (bidAmount == null) return errorJson(400, 'MISSING_FIELD', 'amount required');

  final minBid = config['auction_min_bid'] as int? ?? 1;
  if (bidAmount < minBid) {
    return errorJson(400, 'BID_TOO_LOW', 'Minimum bid is $minBid');
  }

  final balances = state['balances'] as Map<String, dynamic>;
  if (((balances[playerId] as int?) ?? 0) < bidAmount) {
    return errorJson(400, 'INSUFFICIENT_FUNDS', 'Not enough money to bid');
  }

  final bids = Map<String, dynamic>.from(auction['bids'] as Map);
  bids[playerId] = bidAmount;
  auction['bids'] = bids;

  final allPlayers = List<String>.from(auction['all_players'] as List);
  final allBid = allPlayers.every((p) => bids.containsKey(p));

  if (allBid) {
    // Resolve immediately when all bids are in
    final winnerId = bids.entries
        .reduce((a, b) => (a.value as int) >= (b.value as int) ? a : b)
        .key;
    return _finaliseAuction(roomId, winnerId, auction, state, config);
  }

  await supabase.from('game_state').update({
    'active_auction': auction,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({'bid_submitted': true});
}

// ---------------------------------------------------------------------------
// Dutch (player claims at current price)
// ---------------------------------------------------------------------------

Future<Response> _claimDutch(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> auction,
) async {
  final claimPrice = auction['dutch_current_price'] as int;
  final balances = state['balances'] as Map<String, dynamic>;

  if (((balances[playerId] as int?) ?? 0) < claimPrice) {
    return errorJson(400, 'INSUFFICIENT_FUNDS', 'Not enough money to claim at $claimPrice');
  }

  final floorPrice = config['dutch_floor_price'] as int? ?? 1;
  if (claimPrice <= floorPrice) {
    // Floor reached with no buyer — cancel auction
    await supabase.from('game_state').update({
      'active_auction': null,
      'phase': 'trade',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('room_id', roomId);
    return okJson({'claimed': false, 'reason': 'floor_price_reached'});
  }

  auction['bids'] = {playerId: claimPrice};
  return _finaliseAuction(roomId, playerId, auction, state, config);
}

// ---------------------------------------------------------------------------
// Finalise
// ---------------------------------------------------------------------------

Future<Response> _finaliseAuction(
  String roomId,
  String winnerId,
  Map<String, dynamic> auction,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
) async {
  final squareIndex = auction['square'] as int;
  final bids = auction['bids'] as Map<String, dynamic>;
  final winningBid = (bids[winnerId] as int?) ?? (auction['current_price'] as int? ?? 0);

  final balances = Map<String, dynamic>.from(
      state['balances'] as Map<String, dynamic>);
  final ownership = Map<String, dynamic>.from(
      state['property_ownership'] as Map<String, dynamic>);

  balances[winnerId] = ((balances[winnerId] as int?) ?? 0) - winningBid;
  ownership['$squareIndex'] = winnerId;

  await supabase.from('game_state').update({
    'balances': balances,
    'property_ownership': ownership,
    'active_auction': null,
    'phase': 'trade',
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({
    'auction_won': true,
    'winner': winnerId,
    'price': winningBid,
    'square': squareIndex,
  });
}

// Returns the next player in all_players (after currentBidder) who hasn't passed.
// Used for ascending auctions to enforce turn order.
String? _nextActiveBidder(
  List<String> allPlayers,
  List<String> passed,
  String currentBidder,
) {
  final idx = allPlayers.indexOf(currentBidder);
  if (idx == -1) return allPlayers.where((p) => !passed.contains(p)).firstOrNull;
  for (var i = 1; i <= allPlayers.length; i++) {
    final candidate = allPlayers[(idx + i) % allPlayers.length];
    if (!passed.contains(candidate)) return candidate;
  }
  return null;
}
