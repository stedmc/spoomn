import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/game_service.dart';

// ignore_for_file: use_build_context_synchronously

const Map<String, dynamic> kRoomConfigDefaults = {
  'starting_money': 1500,
  'bank_unlimited': false,
  'bank_starting_amount': 20580,
  'house_limit': 32,
  'hotel_limit': 12,
  'turn_order_method': 'highest_roll',
  'warmup_laps': 0,
  'dice_count': 2,
  'dice_sides': 6,
  'doubles_enabled': true,
  'doubles_extra_turn': true,
  'jail_on_consecutive_doubles': 3,
  'go_salary': 200,
  'go_landing_bonus': 0,
  'auto_claim_rent': true,
  'income_tax_type': 'fixed',
  'income_tax_amount': 200,
  'income_tax_percentage': 10,
  'super_tax_amount': 100,
  'free_parking_jackpot': false,
  'free_parking_starting_amount': 0,
  'max_turn_time_secs': null,
  'jail_fine': 50,
  'jail_turns': 3,
  'jail_doubles_escape': true,
  'collect_go_while_in_jail': false,
  'jailbreak_enabled': false,
  'jailbreak_mandatory_turns': 3,
  'jailbreak_fine_multiplier': 2,
  'police_check_mode': 'final',
  'police_duration': null,
  'must_build_evenly': true,
  'hotel_requires_four_houses': true,
  'houses_returned_on_hotel': true,
  'build_own_turn_only': false,
  'sell_building_rate': 0.50,
  'mortgage_rate': 0.50,
  'unmortgage_interest_rate': 0.10,
  'trade_mortgaged_properties': true,
  'mortgage_transfer_penalty': 0.10,
  'auction_on_decline': true,
  'auction_style': 'ascending',
  'auction_starting_bid': 1,
  'auction_min_raise': 1,
  'auction_time_per_bid_secs': 30,
  'auction_blind_time_secs': 60,
  'auction_min_bid': 1,
  'dutch_start_price': null,
  'dutch_decrement': 10,
  'dutch_interval_secs': 5,
  'dutch_floor_price': 1,
  'trade_any_turn': false,
  'multi_party_trades': false,
  'trade_futures': false,
  'trade_timeout_secs': null,
  'winning_condition': 'last_player_standing',
  'net_worth_target': 10000,
  'net_worth_check': 'end_of_turn',
  'turn_limit': 30,
  'time_limit_mins': 60,
  'bankruptcy_assets_to': 'creditor',
  'allow_bankruptcy_negotiation': false,
  'negotiation_timeout_secs': 120,
  'repayment_interest_rate': 0.000,
  'loans_enabled': false,
  'max_loans_per_player': 3,
  'async_turn_timeout_hours': null,
  'async_turn_reminder_hours': null,
};

class LobbySettingsSheet extends ConsumerStatefulWidget {
  const LobbySettingsSheet({super.key, required this.roomId, required this.isHost});

  final String roomId;
  final bool isHost;

  @override
  ConsumerState<LobbySettingsSheet> createState() => _LobbySettingsSheetState();
}

