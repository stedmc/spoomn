import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/game_service.dart';
import 'game_constants.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

Color _tokenColor(String? colour) => switch (colour) {
      'red'    => const Color(0xFFE53935),
      'blue'   => const Color(0xFF1E88E5),
      'green'  => const Color(0xFF43A047),
      'yellow' => const Color(0xFFF9A825),
      'purple' => const Color(0xFF8E24AA),
      'orange' => const Color(0xFFFF6D00),
      'pink'   => const Color(0xFFFF4081),
      'black'  => const Color(0xFF212121),
      _        => Colors.grey,
    };

const List<String> _groupOrder = [
  'brown', 'lightBlue', 'pink', 'orange', 'red', 'yellow', 'green', 'darkBlue',
];

/// Default repayment length (borrower turns) pre-filled into the loan card.
/// The lender can change it per trade.
const int _kDefaultLoanTurns = 10;

// ─── Drag data ────────────────────────────────────────────────────────────────

class _TradeDragData {
  const _TradeDragData({required this.ownerId, required this.propIndex});
  final String ownerId;
  final int propIndex; // board index ≥ 0 | -1 = cash | -2 = rent immunity | -3 = loan
}

// ─── Arrow painter ────────────────────────────────────────────────────────────

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({
    required this.propAssignments,
    required this.moneyTargets,
    required this.rentTargets,
    required this.loanTargets,
    required this.cardKeys,
    required this.cashKeys,
    required this.rentKeys,
    required this.loanKeys,
    required this.pawnKeys,
    required this.stackKey,
    required this.playerColors,
  });

  final Map<String, String> propAssignments;
  final Map<String, String> moneyTargets;
  final Map<String, String> rentTargets;
  final Map<String, String> loanTargets;
  final Map<String, GlobalKey> cardKeys;
  final Map<String, GlobalKey> cashKeys;
  final Map<String, GlobalKey> rentKeys;
  final Map<String, GlobalKey> loanKeys;
  final Map<String, GlobalKey> pawnKeys;
  final GlobalKey stackKey;
  final Map<String, Color> playerColors;

  @override
  void paint(Canvas canvas, Size size) {
    final stackBox = stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    for (final e in propAssignments.entries) {
      _arrow(canvas, stackBox, cardKeys[e.key], pawnKeys[e.value],
          playerColors[e.value] ?? Colors.blue);
    }
    for (final e in moneyTargets.entries) {
      _arrow(canvas, stackBox, cashKeys[e.key], pawnKeys[e.value],
          const Color(0xFF2E7D32));
    }
    for (final e in rentTargets.entries) {
      _arrow(canvas, stackBox, rentKeys[e.key], pawnKeys[e.value],
          Colors.deepPurple.shade400);
    }
    for (final e in loanTargets.entries) {
      _arrow(canvas, stackBox, loanKeys[e.key], pawnKeys[e.value],
          const Color(0xFFFF8F00));
    }
  }

  void _arrow(
    Canvas canvas,
    RenderBox stackBox,
    GlobalKey? fromKey,
    GlobalKey? toKey,
    Color color,
  ) {
    final fromBox = fromKey?.currentContext?.findRenderObject() as RenderBox?;
    final toBox   = toKey?.currentContext?.findRenderObject() as RenderBox?;
    if (fromBox == null || toBox == null) return;

    final from = stackBox.globalToLocal(
      fromBox.localToGlobal(Offset(fromBox.size.width / 2, fromBox.size.height / 2)),
    );
    final to = stackBox.globalToLocal(
      toBox.localToGlobal(Offset(toBox.size.width / 2, toBox.size.height / 2)),
    );

    // Bezier: pull horizontally from source and approach target from the right
    final span = math.max(60.0, (to - from).distance * 0.35);
    final p1 = Offset(from.dx - span, from.dy);
    final p2 = Offset(to.dx + span, to.dy);

    final strokePaint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, to.dx, to.dy),
      strokePaint,
    );

    // Arrowhead: tangent at t=1 is direction P2→P3
    final angle = math.atan2(to.dy - p2.dy, to.dx - p2.dx);
    const len = 9.0;
    const spread = 0.45;
    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(to.dx - len * math.cos(angle - spread),
                 to.dy - len * math.sin(angle - spread))
        ..lineTo(to.dx - len * math.cos(angle + spread),
                 to.dy - len * math.sin(angle + spread))
        ..close(),
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => true;
}

// ─── Property card ────────────────────────────────────────────────────────────

class _TradePropCard extends ConsumerWidget {
  const _TradePropCard({
    required this.boardIndex,
    required this.isMortgaged,
    this.assignedToColor,
    this.isBeingDragged = false,
  });

  final int boardIndex;
  final bool isMortgaged;
  final Color? assignedToColor;
  final bool isBeingDragged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (boardIndex < 0 || boardIndex >= Board.squares.length) {
      return const SizedBox(width: 96);
    }
    final sq = Board.squares[boardIndex];
    final scheme = ref.watch(boardColorSchemeProvider);

    Color bandColor;
    IconData? bandIcon;
    switch (sq.type) {
      case SquareType.station:
        bandColor = Colors.grey.shade800;
        bandIcon  = Icons.train;
      case SquareType.utility:
        bandColor = Colors.teal.shade700;
        bandIcon  = sq.name.contains('Electric') ? Icons.bolt : Icons.water_drop;
      default:
        bandColor = scheme.groupColour(sq.colourGroup) ?? Colors.grey;
        bandIcon  = null;
    }

