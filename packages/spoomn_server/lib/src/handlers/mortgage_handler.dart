import 'package:shelf/shelf.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../db/supabase_client.dart';
import '../middleware/auth_middleware.dart';

Future<Response> mortgageProperty(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  final squareIndex = payload['square'] as int?;
  if (squareIndex == null) return errorJson(400, 'MISSING_FIELD', 'square required');

  final square = Board.squares[squareIndex];
  if (square.mortgageValue == null) {
    return errorJson(400, 'RULE_VIOLATION', 'Property cannot be mortgaged');
  }

  final ownership = state['property_ownership'] as Map<String, dynamic>;
  if (ownership['$squareIndex'] != playerId) {
    return errorJson(400, 'NOT_OWNER', 'You do not own this property');
  }

  final mortgaged = List<dynamic>.from(state['mortgaged'] as List<dynamic>);
  if (mortgaged.contains(squareIndex)) {
    return errorJson(400, 'RULE_VIOLATION', 'Property is already mortgaged');
  }

  // No buildings allowed on any property in the colour group
  if (square.colourGroup != null) {
    final group = Board.colourGroups[square.colourGroup] ?? [];
    final houses = state['houses'] as Map<String, dynamic>;
    final hotels = state['hotels'] as Map<String, dynamic>;
    for (final idx in group) {
      if (((houses['$idx'] as int?) ?? 0) > 0 || hotels['$idx'] == true) {
        return errorJson(400, 'RULE_VIOLATION',
            'Must sell all buildings in colour group before mortgaging');
      }
    }
  }

  final mortgageRate = config['mortgage_rate'] as double? ?? 0.5;
  final mortgageValue = (square.price! * mortgageRate).floor();

  mortgaged.add(squareIndex);
  final balances = Map<String, dynamic>.from(
      state['balances'] as Map<String, dynamic>);
  balances[playerId] = ((balances[playerId] as int?) ?? 0) + mortgageValue;

  await supabase.from('game_state').update({
    'mortgaged': mortgaged,
    'balances': balances,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({
    'mortgaged': squareIndex,
    'received': mortgageValue,
  });
}

Future<Response> unmortgageProperty(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  final squareIndex = payload['square'] as int?;
  if (squareIndex == null) return errorJson(400, 'MISSING_FIELD', 'square required');

  final square = Board.squares[squareIndex];
  if (square.mortgageValue == null || square.price == null) {
    return errorJson(400, 'RULE_VIOLATION', 'Property cannot be unmortgaged');
  }

  final ownership = state['property_ownership'] as Map<String, dynamic>;
  if (ownership['$squareIndex'] != playerId) {
    return errorJson(400, 'NOT_OWNER', 'You do not own this property');
  }

  final mortgaged = List<dynamic>.from(state['mortgaged'] as List<dynamic>);
  if (!mortgaged.contains(squareIndex)) {
    return errorJson(400, 'RULE_VIOLATION', 'Property is not mortgaged');
  }

  final mortgageRate = config['mortgage_rate'] as double? ?? 0.5;
  final interestRate = config['unmortgage_interest_rate'] as double? ?? 0.1;
  // total = purchase_price × mortgage_rate × (1 + interest_rate)
  final totalCost = (square.price! * mortgageRate * (1 + interestRate)).ceil();

  final balances = Map<String, dynamic>.from(
      state['balances'] as Map<String, dynamic>);

  if (((balances[playerId] as int?) ?? 0) < totalCost) {
    return errorJson(400, 'INSUFFICIENT_FUNDS',
        'Need £$totalCost to unmortgage (mortgage value + interest)');
  }

  mortgaged.remove(squareIndex);
  balances[playerId] = ((balances[playerId] as int?) ?? 0) - totalCost;

  await supabase.from('game_state').update({
    'mortgaged': mortgaged,
    'balances': balances,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({
    'unmortgaged': squareIndex,
    'paid': totalCost,
  });
}
