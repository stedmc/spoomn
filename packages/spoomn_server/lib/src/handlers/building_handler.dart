import 'package:shelf/shelf.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../db/supabase_client.dart';
import '../middleware/auth_middleware.dart';

Future<Response> buildHouse(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  final squareIndex = payload['square'] as int?;
  if (squareIndex == null) return errorJson(400, 'MISSING_FIELD', 'square required');

  final square = Board.squares[squareIndex];
  if (square.type != SquareType.property || square.colourGroup == null) {
    return errorJson(400, 'RULE_VIOLATION', 'Not a buildable property');
  }
  if (square.houseCost == null) {
    return errorJson(400, 'RULE_VIOLATION', 'Property has no house cost defined');
  }

  final ownership = state['property_ownership'] as Map<String, dynamic>;
  final group = Board.colourGroups[square.colourGroup]!;

  // Must own entire colour group
  for (final idx in group) {
    if (ownership['$idx'] != playerId) {
      return errorJson(400, 'RULE_VIOLATION', 'Must own entire colour group to build');
    }
  }

  final mortgaged = (state['mortgaged'] as List<dynamic>).cast<int>();
  if (mortgaged.contains(squareIndex)) {
    return errorJson(400, 'RULE_VIOLATION', 'Cannot build on mortgaged property');
  }
  for (final idx in group) {
    if (mortgaged.contains(idx)) {
      return errorJson(400, 'RULE_VIOLATION', 'Cannot build while any group property is mortgaged');
    }
  }

  final houses = Map<String, dynamic>.from(state['houses'] as Map<String, dynamic>);
  final hotels = state['hotels'] as Map<String, dynamic>;

  if (hotels['$squareIndex'] == true) {
    return errorJson(400, 'RULE_VIOLATION', 'Already has a hotel');
  }

  final currentHouses = (houses['$squareIndex'] as int?) ?? 0;
  if (currentHouses >= 4) {
    return errorJson(400, 'RULE_VIOLATION', 'Max 4 houses before hotel');
  }

  // Even building rule
  if (config['must_build_evenly'] as bool? ?? true) {
    final groupHouses = group.map((idx) => (houses['$idx'] as int?) ?? 0).toList();
    final minHouses = groupHouses.reduce((a, b) => a < b ? a : b);
    if (currentHouses > minHouses) {
      return errorJson(400, 'RULE_VIOLATION',
          'Must build evenly: other properties have fewer houses');
    }
  }

  // Check build_own_turn_only
  if (config['build_own_turn_only'] as bool? ?? false) {
    final roomRow = await supabase
        .from('game_rooms')
        .select('current_player_id')
        .eq('id', roomId)
        .single();
    if (roomRow['current_player_id'] != playerId) {
      return errorJson(403, 'NOT_YOUR_TURN', 'Can only build on your own turn');
    }
  }

  // House pool check
  final houseLimit = config['house_limit'] as int?;
  final bankUnlimited = config['bank_unlimited'] as bool? ?? false;
  if (!bankUnlimited && houseLimit != null) {
    final usedHouses = houses.values
        .fold<int>(0, (sum, v) => sum + ((v as int?) ?? 0));
    final hotelCount = (state['hotels'] as Map<String, dynamic>).values
        .where((v) => v == true)
        .length;
    // Hotels consume houses from pool when houses_returned_on_hotel is false
    final housesInPool = houseLimit - usedHouses -
        (config['houses_returned_on_hotel'] as bool? ?? true ? 0 : hotelCount * 4);
    if (housesInPool <= 0) {
      return errorJson(400, 'RULE_VIOLATION', 'No houses available in pool');
    }
  }

  final balances = Map<String, dynamic>.from(
      state['balances'] as Map<String, dynamic>);
  final cost = square.houseCost!;

  if (((balances[playerId] as int?) ?? 0) < cost) {
    return errorJson(400, 'INSUFFICIENT_FUNDS', 'Not enough money to build house');
  }

  balances[playerId] = ((balances[playerId] as int?) ?? 0) - cost;
  houses['$squareIndex'] = currentHouses + 1;

  await supabase.from('game_state').update({
    'houses': houses,
    'balances': balances,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({'built': 'house', 'square': squareIndex, 'houses': currentHouses + 1});
}

Future<Response> buildHotel(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  final squareIndex = payload['square'] as int?;
  if (squareIndex == null) return errorJson(400, 'MISSING_FIELD', 'square required');

  final square = Board.squares[squareIndex];
  if (square.type != SquareType.property || square.hotelCost == null) {
    return errorJson(400, 'RULE_VIOLATION', 'Not a buildable property');
  }

  final ownership = state['property_ownership'] as Map<String, dynamic>;
  final group = Board.colourGroups[square.colourGroup]!;

  for (final idx in group) {
    if (ownership['$idx'] != playerId) {
      return errorJson(400, 'RULE_VIOLATION', 'Must own entire colour group');
    }
  }

  final hotels = Map<String, dynamic>.from(state['hotels'] as Map<String, dynamic>);
  if (hotels['$squareIndex'] == true) {
    return errorJson(400, 'RULE_VIOLATION', 'Already has a hotel');
  }

  final houses = Map<String, dynamic>.from(state['houses'] as Map<String, dynamic>);
  final requiresFour = config['hotel_requires_four_houses'] as bool? ?? true;

  if (requiresFour && ((houses['$squareIndex'] as int?) ?? 0) < 4) {
    return errorJson(400, 'RULE_VIOLATION', 'Need 4 houses before building hotel');
  }

  // Even building rule for hotels
  if (config['must_build_evenly'] as bool? ?? true) {
    for (final idx in group) {
      if (idx == squareIndex) continue;
      if (hotels['$idx'] != true && ((houses['$idx'] as int?) ?? 0) < 4) {
        return errorJson(400, 'RULE_VIOLATION',
            'Must build evenly: all properties need 4 houses before building hotel');
      }
    }
  }

  // Hotel pool check
  final hotelLimit = config['hotel_limit'] as int?;
  final bankUnlimited = config['bank_unlimited'] as bool? ?? false;
  if (!bankUnlimited && hotelLimit != null) {
    final usedHotels = hotels.values.where((v) => v == true).length;
    if (usedHotels >= hotelLimit) {
      return errorJson(400, 'RULE_VIOLATION', 'No hotels available in pool');
    }
  }

  final balances = Map<String, dynamic>.from(
      state['balances'] as Map<String, dynamic>);
  final cost = square.hotelCost!;

  if (((balances[playerId] as int?) ?? 0) < cost) {
    return errorJson(400, 'INSUFFICIENT_FUNDS', 'Not enough money to build hotel');
  }

  balances[playerId] = ((balances[playerId] as int?) ?? 0) - cost;
  hotels['$squareIndex'] = true;

  // Return 4 houses to pool
  if (config['houses_returned_on_hotel'] as bool? ?? true) {
    houses['$squareIndex'] = 0;
  }

  await supabase.from('game_state').update({
    'hotels': hotels,
    'houses': houses,
    'balances': balances,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({'built': 'hotel', 'square': squareIndex});
}

Future<Response> sellHouse(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  final squareIndex = payload['square'] as int?;
  if (squareIndex == null) return errorJson(400, 'MISSING_FIELD', 'square required');

  final square = Board.squares[squareIndex];
  if (square.houseCost == null) {
    return errorJson(400, 'RULE_VIOLATION', 'Not a buildable property');
  }

  final ownership = state['property_ownership'] as Map<String, dynamic>;
  if (ownership['$squareIndex'] != playerId) {
    return errorJson(400, 'NOT_OWNER', 'You do not own this property');
  }

  final houses = Map<String, dynamic>.from(state['houses'] as Map<String, dynamic>);
  final currentHouses = (houses['$squareIndex'] as int?) ?? 0;

  if (currentHouses <= 0) {
    return errorJson(400, 'RULE_VIOLATION', 'No houses to sell on this property');
  }

  // Even selling rule
  if (config['must_build_evenly'] as bool? ?? true) {
    final group = Board.colourGroups[square.colourGroup]!;
    final groupHouses = group.map((idx) => (houses['$idx'] as int?) ?? 0).toList();
    final maxHouses = groupHouses.reduce((a, b) => a > b ? a : b);
    if (currentHouses < maxHouses) {
      return errorJson(400, 'RULE_VIOLATION',
          'Must sell evenly: other properties have more houses');
    }
  }

  final sellRate = config['sell_building_rate'] as double? ?? 0.5;
  final proceeds = (square.houseCost! * sellRate).floor();

  houses['$squareIndex'] = currentHouses - 1;

  final balances = Map<String, dynamic>.from(
      state['balances'] as Map<String, dynamic>);
  balances[playerId] = ((balances[playerId] as int?) ?? 0) + proceeds;

  await supabase.from('game_state').update({
    'houses': houses,
    'balances': balances,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('room_id', roomId);

  return okJson({'sold': 'house', 'square': squareIndex, 'proceeds': proceeds});
}

Future<Response> sellHotel(
  String roomId,
  String playerId,
  Map<String, dynamic> state,
  Map<String, dynamic> config,
  Map<String, dynamic> payload,
) async {
  final squareIndex = payload['square'] as int?;
  if (squareIndex == null) return errorJson(400, 'MISSING_FIELD', 'square required');

  final square = Board.squares[squareIndex];
  if (square.hotelCost == null) {
    return errorJson(400, 'RULE_VIOLATION', 'Not a buildable property');
  }

  final ownership = state['property_ownership'] as Map<String, dynamic>;
  if (ownership['$squareIndex'] != playerId) {
    return errorJson(400, 'NOT_OWNER', 'You do not own this property');
  }

  final hotels = Map<String, dynamic>.from(state['hotels'] as Map<String, dynamic>);
  if (hotels['$squareIndex'] != true) {
    return errorJson(400, 'RULE_VIOLATION', 'No hotel on this property');
  }

  // Replacing hotel with 4 houses requires house pool availability
  final housesReturnedOnHotel = config['houses_returned_on_hotel'] as bool? ?? true;
  if (housesReturnedOnHotel) {
    final houseLimit = config['house_limit'] as int?;
    final bankUnlimited = config['bank_unlimited'] as bool? ?? false;
    if (!bankUnlimited && houseLimit != null) {
      final houses = state['houses'] as Map<String, dynamic>;
      final usedHouses = houses.values
          .fold<int>(0, (sum, v) => sum + ((v as int?) ?? 0));
      final hotelCount = hotels.values.where((v) => v == true).length - 1; // minus this hotel
      final available = houseLimit - usedHouses - (housesReturnedOnHotel ? 0 : hotelCount * 4);
      if (available < 4) {
        return errorJson(400, 'RULE_VIOLATION',
            'Not enough houses in pool to replace hotel (need 4, have $available)');
      }
    }
  }

  final sellRate = config['sell_building_rate'] as double? ?? 0.5;
  final proceeds = (square.hotelCost! * sellRate).floor();

  hotels.remove('$squareIndex');
  final balances = Map<String, dynamic>.from(
      state['balances'] as Map<String, dynamic>);
  balances[playerId] = ((balances[playerId] as int?) ?? 0) + proceeds;

  final updates = <String, dynamic>{
    'hotels': hotels,
    'balances': balances,
    'updated_at': DateTime.now().toIso8601String(),
  };

  if (housesReturnedOnHotel) {
    final houses = Map<String, dynamic>.from(state['houses'] as Map<String, dynamic>);
    houses['$squareIndex'] = 4;
    updates['houses'] = houses;
  }

  await supabase.from('game_state').update(updates).eq('room_id', roomId);

  return okJson({'sold': 'hotel', 'square': squareIndex, 'proceeds': proceeds});
}
