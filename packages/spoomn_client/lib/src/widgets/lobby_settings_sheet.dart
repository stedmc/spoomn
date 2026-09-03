import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/game_service.dart';

// ignore_for_file: use_build_context_synchronously

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
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = ref.read(roomConfigProvider(widget.roomId)).valueOrNull;
      if (config != null && mounted) {
        setState(() {
          _config = Map<String, dynamic>.from(config);
          _loaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(String key, String text) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: text));

  Future<void> _apply() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updates = Map<String, dynamic>.from(_config)
        ..remove('room_id')
        ..remove('created_at');
      await ref.read(gameServiceProvider).updateConfig(widget.roomId, updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved'), duration: Duration(seconds: 2)),
        );
      }
    } on GameServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- Tile helpers ----

  Widget _switchTile(String key, String title, {String? subtitle, bool enabled = true}) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: _config[key] as bool? ?? false,
      onChanged: (enabled && widget.isHost) ? (v) => setState(() => _config[key] = v) : null,
    );
  }

  Widget _intTile(String key, String title, {String? subtitle, bool enabled = true}) {
    final ctrl = _ctrl(key, (_config[key] as int?)?.toString() ?? '');
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: SizedBox(
        width: 80,
        child: TextField(
          controller: ctrl,
          enabled: enabled && widget.isHost,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.end,
          decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()),
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) setState(() => _config[key] = n);
          },
        ),
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

    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      enabled: enabled,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                  ctrl.text = '0';
                  setState(() => _config[key] = 0);
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
                decoration:
                    const InputDecoration(isDense: true, border: UnderlineInputBorder()),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null) setState(() => _config[key] = n);
                },
              ),
            ),
            if (enabled && widget.isHost)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Reset to $nullLabel',
                onPressed: () => setState(() => _config[key] = null),
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
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: DropdownButton<String>(
        value: safeValue,
        isDense: true,
        underline: const SizedBox.shrink(),
        onChanged: (enabled && widget.isHost)
            ? (v) {
                if (v != null) setState(() => _config[key] = v);
              }
            : null,
        items: opts.map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2))).toList(),
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
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: DropdownButton<int>(
        value: safeValue,
        isDense: true,
        underline: const SizedBox.shrink(),
        onChanged: (enabled && widget.isHost)
            ? (v) {
                if (v != null) setState(() => _config[key] = v);
              }
            : null,
        items: opts.map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2))).toList(),
      ),
    );
  }

  Widget _rateTile(String key, String title, {String? subtitle, bool enabled = true}) {
    final v = (_config[key] as num?)?.toDouble();
    final ctrl = _ctrl(key, v?.toStringAsFixed(2) ?? '');
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: SizedBox(
        width: 80,
        child: TextField(
          controller: ctrl,
          enabled: enabled && widget.isHost,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.end,
          decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()),
          onChanged: (s) {
            final d = double.tryParse(s);
            if (d != null) setState(() => _config[key] = d);
          },
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return ExpansionTile(
      title: Text(title),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _section('Setup & Bank', [
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
        _section('Dice', [
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
        _section('Movement & Go', [
          _intTile('go_salary', 'Go salary', subtitle: 'Collect when passing Go'),
          _intTile('go_landing_bonus', 'Go landing bonus',
              subtitle: 'Extra cash for landing exactly on Go'),
        ]),
        _section('Rent', [
          _switchTile('auto_claim_rent', 'Auto-claim rent',
              subtitle: 'Server deducts rent on landing automatically'),
        ]),
        _section('Tax', [
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
        _section('Free Parking', [
          _switchTile('free_parking_jackpot', 'Free parking jackpot',
              subtitle: 'Taxes & fines pool on Free Parking'),
          _intTile('free_parking_starting_amount', 'Starting pot amount',
              subtitle: 'Initial jackpot seeded into pot', enabled: freeParkingJackpot),
        ]),
        _section('Turn Timer', [
          _nullIntTile('max_turn_time_secs', 'Max turn time', 'No limit',
              subtitle: 'Seconds before turn auto-ends'),
        ]),
        _section('Jail', [
          _intTile('jail_fine', 'Jail fine', subtitle: 'Cost to pay out of jail'),
          _intTile('jail_turns', 'Jail turns',
              subtitle: 'Turns before forced payment'),
          _switchTile('jail_doubles_escape', 'Escape with doubles',
              subtitle: 'Rolling doubles exits jail free'),
          _switchTile('collect_go_while_in_jail', 'Collect Go while jailed',
              subtitle: 'Receive Go salary when passing while jailed'),
        ]),
        _section('Jailbreak', [
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
        _section('Buildings', [
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
        _section('Mortgage', [
          _rateTile('mortgage_rate', 'Mortgage rate',
              subtitle: 'Fraction of face value received'),
          _rateTile('unmortgage_interest_rate', 'Unmortgage interest',
              subtitle: 'Interest charged to lift a mortgage'),
          _switchTile('trade_mortgaged_properties', 'Trade mortgaged properties',
              subtitle: 'Mortgaged properties can change hands'),
          _rateTile('mortgage_transfer_penalty', 'Transfer penalty',
              subtitle: 'Extra fee when trading a mortgaged property'),
        ]),
        _section('Auctions', [
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
        _section('Trading', [
          _switchTile('trade_any_turn', 'Trade at any time',
              subtitle: 'Trades allowed outside own turn'),
          _switchTile('multi_party_trades', 'Multi-party trades',
              subtitle: 'Three or more players in one trade'),
          _switchTile('trade_futures', 'Trade future immunity',
              subtitle: 'Trade future rent exemptions'),
          _nullIntTile('trade_timeout_secs', 'Trade timeout', 'No timeout',
              subtitle: 'Seconds to accept a trade offer'),
        ]),
        _section('Winning Condition', [
          _enumTile('winning_condition', 'Win condition', [
            ('last_player_standing', 'Last player standing'),
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
        _section('Bankruptcy', [
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
        _section('Loans', [
          _switchTile('loans_enabled', 'Loans enabled',
              subtitle: 'Players can borrow from the bank'),
          _intTile('loan_amount', 'Loan amount',
              subtitle: 'Fixed amount per loan', enabled: loansEnabled),
          _rateTile('loan_interest_rate', 'Loan interest rate',
              subtitle: 'Interest charged on outstanding loans', enabled: loansEnabled),
          _intTile('max_loans_per_player', 'Max loans per player',
              subtitle: 'Outstanding loan limit per player', enabled: loansEnabled),
        ]),
        _section('Async Play', [
          _nullIntTile('async_turn_timeout_hours', 'Turn timeout', 'No expiry',
              subtitle: 'Hours before idle turn is skipped'),
          _nullIntTile('async_turn_reminder_hours', 'Reminder before expiry', 'No reminder',
              subtitle: 'Hours before expiry to send a reminder'),
        ]),
        if (widget.isHost)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _saving
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton(
                    onPressed: _apply,
                    child: const Text('Apply Settings'),
                  ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