    final card = Container(
      width: 96,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 18,
            decoration: BoxDecoration(
              color: bandColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            ),
            alignment: Alignment.center,
            child: bandIcon != null ? Icon(bandIcon, size: 12, color: Colors.white) : null,
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sq.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('£${sq.price ?? 0}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                if (isMortgaged)
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(3)),
                    child: const Text('MORTGAGED',
                        style: TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: isBeingDragged ? 0.35 : 1.0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (assignedToColor != null)
            Positioned(
              top: -4, right: -4,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: assignedToColor,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Cash input card ──────────────────────────────────────────────────────────

class _CashInputCard extends StatelessWidget {
  const _CashInputCard({
    required this.controller,
    required this.maxAmount,
    this.assignedToColor,
    this.isBeingDragged = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final int maxAmount;
  final Color? assignedToColor;
  final bool isBeingDragged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 90,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('£',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: TextField(
                controller: controller,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                ),
                onChanged: (v) {
                  final parsed = int.tryParse(v) ?? 0;
                  if (parsed > maxAmount) {
                    controller.text = maxAmount.toString();
                    controller.selection =
                        TextSelection.collapsed(offset: maxAmount.toString().length);
                  }
                },
              ),
            ),
            const SizedBox(height: 4),
            Text('Bal: £$maxAmount',
                style: const TextStyle(fontSize: 8, color: Colors.white70),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: isBeingDragged ? 0.35 : 1.0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (assignedToColor != null)
            Positioned(
              top: -4, right: -4,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: assignedToColor,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Rent immunity card ───────────────────────────────────────────────────────

class _RentImmunityCard extends StatelessWidget {
  const _RentImmunityCard({
    required this.controller,
    this.assignedToColor,
    this.isBeingDragged = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final Color? assignedToColor;
  final bool isBeingDragged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 90,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.shield, size: 18, color: Colors.white),
            const SizedBox(height: 2),
            const Text('Rent\nImmunity',
                style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: TextField(
                controller: controller,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  hintText: 'turns',
                  hintStyle: TextStyle(fontSize: 9, color: Colors.grey),
                ),
                onChanged: (v) {
                  final parsed = int.tryParse(v) ?? 0;
                  if (parsed > 99) {
                    controller.text = '99';
                    controller.selection = const TextSelection.collapsed(offset: 2);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: isBeingDragged ? 0.35 : 1.0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (assignedToColor != null)
            Positioned(
              top: -4, right: -4,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: assignedToColor,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Loan input card ──────────────────────────────────────────────────────────

class _LoanInputCard extends StatefulWidget {
  const _LoanInputCard({
    required this.amountController,
    required this.turnsController,
    required this.interestController,
    required this.maxAmount,
    this.assignedToColor,
    this.isBeingDragged = false,
    this.enabled = true,
  });

  final TextEditingController amountController;
  final TextEditingController turnsController;
  final TextEditingController interestController;
  final int maxAmount;
  final Color? assignedToColor;
  final bool isBeingDragged;
  final bool enabled;

  @override
  State<_LoanInputCard> createState() => _LoanInputCardState();
}

class _LoanInputCardState extends State<_LoanInputCard> {
  @override
  void initState() {
    super.initState();
    widget.amountController.addListener(_onChanged);
    widget.turnsController.addListener(_onChanged);
    widget.interestController.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.amountController.removeListener(_onChanged);
    widget.turnsController.removeListener(_onChanged);
    widget.interestController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final amount   = int.tryParse(widget.amountController.text) ?? 0;
    final turns    = int.tryParse(widget.turnsController.text) ?? 0;
    final interest = (double.tryParse(widget.interestController.text) ?? 0) / 100.0;
    final terms    = LoanTerms(amount: amount, turns: turns, interestRate: interest);
    final total    = terms.isValid ? terms.totalRepayable : 0;
    final perTurn  = terms.isValid ? terms.instalment : 0;

    Widget field(TextEditingController c, String hint, {int max = 999999, String? suffix}) => Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
          child: TextField(
            controller: c,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 9, color: Colors.grey),
              suffixText: suffix,
              suffixStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            onChanged: (v) {
              final parsed = int.tryParse(v) ?? 0;
              if (parsed > max) {
                c.text = max.toString();
                c.selection = TextSelection.collapsed(offset: max.toString().length);
              }
            },
          ),
        );

    // Persistent caption above each field in the turns/interest row so it is
    // always clear which value is which, even once both are filled in.
    Widget captioned(String label, Widget f) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 7, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 1),
            f,
          ],
        );

    final card = Container(
      width: 104,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEF6C00), Color(0xFFFFB300)],
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_balance, size: 14, color: Colors.white),
                SizedBox(width: 3),
                Text('LOAN',
                    style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Row(children: [
              const Text('£', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(width: 2),
              Expanded(child: field(widget.amountController, 'value', max: widget.maxAmount)),
            ]),
            const SizedBox(height: 3),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: captioned('TURNS',
                      field(widget.turnsController, '0', max: 99, suffix: 't'))),
              const SizedBox(width: 3),
              Expanded(
                  child: captioned('INTEREST',
                      field(widget.interestController, '0', max: 100, suffix: '%'))),
            ]),
            const SizedBox(height: 3),
            Text(
              perTurn > 0 ? '£$perTurn/turn · £$total total' : 'Bal: £${widget.maxAmount}',
              style: const TextStyle(fontSize: 7, color: Colors.white),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: widget.isBeingDragged ? 0.35 : 1.0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (widget.assignedToColor != null)
            Positioned(
              top: -4, right: -4,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: widget.assignedToColor,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Public widget ────────────────────────────────────────────────────────────

class TradeOverlay extends ConsumerStatefulWidget {
  const TradeOverlay({
    super.key,
    required this.roomId,
    required this.myId,
    required this.effectivePlayerId,
    this.trade,
    required this.onClose,
  });

  final String roomId;
  final String myId;
  final String effectivePlayerId;
  final Map<String, dynamic>? trade;
  final VoidCallback onClose;

  @override
  ConsumerState<TradeOverlay> createState() => _TradeOverlayState();
}

class _TradeOverlayState extends ConsumerState<TradeOverlay> {
  // ── Who's in the trade (initiation mode only; effectivePlayerId always included) ──
  final Set<String> _selectedPlayers = {};

  // ── Assignment maps ───────────────────────────────────────────────────────
  final Map<String, String> _propAssignments  = {}; // 'ownerId:propIdx' -> targetPid
  final Map<String, String> _moneyTargets     = {}; // ownerId -> targetPid
  final Map<String, String> _rentTargets      = {}; // ownerId -> targetPid
  final Map<String, String> _loanTargets      = {}; // lenderId -> borrowerId
  final Set<String> _loanSeeded               = {}; // pids seeded with default terms

  // ── Controllers ───────────────────────────────────────────────────────────
  final Map<String, TextEditingController> _moneyControllers = {};
  final Map<String, TextEditingController> _rentControllers  = {};
  final Map<String, TextEditingController> _loanAmountControllers   = {};
  final Map<String, TextEditingController> _loanTurnsControllers    = {};
  final Map<String, TextEditingController> _loanInterestControllers = {};

  // ── Sub-phase (initiation only) ───────────────────────────────────────────
  bool _inSelectionPhase = true; // true = select players, false = assign assets

  // ── Counter mode ──────────────────────────────────────────────────────────
  bool _isCountering = false;
  String? _counteringAs; // in debug mode: which player is countering

  bool _isSubmitting = false;

  // ── GlobalKeys for arrows ─────────────────────────────────────────────────
  final GlobalKey _stackKey = GlobalKey();
  final Map<String, GlobalKey> _pawnKeys  = {};
  final Map<String, GlobalKey> _cardKeys  = {};
  final Map<String, GlobalKey> _cashKeys  = {};
  final Map<String, GlobalKey> _rentKeys  = {};
  final Map<String, GlobalKey> _loanKeys  = {};

  // ─────────────────────────────────────────────────────────────────────────

  bool get _isResponseMode => widget.trade != null && !_isCountering;

  @override
  void initState() {
    super.initState();
    if (widget.trade != null) {
      _populateFromTrade(widget.trade!);
    }
  }

  @override
  void didUpdateWidget(TradeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.trade?['id'];
    final newId = widget.trade?['id'];
    if (newId != null && newId != oldId) {
      _populateFromTrade(widget.trade!);
    }
  }

  @override
  void dispose() {
    for (final c in _moneyControllers.values) { c.dispose(); }
    for (final c in _rentControllers.values)  { c.dispose(); }
    for (final c in _loanAmountControllers.values)   { c.dispose(); }
    for (final c in _loanTurnsControllers.values)    { c.dispose(); }
    for (final c in _loanInterestControllers.values) { c.dispose(); }
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  TextEditingController _moneyCtrl(String pid) =>
      _moneyControllers.putIfAbsent(pid, () => TextEditingController(text: '0'));

  TextEditingController _rentCtrl(String pid) =>
      _rentControllers.putIfAbsent(pid, () => TextEditingController(text: ''));

  TextEditingController _loanAmountCtrl(String pid) =>
      _loanAmountControllers.putIfAbsent(pid, () => TextEditingController(text: ''));
  TextEditingController _loanTurnsCtrl(String pid) =>
      _loanTurnsControllers.putIfAbsent(pid, () => TextEditingController(text: ''));
  TextEditingController _loanInterestCtrl(String pid) =>
      _loanInterestControllers.putIfAbsent(pid, () => TextEditingController(text: ''));

  GlobalKey _pawnKey(String pid) => _pawnKeys.putIfAbsent(pid, GlobalKey.new);
  GlobalKey _cardKey(String key) => _cardKeys.putIfAbsent(key, GlobalKey.new);
  GlobalKey _cashKey(String pid) => _cashKeys.putIfAbsent(pid, GlobalKey.new);
  GlobalKey _rentKey(String pid) => _rentKeys.putIfAbsent(pid, GlobalKey.new);
  GlobalKey _loanKey(String pid) => _loanKeys.putIfAbsent(pid, GlobalKey.new);

  void _populateFromTrade(Map<String, dynamic> trade) {
    _propAssignments.clear();
    _moneyTargets.clear();
    _rentTargets.clear();
    _loanTargets.clear();
    final legs = (trade['legs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final leg in legs) {
      final from = leg['from'] as String? ?? '';
      final to   = leg['to']   as String? ?? '';
      for (final p in (leg['properties'] as List? ?? [])) {
        _propAssignments['$from:${(p as num).toInt()}'] = to;
      }
      final money = (leg['money'] as num?)?.toInt() ?? 0;
      if (money > 0) {
        _moneyTargets[from] = to;
        _moneyCtrl(from).text = money.toString();
      }
      final rentTurns = (leg['rent_immunity_turns'] as num?)?.toInt() ?? 0;
      if (rentTurns > 0) {
        _rentTargets[from] = to;
        _rentCtrl(from).text = rentTurns.toString();
      }
      final loan = leg['loan'];
      if (loan is Map) {
        final amount = (loan['amount'] as num?)?.toInt() ?? 0;
        if (amount > 0) {
          _loanTargets[from] = to;
          _loanAmountCtrl(from).text = amount.toString();
          _loanTurnsCtrl(from).text =
              ((loan['turns'] as num?)?.toInt() ?? 0).toString();
          final interest = (loan['interest_rate'] as num?)?.toDouble() ?? 0.0;
          _loanInterestCtrl(from).text = (interest * 100).round().toString();
        }
      }
    }
  }

  List<Map<String, dynamic>> _buildLegs(List<String> participants) {
    final legMap = <String, Map<String, dynamic>>{};

    Map<String, dynamic> ensure(String f, String t) =>
        legMap.putIfAbsent('$f:$t', () => {'from': f, 'to': t, 'properties': <int>[], 'money': 0, 'rent_immunity_turns': 0});

    for (final e in _propAssignments.entries) {
      final parts = e.key.split(':');
      (ensure(parts[0], e.value)['properties'] as List<int>).add(int.parse(parts[1]));
    }
    for (final pid in participants) {
      final money = int.tryParse(_moneyCtrl(pid).text) ?? 0;
      if (money <= 0) continue;
      final toId = _moneyTargets[pid] ??
          participants.firstWhere((p) => p != pid, orElse: () => '');
      if (toId.isEmpty) continue;
      ensure(pid, toId)['money'] = money;
    }
    for (final pid in participants) {
      final turns = int.tryParse(_rentCtrl(pid).text) ?? 0;
      if (turns <= 0) continue;
      final toId = _rentTargets[pid] ??
          participants.firstWhere((p) => p != pid, orElse: () => '');
      if (toId.isEmpty) continue;
      ensure(pid, toId)['rent_immunity_turns'] = turns;
    }
    for (final pid in participants) {
      // A loan is only part of the trade when the lender has explicitly
      // assigned it to a borrower (dragged the loan card onto a player).
      // Never fall back to a default target — an untargeted loan card is
      // just a scratchpad and must not be sent.
      final toId = _loanTargets[pid];
      if (toId == null || toId.isEmpty) continue;
      final amount = int.tryParse(_loanAmountCtrl(pid).text) ?? 0;
      final turns  = int.tryParse(_loanTurnsCtrl(pid).text) ?? 0;
      if (amount <= 0 || turns <= 0) continue;
      final pct = double.tryParse(_loanInterestCtrl(pid).text) ?? 0;
      ensure(pid, toId)['loan'] = LoanTerms(
        amount: amount,
        turns: turns,
        interestRate: pct / 100.0,
      ).toLeg();
    }

    return legMap.values.toList();
  }

  Future<void> _submitProposal(List<String> participants) async {
    if (_isSubmitting) return;
    final legs = _buildLegs(participants);
    if (legs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Include at least one asset or amount')));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final payload = <String, dynamic>{'participants': participants, 'legs': legs};
      if (widget.effectivePlayerId != widget.myId) {
        payload['debug_as'] = widget.effectivePlayerId;
      }
      await ref.read(gameServiceProvider).submitAction(
          widget.roomId, GameAction.proposeTrade, payload);
      widget.onClose();
    } on GameServiceException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitCounter(String? tradeId, List<String> participants) async {
    if (_isSubmitting || tradeId == null) return;
    final legs = _buildLegs(participants);
    setState(() => _isSubmitting = true);
    try {
      final payload = <String, dynamic>{
        'trade_id': tradeId,
        'counter': {'participants': participants, 'legs': legs},
      };
      // In debug mode, send as the player who clicked Counter
      if (_counteringAs != null && _counteringAs != widget.myId) {
        payload['debug_as'] = _counteringAs;
      }
      await ref.read(gameServiceProvider).submitAction(
          widget.roomId, GameAction.counterTrade, payload);
      // Counter accepted — flip back to response mode so the overlay shows
      // the new pending trade with the correct responder's buttons.
      if (mounted) {
        setState(() {
          _isCountering = false;
          _counteringAs = null;
        });
      }
    } on GameServiceException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _act(String action, Map<String, dynamic> payload) async {
    try {
      await ref.read(gameServiceProvider).submitAction(widget.roomId, action, payload);
    } on GameServiceException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(roomPlayersProvider(widget.roomId)).value ?? [];
    final state   = ref.watch(gameStateProvider(widget.roomId)).value;
    final config  = ref.watch(roomConfigProvider(widget.roomId)).value;
    final isDebug = ref.watch(isDebugModeProvider(widget.roomId));

    // Live-sync the response trade data
    Map<String, dynamic>? activeTrade = widget.trade;
    if (widget.trade != null) {
      final tradeId = widget.trade!['id'] as String?;
      final liveList = ref.watch(pendingTradesProvider(widget.roomId)).value;
      final liveTrade = liveList?.where((t) => t['id'] == tradeId).firstOrNull;

      if (liveList != null && liveTrade == null) {
        // Trade resolved — dismiss, but guard against the case where game_screen
        // has already updated widget.trade to a new trade (e.g. after a counter).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.trade?['id'] == tradeId) widget.onClose();
        });
      }
      if (liveTrade != null) activeTrade = liveTrade;
    }

    // Determine participant list
    final List<String> participantIds;
    if (_isResponseMode) {
      participantIds = (activeTrade!['participants'] as List?)?.cast<String>() ?? [];
    } else {
      // In counter mode use _counteringAs as the "from" player, not effectivePlayerId
      final fromId = (_isCountering && _counteringAs != null)
          ? _counteringAs!
          : widget.effectivePlayerId;
      participantIds = [fromId, ..._selectedPlayers];
    }

    // All phases show all non-bankrupt players; response mode dims non-participants.
    final allActive = players.where((p) => !p.isBankrupt).toList();

    // Player colours for arrow painter
    final playerColors = <String, Color>{
      for (final p in allActive) p.playerId: _tokenColor(p.tokenColour),
    };

    return Stack(
      key: _stackKey,
      children: [
        // ── Background scrim ────────────────────────────────────────────────
        GestureDetector(
          onTap: widget.onClose,
          behavior: HitTestBehavior.opaque,
          child: Container(color: Colors.black54),
        ),
        // ── Main card ───────────────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              elevation: 8,
              child: Column(
                children: [
                  _buildHeader(context, participantIds, activeTrade),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: allActive.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 12, endIndent: 12),
                      itemBuilder: (_, i) => _buildPlayerRow(
                        context,
                        player: allActive[i],
                        allPlayers: allActive,
                        participantIds: participantIds,
                        activeTrade: activeTrade,
                        state: state,
                        config: config,
                        isDebug: isDebug,
                      ),
                    ),
                  ),
                  if (_isResponseMode)
                    _buildResponseFooter(
                      activeTrade: activeTrade,
                      participantIds: participantIds,
                      allPlayers: allActive,
                      isDebug: isDebug,
                    ),
                ],
              ),
            ),
          ),
        ),
        // ── Arrows overlay ──────────────────────────────────────────────────
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ArrowPainter(
              propAssignments: _propAssignments,
              moneyTargets: _moneyTargets,
              rentTargets: _rentTargets,
              loanTargets: _loanTargets,
              cardKeys: _cardKeys,
              cashKeys: _cashKeys,
              rentKeys: _rentKeys,
              loanKeys: _loanKeys,
              pawnKeys: _pawnKeys,
              stackKey: _stackKey,
              playerColors: playerColors,
            ),
          ),
        ),
      ],
    );
  }

  // ── Header bar ─────────────────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    List<String> participantIds,
    Map<String, dynamic>? activeTrade,
  ) {
    if (_isResponseMode) {
      final tradeId  = activeTrade?['id'] as String?;
      final isProposer = activeTrade?['proposer_id'] == widget.effectivePlayerId;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Text('Trade Offer',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                if (isProposer && tradeId != null) {
                  _act(GameAction.cancelTrade, {'trade_id': tradeId});
                }
                widget.onClose();
              },
            ),
          ],
        ),
      );
    }