class _LobbySettingsSheetState extends ConsumerState<LobbySettingsSheet> {
  Map<String, dynamic> _config = {};
  bool _loaded = false;
  bool _saving = false;
  Timer? _saveTimer;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = ref.read(roomConfigProvider(widget.roomId)).value;
      if (config != null && mounted) {
        setState(() {
          _config = Map<String, dynamic>.from(config);
          _loaded = true;
        });
        ref.read(draftRoomConfigProvider(widget.roomId).notifier).state =
            Map<String, dynamic>.from(config);
      }
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String key, String text) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: text));

  void _update(String key, dynamic value) {
    setState(() => _config[key] = value);
    ref.read(draftRoomConfigProvider(widget.roomId).notifier).state =
        Map<String, dynamic>.from(_config);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _apply);
  }

  Future<void> _apply() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updates = Map<String, dynamic>.from(_config)
        ..remove('room_id')
        ..remove('created_at');
      await ref.read(gameServiceProvider).updateConfig(widget.roomId, updates);
    } on GameServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- Tile helpers ----

  void _resetKey(String key) {
    final defaultVal = kRoomConfigDefaults[key];
    _update(key, defaultVal);
    final ctrl = _controllers[key];
    if (ctrl != null) {
      ctrl.text = switch (defaultVal) {
        null => '',
        double v => v.toStringAsFixed(2),
        _ => '$defaultVal',
      };
    }
  }

  bool _isDefault(String key) {
    if (!kRoomConfigDefaults.containsKey(key)) return true;
    final def = kRoomConfigDefaults[key];
    final cur = _config[key];
    if (def == null && cur == null) return true;
    if (def == null || cur == null) return false;
    if (def is double || cur is double) {
      return (def as num).toDouble() == (cur as num).toDouble();
    }
    return def == cur;
  }

  Widget _resetBtn(String key) => Tooltip(
        message: 'Reset to default',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _update(key, kRoomConfigDefaults[key]),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.restart_alt, size: 14, color: Colors.orange),
          ),
        ),
      );

  Widget _switchTile(String key, String title, {String? subtitle, bool enabled = true}) {
    final current = _config[key] as bool? ?? false;
    final showReset = !_isDefault(key) && widget.isHost && enabled;
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showReset) _resetBtn(key),
          Switch(
            value: current,
            onChanged: (enabled && widget.isHost) ? (v) => _update(key, v) : null,
          ),
        ],
      ),
    );
  }

  Widget _intTile(String key, String title, {String? subtitle, bool enabled = true}) {
    final ctrl = _ctrl(key, (_config[key] as int?)?.toString() ?? '');
    final showReset = !_isDefault(key) && widget.isHost && enabled;
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showReset) _resetBtn(key),
          SizedBox(
            width: 80,
            child: TextField(
              controller: ctrl,
              enabled: enabled && widget.isHost,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.end,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()),
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null) _update(key, n);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _nullIntTile(
    String key,
    String title,
    String nullLabel, {
    String? subtitle,
    bool enabled = true,
  }) {
    final value = _config[key] as int?;
    final isNull = value == null;
    final ctrl = _ctrl(key, value?.toString() ?? '0');
    final defaultVal = kRoomConfigDefaults[key];
    final showReset = !_isDefault(key) && widget.isHost && enabled;

    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      enabled: enabled,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showReset) _resetBtn(key),
          if (isNull) ...[
            Text(
              nullLabel,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            if (enabled && widget.isHost)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Set custom value',
                onPressed: () {
                  ctrl.text = (defaultVal as int?)?.toString() ?? '0';
                  _update(key, defaultVal ?? 0);
                },
              ),
          ] else ...[
            SizedBox(
              width: 70,
              child: TextField(
                controller: ctrl,
                enabled: enabled && widget.isHost,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.end,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration:
                    const InputDecoration(isDense: true, border: UnderlineInputBorder()),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null) _update(key, n);
                },
              ),
            ),
            if (enabled && widget.isHost)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Reset to $nullLabel',
                onPressed: () => _update(key, null),
              ),
          ],
        ],
      ),
    );
  }

  Widget _enumTile(
    String key,
    String title,
    List<(String, String)> opts, {
    String? subtitle,
    bool enabled = true,
  }) {
    final value = _config[key] as String? ?? opts.first.$1;
    final safeValue = opts.any((o) => o.$1 == value) ? value : opts.first.$1;
    final showReset = !_isDefault(key) && widget.isHost && enabled;
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showReset) _resetBtn(key),
          DropdownButton<String>(
            value: safeValue,
            isDense: true,
            underline: const SizedBox.shrink(),
            onChanged: (enabled && widget.isHost)
                ? (v) {
                    if (v != null) _update(key, v);
                  }
                : null,
            items: opts.map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2))).toList(),
          ),
        ],
      ),
    );
  }

  Widget _intChoiceTile(
    String key,
    String title,
    List<(int, String)> opts, {
    String? subtitle,
    bool enabled = true,
  }) {
    final raw = (_config[key] as num?)?.toInt() ?? opts.first.$1;
    final safeValue = opts.any((o) => o.$1 == raw) ? raw : opts.first.$1;
    final showReset = !_isDefault(key) && widget.isHost && enabled;
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showReset) _resetBtn(key),
          DropdownButton<int>(
            value: safeValue,
            isDense: true,
            underline: const SizedBox.shrink(),
            onChanged: (enabled && widget.isHost)
                ? (v) {
                    if (v != null) _update(key, v);
                  }
                : null,
            items: opts.map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2))).toList(),
          ),
        ],
      ),
    );
  }

  Widget _rateTile(String key, String title, {String? subtitle, bool enabled = true}) {
    final v = (_config[key] as num?)?.toDouble();
    final ctrl = _ctrl(key, v?.toStringAsFixed(2) ?? '');
    final showReset = !_isDefault(key) && widget.isHost && enabled;
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showReset) _resetBtn(key),
          SizedBox(
            width: 80,
            child: TextField(
              controller: ctrl,
              enabled: enabled && widget.isHost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()),
              onChanged: (s) {
                final d = double.tryParse(s);
                if (d != null) _update(key, d);
              },
            ),
          ),
        ],
      ),
    );
  }

  int _countCustom(List<String> keys) => keys.where((k) => !_isDefault(k)).length;

  Widget _badge(int count) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
        ),
        child: Text(
          '$count custom',
          style: const TextStyle(
            fontSize: 10,
            color: Colors.orange,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _section(String title, List<String> sectionKeys, List<Widget> children) {
    final n = _countCustom(sectionKeys);
    return ExpansionTile(
      title: Row(
        children: [
          Text(title),
          if (n > 0) ...[
            const SizedBox(width: 8),
            _badge(n),
          ],
        ],
      ),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(roomConfigProvider(widget.roomId), (_, next) {
      if (!_loaded && next.value != null && mounted) {
        setState(() {
          _config = Map<String, dynamic>.from(next.value!);
          _loaded = true;
        });
        ref.read(draftRoomConfigProvider(widget.roomId).notifier).state =
            Map<String, dynamic>.from(next.value!);
      }
    });

    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final bankUnlimited = _config['bank_unlimited'] as bool? ?? false;
    final doubles = _config['doubles_enabled'] as bool? ?? true;
    final incomeTaxType = _config['income_tax_type'] as String? ?? 'fixed';
    final freeParkingJackpot = _config['free_parking_jackpot'] as bool? ?? false;
    final jailbreakEnabled = _config['jailbreak_enabled'] as bool? ?? false;
    final auctionOnDecline = _config['auction_on_decline'] as bool? ?? true;
    final auctionStyle = _config['auction_style'] as String? ?? 'ascending';
    final winCondition = _config['winning_condition'] as String? ?? 'last_player_standing';
    final allowNeg = _config['allow_bankruptcy_negotiation'] as bool? ?? false;
    final loansEnabled = _config['loans_enabled'] as bool? ?? false;

    ref.listen(resetConfigKeyProvider(widget.roomId), (_, key) {
      if (key != null && mounted) {
        _resetKey(key);
        ref.read(resetConfigKeyProvider(widget.roomId).notifier).state = null;
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_saving)
          const LinearProgressIndicator(minHeight: 2),
        _section('Setup & Bank', ['starting_money', 'bank_unlimited', 'bank_starting_amount', 'house_limit', 'hotel_limit', 'turn_order_method'], [
          _intTile('starting_money', 'Starting money',
              subtitle: 'Cash each player begins with'),
          _switchTile('bank_unlimited', 'Unlimited bank',
              subtitle: 'Bank never runs out of money'),
          _intTile('bank_starting_amount', 'Bank starting amount',
              subtitle: 'Total money in the bank', enabled: !bankUnlimited),
          _nullIntTile('house_limit', 'House limit', 'Unlimited',
              subtitle: 'Max houses in play'),
          _nullIntTile('hotel_limit', 'Hotel limit', 'Unlimited',
              subtitle: 'Max hotels in play'),
          _enumTile('turn_order_method', 'Turn order', [
            ('highest_roll', 'Highest roll'),
            ('random', 'Random'),
            ('host_assigned', 'Host assigned'),
          ], subtitle: 'How player order is decided'),
        ]),
        _section('Dice', ['dice_count', 'dice_sides', 'doubles_enabled', 'doubles_extra_turn', 'jail_on_consecutive_doubles'], [
          _intTile('dice_count', 'Dice count',
              subtitle: 'Number of dice rolled per turn (1–4)'),
          _intChoiceTile('dice_sides', 'Die sides', [
            (4, 'D4'), (6, 'D6'), (8, 'D8'), (10, 'D10'), (12, 'D12'), (20, 'D20'),
          ], subtitle: 'Type of dice used'),
          _switchTile('doubles_enabled', 'Doubles enabled',
              subtitle: 'Rolling identical dice counts as a double'),
          _switchTile('doubles_extra_turn', 'Extra turn on doubles',
              subtitle: 'Doubles grants another roll', enabled: doubles),
          _nullIntTile('jail_on_consecutive_doubles', 'Jail after N doubles', 'Never',
              subtitle: 'Go to jail after this many doubles in a row', enabled: doubles),
        ]),
        _section('Movement & Go', ['go_salary', 'go_landing_bonus', 'warmup_laps'], [
          _intTile('go_salary', 'Go salary', subtitle: 'Collect when passing Go'),
          _intTile('go_landing_bonus', 'Go landing bonus',
              subtitle: 'Extra cash for landing exactly on Go'),
          _intTile('warmup_laps', 'Warm-up laps',
              subtitle: 'Laps round the board before players can buy properties'),
        ]),
        _section('Rent', ['auto_claim_rent'], [
          _switchTile('auto_claim_rent', 'Auto-claim rent',
              subtitle: 'Server deducts rent on landing automatically'),
        ]),
        _section('Tax', ['income_tax_type', 'income_tax_amount', 'income_tax_percentage', 'super_tax_amount'], [
          _enumTile('income_tax_type', 'Income tax type', [
            ('fixed', 'Fixed amount'),
            ('percentage', 'Percentage of net worth'),
          ], subtitle: 'How income tax is calculated'),
          _intTile('income_tax_amount', 'Income tax amount',
              subtitle: 'Fixed tax charged', enabled: incomeTaxType == 'fixed'),
          _intTile('income_tax_percentage', 'Income tax %',
              subtitle: 'Tax as % of net worth', enabled: incomeTaxType == 'percentage'),
          _intTile('super_tax_amount', 'Super tax amount', subtitle: 'Luxury tax charged'),
        ]),
        _section('Free Parking', ['free_parking_jackpot', 'free_parking_starting_amount'], [
          _switchTile('free_parking_jackpot', 'Free parking jackpot',
              subtitle: 'Taxes & fines pool on Free Parking'),
          _intTile('free_parking_starting_amount', 'Starting pot amount',
              subtitle: 'Initial jackpot seeded into pot', enabled: freeParkingJackpot),
        ]),
        _section('Turn Timer', ['max_turn_time_secs'], [
          _nullIntTile('max_turn_time_secs', 'Max turn time', 'No limit',
              subtitle: 'Seconds before turn auto-ends'),
        ]),
        _section('Jail', ['jail_fine', 'jail_turns', 'jail_doubles_escape', 'collect_go_while_in_jail'], [
          _intTile('jail_fine', 'Jail fine', subtitle: 'Cost to pay out of jail'),
          _intTile('jail_turns', 'Jail turns',
              subtitle: 'Turns before forced payment'),
          _switchTile('jail_doubles_escape', 'Escape with doubles',
              subtitle: 'Rolling doubles exits jail free'),
          _switchTile('collect_go_while_in_jail', 'Collect Go while jailed',
              subtitle: 'Receive Go salary when passing while jailed'),
        ]),
        _section('Jailbreak', ['jailbreak_enabled', 'jailbreak_mandatory_turns', 'jailbreak_fine_multiplier', 'police_check_mode', 'police_duration'], [
          _switchTile('jailbreak_enabled', 'Jailbreak enabled',
              subtitle: 'Police pawn can re-arrest escaped players'),
          _intTile('jailbreak_mandatory_turns', 'Mandatory turns after catch',
              subtitle: 'Turns jailed after re-arrest', enabled: jailbreakEnabled),
          _intTile('jailbreak_fine_multiplier', 'Fine multiplier on catch',
              subtitle: 'Multiplier applied to jail fine on re-arrest',
              enabled: jailbreakEnabled),
          _enumTile('police_check_mode', 'Police check mode', [
            ('final', 'Landing square only'),
            ('path', 'Every square passed'),
          ],
              subtitle: 'When police pawn checks for escapees',
              enabled: jailbreakEnabled),
          _nullIntTile('police_duration', 'Police pawn lifespan', 'Indefinite',
              subtitle: 'Turns before police pawn is removed', enabled: jailbreakEnabled),
        ]),
        _section('Buildings', ['must_build_evenly', 'hotel_requires_four_houses', 'houses_returned_on_hotel', 'build_own_turn_only', 'sell_building_rate'], [
          _switchTile('must_build_evenly', 'Must build evenly',
              subtitle: 'Houses must be spread across the color group'),
          _switchTile('hotel_requires_four_houses', 'Hotel requires 4 houses',
              subtitle: 'Must have 4 houses before upgrading to hotel'),
          _switchTile('houses_returned_on_hotel', 'Return houses on hotel',
              subtitle: 'Houses go back to bank when hotel is placed'),
          _switchTile('build_own_turn_only', 'Build on own turn only',
              subtitle: 'Cannot build during other players\' turns'),
          _rateTile('sell_building_rate', 'Sell building rate',
              subtitle: 'Fraction of cost returned on sale (0–1)'),
        ]),
        _section('Mortgage', ['mortgage_rate', 'unmortgage_interest_rate', 'trade_mortgaged_properties', 'mortgage_transfer_penalty'], [
          _rateTile('mortgage_rate', 'Mortgage rate',
              subtitle: 'Fraction of face value received'),
          _rateTile('unmortgage_interest_rate', 'Unmortgage interest',
              subtitle: 'Interest charged to lift a mortgage'),
          _switchTile('trade_mortgaged_properties', 'Trade mortgaged properties',
              subtitle: 'Mortgaged properties can change hands'),
          _rateTile('mortgage_transfer_penalty', 'Transfer penalty',
              subtitle: 'Extra fee when trading a mortgaged property'),
        ]),
        _section('Auctions', ['auction_on_decline', 'auction_style', 'auction_starting_bid', 'auction_min_raise', 'auction_time_per_bid_secs', 'auction_blind_time_secs', 'auction_min_bid', 'dutch_start_price', 'dutch_decrement', 'dutch_interval_secs', 'dutch_floor_price'], [
          _switchTile('auction_on_decline', 'Auction on decline',
              subtitle: 'Declined properties go to auction'),
          _enumTile('auction_style', 'Auction style', [
            ('ascending', 'Ascending'),
            ('blind', 'Blind'),
            ('dutch', 'Dutch'),
          ], subtitle: 'Bidding format used', enabled: auctionOnDecline),
          _intTile('auction_starting_bid', 'Starting bid',
              subtitle: 'Opening bid amount',
              enabled: auctionOnDecline && auctionStyle == 'ascending'),
          _intTile('auction_min_raise', 'Min raise',
              subtitle: 'Minimum bid increment',
              enabled: auctionOnDecline && auctionStyle == 'ascending'),
          _intTile('auction_time_per_bid_secs', 'Time per bid',
              subtitle: 'Seconds to place each bid',
              enabled: auctionOnDecline && auctionStyle == 'ascending'),
          _intTile('auction_blind_time_secs', 'Blind bid window',
              subtitle: 'Seconds for sealed bids',
              enabled: auctionOnDecline && auctionStyle == 'blind'),
          _intTile('auction_min_bid', 'Min bid (blind)',
              subtitle: 'Minimum sealed bid amount',
              enabled: auctionOnDecline && auctionStyle == 'blind'),
          _nullIntTile('dutch_start_price', 'Dutch start price', 'Property face value',
              subtitle: 'Dutch auction opening price',
              enabled: auctionOnDecline && auctionStyle == 'dutch'),
          _intTile('dutch_decrement', 'Dutch price decrement',
              subtitle: 'Price drop per interval',
              enabled: auctionOnDecline && auctionStyle == 'dutch'),
          _intTile('dutch_interval_secs', 'Dutch drop interval',
              subtitle: 'Seconds between price drops',
              enabled: auctionOnDecline && auctionStyle == 'dutch'),
          _intTile('dutch_floor_price', 'Dutch floor price',
              subtitle: 'Lowest price before auction ends',
              enabled: auctionOnDecline && auctionStyle == 'dutch'),
        ]),
        _section('Trading', ['trade_any_turn', 'multi_party_trades', 'trade_futures', 'trade_timeout_secs'], [
          _switchTile('trade_any_turn', 'Trade at any time',
              subtitle: 'Trades allowed outside own turn'),
          _switchTile('multi_party_trades', 'Multi-party trades',
              subtitle: 'Three or more players in one trade'),
          _switchTile('trade_futures', 'Trade future immunity',
              subtitle: 'Trade future rent exemptions'),
          _nullIntTile('trade_timeout_secs', 'Trade timeout', 'No timeout',
              subtitle: 'Seconds to accept a trade offer'),
        ]),
        _section('Winning Condition', ['winning_condition', 'net_worth_target', 'net_worth_check', 'turn_limit', 'time_limit_mins'], [
          _enumTile('winning_condition', 'Win condition', [
            ('last_player_standing', 'Last player standing'),
            ('highest_value_first_bankruptcy', 'Highest value at first bankruptcy'),
            ('net_worth_target', 'Net worth target'),
            ('turn_limit', 'Turn limit'),
            ('time_limit', 'Time limit'),
          ], subtitle: 'How the game ends'),
          _intTile('net_worth_target', 'Net worth target',
              subtitle: 'Net worth required to win',
              enabled: winCondition == 'net_worth_target'),
          _enumTile('net_worth_check', 'Net worth check timing', [
            ('end_of_turn', 'End of turn'),
            ('real_time', 'Real time'),
          ],
              subtitle: 'When net worth is evaluated',
              enabled: winCondition == 'net_worth_target'),
          _intTile('turn_limit', 'Turn limit',
              subtitle: 'Game ends after this many turns',
              enabled: winCondition == 'turn_limit'),
          _intTile('time_limit_mins', 'Time limit',
              subtitle: 'Game ends after this many minutes',
              enabled: winCondition == 'time_limit'),
        ]),
        _section('Bankruptcy', ['bankruptcy_assets_to', 'allow_bankruptcy_negotiation', 'negotiation_timeout_secs', 'repayment_interest_rate'], [
          _enumTile('bankruptcy_assets_to', 'Assets go to', [
            ('creditor', 'Creditor'),
            ('bank', 'Bank'),
          ], subtitle: 'Where bankrupt player\'s assets are distributed'),
          _switchTile('allow_bankruptcy_negotiation', 'Allow negotiation',
              subtitle: 'Bankrupt player can negotiate with creditor'),
          _intTile('negotiation_timeout_secs', 'Negotiation timeout',
              subtitle: 'Seconds to reach a deal', enabled: allowNeg),
          _rateTile('repayment_interest_rate', 'Repayment interest',
              subtitle: 'Interest rate on negotiated repayment plan', enabled: allowNeg),
        ]),
        _section('Loans', ['loans_enabled', 'max_loans_per_player'], [
          _switchTile('loans_enabled', 'Loans enabled',
              subtitle: 'Players can borrow from the bank'),
          _intTile('max_loans_per_player', 'Max loans per player',
              subtitle: 'Outstanding loan limit per player', enabled: loansEnabled),
        ]),
        _section('Async Play', ['async_turn_timeout_hours', 'async_turn_reminder_hours'], [
          _nullIntTile('async_turn_timeout_hours', 'Turn timeout', 'No expiry',
              subtitle: 'Hours before idle turn is skipped'),
          _nullIntTile('async_turn_reminder_hours', 'Reminder before expiry', 'No reminder',
              subtitle: 'Hours before expiry to send a reminder'),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }
}
