import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../../providers/providers.dart';
import 'game_constants.dart';

class GameActivityLog extends ConsumerWidget {
  const GameActivityLog({super.key, required this.roomId});
  final String roomId;

  static String _squareName(dynamic idx) {
    if (idx == null) return 'unknown';
    final i = idx is int ? idx : int.tryParse('$idx');
    if (i != null && i >= 0 && i < Board.squares.length) {
      return Board.squares[i].name;
    }
    return 'square $idx';
  }

  // Renders a flat interest rate (0.1 -> "10%", 0.125 -> "12.5%").
  static String _formatRate(double rate) {
    final pct = rate * 100;
    final str = pct == pct.roundToDouble()
        ? pct.round().toString()
        : pct.toStringAsFixed(1);
    return '$str%';
  }

  static String _formatRoll(String name, Map<String, dynamic> p) {
    final roll = (p['roll'] as List<dynamic>?)?.cast<int>() ?? [];
    final total = roll.fold(0, (a, b) => a + b);
    final rollStr = roll.join('+');
    if (p['sent_to_jail'] == true) return '$name rolled $rollStr=$total → Jail!';
    if (p['escaped_jail'] == true) {
      return '$name rolled $rollStr=$total, escaped jail → ${_squareName(p['new_position'])}';
    }
    if (p['failed_jail_roll'] == true) return '$name rolled $rollStr=$total — still in jail';
    if (p['mandatory_turns_remaining'] != null) {
      return '$name rolled $rollStr=$total in jail (mandatory)';
    }
    if (p['forced_fine'] != null) {
      return '$name rolled $rollStr=$total, paid £${p['forced_fine']} fine → ${_squareName(p['new_position'])}';
    }
    final passedGo = p['passed_go'] as bool? ?? false;
    return '$name rolled $rollStr=$total${passedGo ? ', passed Go' : ''} → ${_squareName(p['new_position'])}';
  }

  // Returns null for entries that should be rendered as rich widgets.
  static String? _formatEntry(
    Map<String, dynamic> entry,
    String Function(String?) nameOf,
  ) {
    final action = entry['action'] as String? ?? '';
    final payload = (entry['payload'] as Map<String, dynamic>?) ?? {};
    final pid = entry['player_id'] as String?;
    final name = nameOf(pid);

    return switch (action) {
      GameAction.rollDice           => _formatRoll(name, payload),
      GameAction.buyProperty        => '$name bought ${_squareName(payload['square'])} for £${payload['price']}',
      GameAction.declineProperty    => '$name passed on buying ${_squareName(payload['square'])}',
      GameAction.payJailFine        => '$name paid £${payload['fine']} jail fine',
      GameAction.useGoojfCard       => '$name used Get Out of Jail Free card',
      GameAction.jailbreak          => '$name broke out of jail',
      GameAction.drawCard           => '$name drew a ${payload['deck'] ?? 'card'}: ${payload['label'] ?? payload['card_id'] ?? 'unknown'}',
      GameAction.bid                => '$name bid £${payload['amount'] ?? 0} at auction',
      GameAction.passBid            => '$name passed on the auction',
      GameAction.placeTrap          => '$name placed a trap on ${_squareName(payload['square'])}',
      GameAction.trapTriggered      => '$name triggered a trap on ${_squareName(payload['square'])} (−£${payload['amount']})',
      GameAction.rentPayment        => '$name paid £${payload['amount']} rent to ${nameOf(payload['owner_id'] as String?)} on ${_squareName(payload['square'])}',
      GameAction.taxPayment         => '$name paid £${payload['amount']} tax',
      GameAction.goToJail           => '$name was sent to Jail!',
      GameAction.buildHouse         => '$name built a house on ${_squareName(payload['square'])}',
      GameAction.buildHotel         => '$name built a hotel on ${_squareName(payload['square'])}',
      GameAction.sellHouse          => '$name sold a house on ${_squareName(payload['square'])}',
      GameAction.sellHotel          => '$name sold a hotel on ${_squareName(payload['square'])}',
      GameAction.mortgageProperty   => '$name mortgaged ${_squareName(payload['square'])}',
      GameAction.unmortgageProperty => '$name unmortgaged ${_squareName(payload['square'])}',
      GameAction.gameOver           => 'Game over — ${payload['reason'] ?? ''}',
      GameAction.proposeTrade       => null, // rendered as rich widget
      GameAction.acceptTrade        => '$name accepted a trade',
      GameAction.rejectTrade        => '$name rejected a trade offer',
      GameAction.counterTrade       => '$name countered a trade offer',
      GameAction.cancelTrade        => '$name cancelled their trade offer',
      GameAction.loanRepayment      => '$name repaid £${payload['amount']} to ${nameOf(payload['creditor_id'] as String?)}'
                                        '${payload['instalments_remaining'] != null ? ' (${payload['instalments_remaining']} left)' : ''}',
      GameAction.loanRepaid         => '$name cleared their loan from ${nameOf(payload['creditor_id'] as String?)}',
      GameAction.endTurn            => null,
      _                             => '$name: $action',
    };
  }

