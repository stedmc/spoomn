import '../enums/square_type.dart';

class BoardSquare {
  const BoardSquare({
    required this.index,
    required this.name,
    required this.type,
    this.colourGroup,
    this.price,
    this.mortgageValue,
    this.houseCost,
    this.hotelCost,
    this.rent,       // [base, 1H, 2H, 3H, 4H, hotel]
    this.taxAmount,
  });

  final int index;
  final String name;
  final SquareType type;
  final String? colourGroup;
  final int? price;
  final int? mortgageValue;
  final int? houseCost;
  final int? hotelCost;
  final List<int>? rent;
  final int? taxAmount;
}

class Board {
  static const List<BoardSquare> squares = [
    BoardSquare(index: 0,  name: 'Go',                     type: SquareType.go),
    BoardSquare(index: 1,  name: 'Milltimber',               type: SquareType.property,  colourGroup: 'brown',      price: 60,  mortgageValue: 30,  houseCost: 50,  hotelCost: 50,  rent: [2,   10,  30,  90,  160, 250]),
    BoardSquare(index: 2,  name: 'Community Chest',         type: SquareType.communityChest),
    BoardSquare(index: 3,  name: 'Kincorth',                type: SquareType.property,  colourGroup: 'brown',      price: 60,  mortgageValue: 30,  houseCost: 50,  hotelCost: 50,  rent: [4,   20,  60,  180, 320, 450]),
    BoardSquare(index: 4,  name: 'Income Tax',              type: SquareType.tax,       taxAmount: 200),
    BoardSquare(index: 5,  name: 'Aberdeen Station',        type: SquareType.station,   price: 200, mortgageValue: 100),
    BoardSquare(index: 6,  name: 'Bridge of Don',           type: SquareType.property,  colourGroup: 'lightBlue',  price: 100, mortgageValue: 50,  houseCost: 50,  hotelCost: 50,  rent: [6,   30,  90,  270, 400, 550]),
    BoardSquare(index: 7,  name: 'Chance',                  type: SquareType.chance),
    BoardSquare(index: 8,  name: 'Tullos',                  type: SquareType.property,  colourGroup: 'lightBlue',  price: 100, mortgageValue: 50,  houseCost: 50,  hotelCost: 50,  rent: [6,   30,  90,  270, 400, 550]),
    BoardSquare(index: 9,  name: 'Northfield',              type: SquareType.property,  colourGroup: 'lightBlue',  price: 120, mortgageValue: 60,  houseCost: 50,  hotelCost: 50,  rent: [8,   40,  100, 300, 450, 600]),
    BoardSquare(index: 10, name: 'Jail / Just Visiting',    type: SquareType.jail),
    BoardSquare(index: 11, name: 'Torry',                   type: SquareType.property,  colourGroup: 'pink',       price: 140, mortgageValue: 70,  houseCost: 100, hotelCost: 100, rent: [10,  50,  150, 450, 625, 750]),
    BoardSquare(index: 12, name: 'North Sea Oil',           type: SquareType.utility,   price: 150, mortgageValue: 75),
    BoardSquare(index: 13, name: 'Danestone',               type: SquareType.property,  colourGroup: 'pink',       price: 140, mortgageValue: 70,  houseCost: 100, hotelCost: 100, rent: [10,  50,  150, 450, 625, 750]),
    BoardSquare(index: 14, name: 'Bucksburn',               type: SquareType.property,  colourGroup: 'pink',       price: 160, mortgageValue: 80,  houseCost: 100, hotelCost: 100, rent: [12,  60,  180, 500, 700, 900]),
    BoardSquare(index: 15, name: 'Dyce Station',            type: SquareType.station,   price: 200, mortgageValue: 100),
    BoardSquare(index: 16, name: 'Dyce',                    type: SquareType.property,  colourGroup: 'orange',     price: 180, mortgageValue: 90,  houseCost: 100, hotelCost: 100, rent: [14,  70,  200, 550, 750, 950]),
    BoardSquare(index: 17, name: 'Community Chest',         type: SquareType.communityChest),
    BoardSquare(index: 18, name: 'Mastrick',                type: SquareType.property,  colourGroup: 'orange',     price: 180, mortgageValue: 90,  houseCost: 100, hotelCost: 100, rent: [14,  70,  200, 550, 750, 950]),
    BoardSquare(index: 19, name: 'Portlethen',              type: SquareType.property,  colourGroup: 'orange',     price: 200, mortgageValue: 100, houseCost: 100, hotelCost: 100, rent: [16,  80,  220, 600, 800, 1000]),
    BoardSquare(index: 20, name: 'Free Parking',            type: SquareType.freeParking),
    BoardSquare(index: 21, name: 'Garthdee',                type: SquareType.property,  colourGroup: 'red',        price: 220, mortgageValue: 110, houseCost: 150, hotelCost: 150, rent: [18,  90,  250, 700, 875, 1050]),
    BoardSquare(index: 22, name: 'Chance',                  type: SquareType.chance),
    BoardSquare(index: 23, name: 'Ferryhill',               type: SquareType.property,  colourGroup: 'red',        price: 220, mortgageValue: 110, houseCost: 150, hotelCost: 150, rent: [18,  90,  250, 700, 875, 1050]),
    BoardSquare(index: 24, name: 'Rosemount',               type: SquareType.property,  colourGroup: 'red',        price: 240, mortgageValue: 120, houseCost: 150, hotelCost: 150, rent: [20,  100, 300, 750, 925, 1100]),
    BoardSquare(index: 25, name: 'Portlethen Station',      type: SquareType.station,   price: 200, mortgageValue: 100),
    BoardSquare(index: 26, name: 'Westhill',                type: SquareType.property,  colourGroup: 'yellow',     price: 260, mortgageValue: 130, houseCost: 150, hotelCost: 150, rent: [22,  110, 330, 800, 975, 1150]),
    BoardSquare(index: 27, name: 'Mannofield',              type: SquareType.property,  colourGroup: 'yellow',     price: 260, mortgageValue: 130, houseCost: 150, hotelCost: 150, rent: [22,  110, 330, 800, 975, 1150]),
    BoardSquare(index: 28, name: 'River Dee',               type: SquareType.utility,   price: 150, mortgageValue: 75),
    BoardSquare(index: 29, name: 'Peterculter',             type: SquareType.property,  colourGroup: 'yellow',     price: 280, mortgageValue: 140, houseCost: 150, hotelCost: 150, rent: [24,  120, 360, 850, 1025, 1200]),
    BoardSquare(index: 30, name: 'Go To Jail',              type: SquareType.goToJail),
    BoardSquare(index: 31, name: 'Cults',                   type: SquareType.property,  colourGroup: 'green',      price: 300, mortgageValue: 150, houseCost: 200, hotelCost: 200, rent: [26,  130, 390, 900, 1100, 1275]),
    BoardSquare(index: 32, name: 'Bieldside',               type: SquareType.property,  colourGroup: 'green',      price: 300, mortgageValue: 150, houseCost: 200, hotelCost: 200, rent: [26,  130, 390, 900, 1100, 1275]),
    BoardSquare(index: 33, name: 'Chance',                  type: SquareType.chance),
    BoardSquare(index: 34, name: 'Banchory Devenick',       type: SquareType.property,  colourGroup: 'green',      price: 320, mortgageValue: 160, houseCost: 200, hotelCost: 200, rent: [28,  150, 450, 1000, 1200, 1400]),
    BoardSquare(index: 35, name: 'Stonehaven Station',      type: SquareType.station,   price: 200, mortgageValue: 100),
    BoardSquare(index: 36, name: 'Chance',                  type: SquareType.chance),
    BoardSquare(index: 37, name: 'Maryculter',              type: SquareType.property,  colourGroup: 'darkBlue',   price: 350, mortgageValue: 175, houseCost: 200, hotelCost: 200, rent: [35,  175, 500, 1100, 1300, 1500]),
    BoardSquare(index: 38, name: 'Super Tax',               type: SquareType.tax,       taxAmount: 100),
    BoardSquare(index: 39, name: 'Stonehaven',              type: SquareType.property,  colourGroup: 'darkBlue',   price: 400, mortgageValue: 200, houseCost: 200, hotelCost: 200, rent: [50,  200, 600, 1400, 1700, 2000]),
  ];

  static const Map<String, List<int>> colourGroups = {
    'brown':     [1, 3],
    'lightBlue': [6, 8, 9],
    'pink':      [11, 13, 14],
    'orange':    [16, 18, 19],
    'red':       [21, 23, 24],
    'yellow':    [26, 27, 29],
    'green':     [31, 32, 34],
    'darkBlue':  [37, 39],
  };

  static const List<int> stationIndices = [5, 15, 25, 35];
  static const List<int> utilityIndices = [12, 28];
  static const int jailSquare = 10;
  static const int goSquare = 0;
  static const int goToJailSquare = 30;
  static const int freeParkingSquare = 20;
  static const int boardSize = 40;

  static int nearestStation(int currentPosition) =>
      _nearestOf(currentPosition, stationIndices);

  static int nearestUtility(int currentPosition) =>
      _nearestOf(currentPosition, utilityIndices);

  static int _nearestOf(int pos, List<int> targets) {
    int best = targets.first;
    int bestDist = boardSize + 1;
    for (final t in targets) {
      final d = (t - pos + boardSize) % boardSize;
      if (d > 0 && d < bestDist) {
        bestDist = d;
        best = t;
      }
    }
    return best;
  }
}