    if (_inSelectionPhase && !_isCountering) {
      // Phase 1: Select players
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Text('Select players',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            OutlinedButton(onPressed: widget.onClose, child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _selectedPlayers.isEmpty
                  ? null
                  : () => setState(() => _inSelectionPhase = false),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    }

    // Phase 2: Propose / Counter
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(_isCountering ? 'Counter Offer' : 'Propose trade',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
          OutlinedButton(
            onPressed: () {
              if (_isCountering) {
                setState(() {
                  _isCountering  = false;
                  _counteringAs  = null;
                  _propAssignments.clear();
                  _moneyTargets.clear();
                  _rentTargets.clear();
                  _loanTargets.clear();
                  if (widget.trade != null) _populateFromTrade(widget.trade!);
                });
              } else {
                setState(() {
                  _inSelectionPhase = true;
                  _propAssignments.clear();
                  _moneyTargets.clear();
                  _rentTargets.clear();
                  _loanTargets.clear();
                });
              }
            },
            child: const Text('Back'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _isSubmitting || participantIds.length < 2
                ? null
                : _isCountering
                    ? () => _submitCounter(activeTrade?['id'] as String?, participantIds)
                    : () => _submitProposal(participantIds),
            child: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isCountering ? 'Send Counter' : 'Offer'),
          ),
        ],
      ),
    );
  }

  // ── Player row ─────────────────────────────────────────────────────────────

  Widget _buildPlayerRow(
    BuildContext context, {
    required RoomPlayer player,
    required List<RoomPlayer> allPlayers,
    required List<String> participantIds,
    required Map<String, dynamic>? activeTrade,
    required GameState? state,
    required Map<String, dynamic>? config,
    required bool isDebug,
  }) {
    final pid      = player.playerId;
    final tc       = _tokenColor(player.tokenColour);
    final isProposer  = _isResponseMode && (activeTrade?['proposer_id'] as String?) == pid;
    final isInTrade  = participantIds.contains(pid);

    // ── Phase 1: Selection ─────────────────────────────────────────────────
    if (!_isResponseMode && !_isCountering && _inSelectionPhase) {
      final isSelf      = pid == widget.effectivePlayerId;
      final isSelected  = isSelf || _selectedPlayers.contains(pid);
      final multiParty  = config?['multi_party_trades'] as bool? ?? false;
      return InkWell(
        onTap: isSelf
            ? null
            : () => setState(() {
                  if (_selectedPlayers.contains(pid)) {
                    _selectedPlayers.remove(pid);
                  } else {
                    if (!multiParty) _selectedPlayers.clear(); // single-select
                    _selectedPlayers.add(pid);
                  }
                }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: isSelected
              ? BoxDecoration(
                  border: Border.all(color: tc, width: 2),
                  borderRadius: BorderRadius.circular(10),
                  color: tc.withValues(alpha: 0.08),
                )
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 148,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        KeyedSubtree(
                          key: _pawnKey(pid),
                          child: Container(
                            width: 16, height: 16,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: tc),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(player.displayName ?? 'Guest',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (isSelected && !isSelf)
                          Icon(Icons.check_circle, size: 16, color: tc),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.grey.shade200, margin: const EdgeInsets.only(right: 8)),
                Expanded(
                  child: _buildTradables(pid, state, config, allPlayers, participantIds,
                      forceReadOnly: true),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Phase 2 / Response / Counter: DragTarget row ───────────────────────
    return DragTarget<_TradeDragData>(
      onWillAcceptWithDetails: (d) => d.data.ownerId != pid && isInTrade && !_isResponseMode,
      onAcceptWithDetails: (d) {
        setState(() {
          if (d.data.propIndex >= 0) {
            _propAssignments['${d.data.ownerId}:${d.data.propIndex}'] = pid;
          } else if (d.data.propIndex == -1) {
            final amount = int.tryParse(_moneyCtrl(d.data.ownerId).text) ?? 0;
            if (amount > 0) _moneyTargets[d.data.ownerId] = pid;
          } else if (d.data.propIndex == -2) {
            final turns = int.tryParse(_rentCtrl(d.data.ownerId).text) ?? 0;
            if (turns > 0) _rentTargets[d.data.ownerId] = pid;
          } else if (d.data.propIndex == -3) {
            final amount = int.tryParse(_loanAmountCtrl(d.data.ownerId).text) ?? 0;
            final turns  = int.tryParse(_loanTurnsCtrl(d.data.ownerId).text) ?? 0;
            if (amount > 0 && turns > 0) _loanTargets[d.data.ownerId] = pid;
          }
        });
      },
      builder: (ctx, candidates, rejected) {
        final isHot = candidates.isNotEmpty;
        final rowContent = AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: isHot
              ? BoxDecoration(
                  border: Border.all(color: tc, width: 2.5),
                  borderRadius: BorderRadius.circular(10),
                  color: tc.withValues(alpha: 0.08),
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 148,
                  child: _buildLeftColumn(
                    pid: pid,
                    player: player,
                    tc: tc,
                    isInTrade: isInTrade,
                    isProposer: isProposer,
                    activeTrade: activeTrade,
                    participantIds: participantIds,
                  ),
                ),
                Container(width: 1, color: Colors.grey.shade200, margin: const EdgeInsets.only(right: 8)),
                Expanded(
                  child: _buildTradables(pid, state, config, allPlayers, participantIds),
                ),
              ],
            ),
          ),
        );
        // Dim non-participants; SizedBox.expand ensures full-row drop coverage
        if (!isInTrade) {
          return SizedBox(width: double.infinity, child: Opacity(opacity: 0.35, child: rowContent));
        }
        return SizedBox(width: double.infinity, child: rowContent);
      },
    );
  }

  // ── Left column ────────────────────────────────────────────────────────────

  Widget _buildLeftColumn({
    required String pid,
    required RoomPlayer player,
    required Color tc,
    required bool isInTrade,
    required bool isProposer,
    required Map<String, dynamic>? activeTrade,
    required List<String> participantIds,
  }) {
    final pawnWidget = KeyedSubtree(
      key: _pawnKey(pid),
      child: Container(
        width: 16, height: 16,
        decoration: BoxDecoration(shape: BoxShape.circle, color: tc),
      ),
    );

    // Assign / counter mode (phase 2, non-response)
    if (!_isResponseMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            pawnWidget,
            const SizedBox(width: 6),
            Expanded(
              child: Text(player.displayName ?? 'Guest',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
    }

    // ── Response mode ──────────────────────────────────────────────────────
    // Show name + accepted indicator. Buttons are in the modal footer.
    final acceptedByList = (activeTrade?['accepted_by'] as List?)?.cast<String>() ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          pawnWidget,
          const SizedBox(width: 6),
          Expanded(
            child: Text(player.displayName ?? 'Guest',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
          if (acceptedByList.contains(pid))
            Icon(Icons.check_circle, size: 14, color: Colors.green.shade600)
          else if (isProposer)
            Icon(Icons.swap_horiz, size: 14, color: Colors.blue.shade400)
          else
            Icon(Icons.hourglass_empty, size: 13, color: Colors.grey.shade400),
        ],
      ),
    );
  }

  // ── Response footer ────────────────────────────────────────────────────────

  Widget _buildResponseFooter({
    required Map<String, dynamic>? activeTrade,
    required List<String> participantIds,
    required List<RoomPlayer> allPlayers,
    required bool isDebug,
  }) {
    final tradeId      = activeTrade?['id'] as String?;
    final proposerId   = activeTrade?['proposer_id'] as String? ?? '';
    final acceptedByList = (activeTrade?['accepted_by'] as List?)?.cast<String>() ?? [];
    final receivers    = participantIds.where((p) => p != proposerId).toList();
    final currentResponderId = receivers.firstWhere(
      (p) => !acceptedByList.contains(p),
      orElse: () => '',
    );

    String nameOf(String id) =>
        allPlayers.where((p) => p.playerId == id).firstOrNull?.displayName ?? 'Player';

    Map<String, dynamic> actAs(String pid, Map<String, dynamic> base) =>
        pid != widget.myId ? {...base, 'debug_as': pid} : base;

    void startCounter(String pid) {
      _propAssignments.clear();
      _moneyTargets.clear();
      _rentTargets.clear();
      _loanTargets.clear();
      for (final c in _moneyControllers.values) { c.dispose(); }
      for (final c in _rentControllers.values)  { c.dispose(); }
      for (final c in _loanAmountControllers.values)   { c.dispose(); }
      for (final c in _loanTurnsControllers.values)    { c.dispose(); }
      for (final c in _loanInterestControllers.values) { c.dispose(); }
      _moneyControllers.clear();
      _rentControllers.clear();
      _loanAmountControllers.clear();
      _loanTurnsControllers.clear();
      _loanInterestControllers.clear();
      _loanSeeded.clear();
      if (activeTrade != null) _populateFromTrade(activeTrade);
      _selectedPlayers.clear();
      for (final p in participantIds) {
        if (p != pid) _selectedPlayers.add(p);
      }
      setState(() {
        _isCountering     = true;
        _counteringAs     = pid;
        _inSelectionPhase = false;
      });
    }

    // Build the responder action buttons section.
    // In debug mode: acts as currentResponderId regardless of myId.
    final isUserProposer   = proposerId == widget.effectivePlayerId;
    final isUserResponder  = currentResponderId == widget.effectivePlayerId;
    final canAct = isDebug
        ? currentResponderId.isNotEmpty
        : isUserResponder;

    final responderId = isDebug && currentResponderId.isNotEmpty
        ? currentResponderId
        : widget.effectivePlayerId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Debug label showing who we're acting as
              if (isDebug && currentResponderId.isNotEmpty &&
                  currentResponderId != widget.myId)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Acting as ${nameOf(currentResponderId)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Responder buttons (Refuse / Counter / Accept)
              if (currentResponderId.isNotEmpty && (isUserResponder || isDebug))
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: canAct
                            ? () => _act(GameAction.rejectTrade,
                                actAs(responderId, {'trade_id': tradeId}))
                            : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        child: const Text('Refuse'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: canAct ? () => startCounter(responderId) : null,
                        child: const Text('Counter'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: canAct
                            ? () => _act(GameAction.acceptTrade,
                                actAs(responderId, {'trade_id': tradeId}))
                            : null,
                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                        child: const Text('Accept'),
                      ),
                    ),
                  ],
                ),

              // Waiting status (not yet your turn)
              if (currentResponderId.isNotEmpty &&
                  !isUserResponder && !isDebug &&
                  !isUserProposer)
                Text(
                  'Waiting for ${nameOf(currentResponderId)}…',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tradables (right column) ───────────────────────────────────────────────

  Widget _buildTradables(
    String pid,
    GameState? state,
    Map<String, dynamic>? config,
    List<RoomPlayer> allPlayers,
    List<String> participantIds, {
    bool forceReadOnly = false,
  }) {
    final showMortgaged = config?['trade_mortgaged_properties'] as bool? ?? true;
    final props = state?.propertyOwnership.entries
            .where((e) => e.value == pid)
            .map((e) => int.parse(e.key))
            .where((i) => showMortgaged || !(state.mortgaged.contains(i)))
            .toList() ??
        <int>[];
    props.sort();

    final byGroup = <String, List<int>>{};
    final stations = <int>[];
    final utilities = <int>[];
    for (final idx in props) {
      final sq = Board.squares[idx];
      switch (sq.type) {
        case SquareType.property:
          byGroup.putIfAbsent(sq.colourGroup!, () => []).add(idx);
        case SquareType.station:
          stations.add(idx);
        case SquareType.utility:
          utilities.add(idx);
        default:
          break;
      }
    }

    // Phase 1 selection: show real cards but non-draggable
    if (forceReadOnly) {
      final allIdxs = [...props];
      if (allIdxs.isEmpty) {
        return Text('No properties', style: TextStyle(fontSize: 12, color: Colors.grey.shade400));
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        child: Wrap(
          spacing: 4, runSpacing: 4,
          children: [
            for (final idx in allIdxs)
              _TradePropCard(
                boardIndex: idx,
                isMortgaged: state?.mortgaged.contains(idx) ?? false,
              ),
          ],
        ),
      );
    }

    // Draggable only in edit mode for participants (not in response/read-only view)
    final canDrag = !_isResponseMode && participantIds.contains(pid);
    final cols = <Widget>[];

    for (final group in _groupOrder) {
      final idxs = byGroup[group];
      if (idxs == null || idxs.isEmpty) continue;
      cols.add(_buildPropColumn(pid, idxs, state, allPlayers, canDrag: canDrag));
      cols.add(const SizedBox(width: 8));
    }
    if (stations.isNotEmpty) {
      cols.add(_buildPropColumn(pid, stations, state, allPlayers, canDrag: canDrag));
      cols.add(const SizedBox(width: 8));
    }
    if (utilities.isNotEmpty) {
      cols.add(_buildPropColumn(pid, utilities, state, allPlayers, canDrag: canDrag));
      cols.add(const SizedBox(width: 8));
    }

    // Cash card
    final balance    = state?.balances[pid] ?? 0;
    final moneyCtrl  = _moneyCtrl(pid);
    final moneyColor = _moneyTargets[pid] != null
        ? _tokenColor(allPlayers.where((p) => p.playerId == _moneyTargets[pid]).firstOrNull?.tokenColour)
        : null;
    final cashCard = KeyedSubtree(
      key: _cashKey(pid),
      child: _CashInputCard(
          controller: moneyCtrl, maxAmount: balance,
          assignedToColor: moneyColor, enabled: !_isResponseMode),
    );
    // Cash: always draggable when participant — amount checked on drop/submit
    cols.add(
      canDrag
          ? Draggable<_TradeDragData>(
              data: _TradeDragData(ownerId: pid, propIndex: -1),
              feedback: Material(
                  color: Colors.transparent, elevation: 8,
                  child: _CashInputCard(controller: moneyCtrl, maxAmount: balance)),
              childWhenDragging: _CashInputCard(
                  controller: moneyCtrl, maxAmount: balance, isBeingDragged: true),
              child: GestureDetector(
                onTap: () => setState(() => _moneyTargets.remove(pid)),
                child: cashCard,
              ),
            )
          : cashCard,
    );

    // Rent immunity card
    cols.add(const SizedBox(width: 8));
    final rentCtrl  = _rentCtrl(pid);
    final rentColor = _rentTargets[pid] != null
        ? _tokenColor(allPlayers.where((p) => p.playerId == _rentTargets[pid]).firstOrNull?.tokenColour)
        : null;
    final rentCard = KeyedSubtree(
      key: _rentKey(pid),
      child: _RentImmunityCard(
          controller: rentCtrl, assignedToColor: rentColor, enabled: !_isResponseMode),
    );
    // Rent: always draggable when participant — turns checked on drop/submit
    cols.add(
      canDrag
          ? Draggable<_TradeDragData>(
              data: _TradeDragData(ownerId: pid, propIndex: -2),
              feedback: Material(
                  color: Colors.transparent, elevation: 8,
                  child: _RentImmunityCard(controller: rentCtrl)),
              childWhenDragging: _RentImmunityCard(controller: rentCtrl, isBeingDragged: true),
              child: GestureDetector(
                onTap: () => setState(() => _rentTargets.remove(pid)),
                child: rentCard,
              ),
            )
          : rentCard,
    );

    // Loan card (only when loans are enabled for this room)
    if (config?['loans_enabled'] as bool? ?? false) {
      cols.add(const SizedBox(width: 8));
      final loanAmountCtrl   = _loanAmountCtrl(pid);
      final loanTurnsCtrl    = _loanTurnsCtrl(pid);
      final loanInterestCtrl = _loanInterestCtrl(pid);
      // Pre-fill the repayment length once so the borrower need not type it;
      // amount and interest are left blank for the lender to set per trade.
      if (!_isResponseMode && _loanSeeded.add(pid)) {
        if (loanTurnsCtrl.text.isEmpty) {
          loanTurnsCtrl.text = _kDefaultLoanTurns.toString();
        }
      }
      final loanColor = _loanTargets[pid] != null
          ? _tokenColor(allPlayers.where((p) => p.playerId == _loanTargets[pid]).firstOrNull?.tokenColour)
          : null;
      final loanCard = KeyedSubtree(
        key: _loanKey(pid),
        child: _LoanInputCard(
          amountController: loanAmountCtrl,
          turnsController: loanTurnsCtrl,
          interestController: loanInterestCtrl,
          maxAmount: balance,
          assignedToColor: loanColor,
          enabled: !_isResponseMode,
        ),
      );
      // Loan: lend from this player to the drop target — values checked on drop/submit
      cols.add(
        canDrag
            ? Draggable<_TradeDragData>(
                data: _TradeDragData(ownerId: pid, propIndex: -3),
                feedback: Material(
                    color: Colors.transparent, elevation: 8,
                    child: _LoanInputCard(
                      amountController: loanAmountCtrl,
                      turnsController: loanTurnsCtrl,
                      interestController: loanInterestCtrl,
                      maxAmount: balance,
                    )),
                childWhenDragging: _LoanInputCard(
                  amountController: loanAmountCtrl,
                  turnsController: loanTurnsCtrl,
                  interestController: loanInterestCtrl,
                  maxAmount: balance,
                  isBeingDragged: true,
                ),
                child: GestureDetector(
                  onTap: () => setState(() => _loanTargets.remove(pid)),
                  child: loanCard,
                ),
              )
            : loanCard,
      );
    }

    if (cols.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('No tradeable properties',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: cols),
    );
  }

  Widget _buildPropColumn(
    String pid, List<int> idxs, GameState? state, List<RoomPlayer> allPlayers,
    {required bool canDrag}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final idx in idxs) ...[
          _buildDraggableCard(pid, idx, state, allPlayers, canDrag: canDrag),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _buildDraggableCard(
    String pid, int idx, GameState? state, List<RoomPlayer> allPlayers,
    {required bool canDrag}) {
    final isMortgaged   = state?.mortgaged.contains(idx) ?? false;
    final assignedTo    = _propAssignments['$pid:$idx'];
    final assignedColor = assignedTo != null
        ? _tokenColor(allPlayers.where((p) => p.playerId == assignedTo).firstOrNull?.tokenColour)
        : null;
    final cardKey = _cardKey('$pid:$idx');

    final cardWidget = KeyedSubtree(
      key: cardKey,
      child: _TradePropCard(boardIndex: idx, isMortgaged: isMortgaged, assignedToColor: assignedColor),
    );

    if (!canDrag) return cardWidget;

    return Draggable<_TradeDragData>(
      data: _TradeDragData(ownerId: pid, propIndex: idx),
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        child: _TradePropCard(boardIndex: idx, isMortgaged: isMortgaged),
      ),
      childWhenDragging: _TradePropCard(boardIndex: idx, isMortgaged: isMortgaged, isBeingDragged: true),
      child: GestureDetector(
        onTap: () => setState(() => _propAssignments.remove('$pid:$idx')),
        child: cardWidget,
      ),
    );
  }

}