  static (IconData, Color) _iconForAction(String action) {
    return switch (action) {
      GameAction.rollDice           => (Icons.casino, Colors.blueGrey),
      GameAction.buyProperty        => (Icons.home, Colors.green),
      GameAction.declineProperty    => (Icons.home_work, Colors.orange),
      GameAction.payJailFine        => (Icons.attach_money, Colors.orange),
      GameAction.useGoojfCard       => (Icons.credit_card, Colors.purple),
      GameAction.jailbreak          => (Icons.run_circle_outlined, Colors.deepOrange),
      GameAction.drawCard           => (Icons.help_outline, Colors.amber),
      GameAction.bid                => (Icons.gavel, Colors.brown),
      GameAction.passBid            => (Icons.gavel, Colors.grey),
      GameAction.placeTrap          => (Icons.dangerous, Colors.red),
      GameAction.trapTriggered      => (Icons.warning_amber, Colors.deepOrange),
      GameAction.rentPayment        => (Icons.receipt, Colors.orange),
      GameAction.taxPayment         => (Icons.receipt_long, Colors.red),
      GameAction.goToJail           => (Icons.lock, Colors.red),
      GameAction.buildHouse         => (Icons.house, Colors.green),
      GameAction.buildHotel         => (Icons.apartment, Colors.green),
      GameAction.sellHouse          => (Icons.house_outlined, Colors.orange),
      GameAction.sellHotel          => (Icons.apartment, Colors.orange),
      GameAction.mortgageProperty   => (Icons.account_balance, Colors.brown),
      GameAction.unmortgageProperty => (Icons.account_balance, Colors.green),
      GameAction.gameOver           => (Icons.emoji_events, Colors.amber),
      GameAction.proposeTrade       => (Icons.swap_horiz, Colors.blue),
      GameAction.acceptTrade        => (Icons.check_circle_outline, Colors.green),
      GameAction.rejectTrade        => (Icons.cancel_outlined, Colors.red),
      GameAction.cancelTrade        => (Icons.cancel_outlined, Colors.grey),
      GameAction.counterTrade       => (Icons.swap_horiz, Colors.orange),
      GameAction.loanRepayment      => (Icons.payments, Colors.teal),
      GameAction.loanRepaid         => (Icons.price_check, Colors.green),
      _                             => (Icons.info_outline, Colors.grey),
    };
  }

  // Renders the rich propose_trade entry showing what each player receives.
  static Widget _buildTradeEntry(
    Map<String, dynamic> entry,
    String Function(String?) nameOf,
  ) {
    final payload      = (entry['payload'] as Map<String, dynamic>?) ?? {};
    final pid          = entry['player_id'] as String?;
    final proposerName = nameOf(pid);
    final legs         = (payload['legs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final participants = (payload['participants'] as List?)?.cast<String>() ?? [];
    final multiParty   = participants.length > 2;

    // Build a map of what each player receives: toId → list of descriptions
    final received = <String, List<String>>{};
    for (final leg in legs) {
      final from       = leg['from'] as String? ?? '';
      final to         = leg['to']   as String? ?? '';
      final properties = (leg['properties'] as List?)?.cast<int>() ?? [];
      final money      = (leg['money'] as num?)?.toInt() ?? 0;
      final rentTurns  = (leg['rent_immunity_turns'] as num?)?.toInt() ?? 0;

      final items = received.putIfAbsent(to, () => []);
      for (final p in properties) {
        final desc = multiParty
            ? '${_squareName(p)} (from ${nameOf(from)})'
            : _squareName(p);
        items.add(desc);
      }
      if (money > 0) {
        final desc = multiParty ? '£$money (from ${nameOf(from)})' : '£$money';
        items.add(desc);
      }
      if (rentTurns > 0) {
        final turns = rentTurns == 1 ? '1 turn' : '$rentTurns turns';
        final desc = multiParty
            ? 'Rent immunity for $turns (from ${nameOf(from)})'
            : 'Rent immunity for $turns';
        items.add(desc);
      }
      final loan = LoanTerms.tryParse(leg['loan']);
      if (loan != null) {
        final turns = loan.turns == 1 ? '1 turn' : '${loan.turns} turns';
        final rate = _formatRate(loan.interestRate);
        final terms =
            'repay £${loan.totalRepayable} over $turns ($rate interest, £${loan.instalment}/turn)';
        final desc = multiParty
            ? 'Loan of £${loan.amount} from ${nameOf(from)} — $terms'
            : 'Loan of £${loan.amount} — $terms';
        items.add(desc);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.swap_horiz, size: 14, color: Colors.blue),
              const SizedBox(width: 6),
              Expanded(
                child: Text('$proposerName proposed a trade',
                    style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          if (received.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final entry in received.entries)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nameOf(entry.key),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                    for (final item in entry.value)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 1),
                        child: Text('• $item',
                            style: const TextStyle(fontSize: 10)),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(gameLogProvider(roomId));
    final players = ref.watch(roomPlayersProvider(roomId)).value ?? [];

    String nameOf(String? id) => id == null
        ? 'Unknown'
        : (players.where((p) => p.playerId == id).firstOrNull?.displayName ?? 'Player');

    return logAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (entries) {
        // Filter out null-formatted entries that are also not rich entries
        final visibleEntries = entries.where((e) {
          final action = e['action'] as String? ?? '';
          if (action == GameAction.endTurn) return false;
          return true;
        }).toList();

        if (visibleEntries.isEmpty) {
          return const Center(
            child: Text('No activity yet', style: TextStyle(fontSize: 12, color: Colors.grey)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: visibleEntries.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 8, endIndent: 8),
          itemBuilder: (context, i) {
            final entry  = visibleEntries[i];
            final action = entry['action'] as String? ?? '';

            // Rich widget for propose_trade
            if (action == GameAction.proposeTrade) {
              return _buildTradeEntry(entry, nameOf);
            }

            final text = _formatEntry(entry, nameOf);
            if (text == null) return const SizedBox.shrink();
            final (icon, iconColor) = _iconForAction(action);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 14, color: iconColor),
                  const SizedBox(width: 6),
                  Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
