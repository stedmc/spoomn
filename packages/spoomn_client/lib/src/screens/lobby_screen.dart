import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoomn_core/spoomn_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/providers.dart';
import '../services/game_service.dart';
import '../widgets/lobby_settings_sheet.dart';

// ignore_for_file: use_build_context_synchronously

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({
    super.key,
    required this.roomId,
    this.showDebugMode = false,
  });

  final String roomId;
  final bool showDebugMode;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

String _formatRoomCode(String code) {
  if (code.length == 8) return '${code.substring(0, 4)} - ${code.substring(4)}';
  if (code.length == 6) return '${code.substring(0, 3)} - ${code.substring(3)}';
  return code;
}

// Human-readable label for a non-default config key/value pair.
String? _ruleLabel(String key, dynamic value) {
  if (!kRoomConfigDefaults.containsKey(key)) return null;
  final def = kRoomConfigDefaults[key];
  // Skip null-default keys that are still null
  if (def == null && value == null) return null;
  // Skip matching defaults
  if (def != null && value != null) {
    if (def is double || value is double) {
      if ((def as num).toDouble() == (value as num).toDouble()) return null;
    } else if (def == value) {
      return null;
    }
  }

  final labels = <String, String>{
    'starting_money': 'Starting money',
    'bank_unlimited': 'Unlimited bank',
    'bank_starting_amount': 'Bank amount',
    'house_limit': 'House limit',
    'hotel_limit': 'Hotel limit',
    'turn_order_method': 'Turn order',
    'dice_count': 'Dice count',
    'dice_sides': 'Die sides',
    'doubles_enabled': 'Doubles',
    'doubles_extra_turn': 'Extra turn on doubles',
    'jail_on_consecutive_doubles': 'Jail on N doubles',
    'go_salary': 'Go salary',
    'go_landing_bonus': 'Go landing bonus',
    'auto_claim_rent': 'Auto-claim rent',
    'income_tax_type': 'Income tax type',
    'income_tax_amount': 'Income tax',
    'income_tax_percentage': 'Income tax %',
    'super_tax_amount': 'Super tax',
    'free_parking_jackpot': 'Free parking jackpot',
    'free_parking_starting_amount': 'Parking pot start',
    'max_turn_time_secs': 'Turn time limit',
    'jail_fine': 'Jail fine',
    'jail_turns': 'Jail turns',
    'jail_doubles_escape': 'Escape jail with doubles',
    'collect_go_while_in_jail': 'Collect Go in jail',
    'jailbreak_enabled': 'Jailbreak',
    'must_build_evenly': 'Build evenly',
    'hotel_requires_four_houses': 'Hotel needs 4 houses',
    'houses_returned_on_hotel': 'Return houses on hotel',
    'build_own_turn_only': 'Build on own turn only',
    'sell_building_rate': 'Sell building rate',
    'mortgage_rate': 'Mortgage rate',
    'unmortgage_interest_rate': 'Unmortgage interest',
    'trade_mortgaged_properties': 'Trade mortgaged',
    'mortgage_transfer_penalty': 'Mortgage transfer fee',
    'auction_on_decline': 'Auction on decline',
    'auction_style': 'Auction style',
    'trade_any_turn': 'Trade any time',
    'multi_party_trades': 'Multi-party trades',
    'trade_futures': 'Trade future immunity',
    'trade_timeout_secs': 'Trade timeout',
    'winning_condition': 'Win condition',
    'net_worth_target': 'Net worth target',
    'turn_limit': 'Turn limit',
    'time_limit_mins': 'Time limit',
    'bankruptcy_assets_to': 'Bankruptcy assets to',
    'allow_bankruptcy_negotiation': 'Bankruptcy negotiation',
    'loans_enabled': 'Loans',
    'async_turn_timeout_hours': 'Async turn timeout',
  };

  final label = labels[key];
  if (label == null) return null;

  final valueStr = switch (value) {
    null => 'None',
    true => 'On',
    false => 'Off',
    _ => '$value',
  };

  return '$label: $valueStr';
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool? _pendingDebugMode;
  bool _addingBot = false;
  bool _didInitDebug = false;
  final Map<String, String> _localNameOverrides = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      await ref.read(gameServiceProvider).connect(widget.roomId);
    } catch (_) {}
  }

  Future<void> _disconnect() async {
    try {
      await ref.read(gameServiceProvider).disconnect(widget.roomId);
    } catch (_) {}
  }

  Future<void> _debugAddPlayer() async {
    if (_addingBot) return;
    setState(() => _addingBot = true);
    try {
      await ref.read(gameServiceProvider).debugAddPlayer(widget.roomId);
    } on GameServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _addingBot = false);
    }
  }

  Future<void> _setDebugMode(bool enabled) async {
    setState(() => _pendingDebugMode = enabled);
    try {
      await ref.read(gameServiceProvider).setDebugMode(widget.roomId, enabled: enabled);
    } catch (e) {
      if (mounted) setState(() => _pendingDebugMode = null);
      final message = e is GameServiceException ? e.message : 'Could not update debug mode';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _editName(BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(labelText: 'Display name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty) return;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    setState(() => _localNameOverrides[userId] = newName);
    await Supabase.instance.client
        .from('profiles')
        .update({'display_name': newName})
        .eq('id', userId);
  }

  Future<void> _removePlayer(String targetPlayerId) async {
    try {
      await ref.read(gameServiceProvider).removePlayer(widget.roomId, targetPlayerId);
    } on GameServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _confirmDeleteGame() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete game?'),
        content: const Text('This permanently removes the game for all players.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(gameServiceProvider).deleteRoom(widget.roomId);
      if (mounted) context.go('/dashboard');
    } on GameServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _startGame() async {
    try {
      await ref.read(gameServiceProvider).startRoom(widget.roomId);
    } on GameServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _copyRoomCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Room code copied'), duration: Duration(seconds: 2)),
    );
  }

  static const _deepLinkBase = String.fromEnvironment(
    'DEEP_LINK_BASE_URL',
    defaultValue: 'https://spoomn.online/join',
  );

  void _copyInviteLink(String code) {
    final link = '$_deepLinkBase/$code';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied'), duration: Duration(seconds: 2)),
    );
  }

  Widget _buildPlayersList(
    List<RoomPlayer> players,
    String? myId,
    bool isHost,
  ) {
    if (players.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No players yet', style: TextStyle(color: Colors.grey)),
      );
    }
    final onlineIds = ref.watch(onlinePlayerIdsProvider(widget.roomId)).value;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: players.length,
      itemBuilder: (context, i) {
        final p = players[i];
        final isMe = p.playerId == myId;
        final isOnline = onlineIds?.contains(p.playerId) ?? p.isConnected;
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            child: Icon(
              isOnline ? Icons.person : Icons.person_outline,
              size: 18,
            ),
          ),
          title: Text(_localNameOverrides[p.playerId] ?? p.displayName ?? 'Guest', style: const TextStyle(fontSize: 13)),
          subtitle: Text(
            isOnline ? 'Online' : 'Offline',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMe)
                IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  tooltip: 'Edit name',
                  onPressed: () => _editName(context, p.displayName ?? ''),
                ),
              if (isHost && !isMe)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                  tooltip: 'Remove player',
                  onPressed: () => _removePlayer(p.playerId),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNonDefaultRules(Map<String, dynamic>? config, {required bool isHost}) {
    if (config == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final rules = <(String, String)>[];
    for (final entry in config.entries) {
      final label = _ruleLabel(entry.key, entry.value);
      if (label != null) rules.add((entry.key, label));
    }

    if (rules.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'All default rules',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rules.length,
      itemBuilder: (_, i) {
        final (key, label) = rules[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.circle, size: 6, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
              if (isHost)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => ref
                      .read(resetConfigKeyProvider(widget.roomId).notifier)
                      .state = key,
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close, size: 13, color: Colors.grey),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(gameRoomProvider(widget.roomId));
    final playersAsync = ref.watch(roomPlayersProvider(widget.roomId));
    final myId = ref.watch(currentUserIdProvider);
    final configAsync = ref.watch(roomConfigProvider(widget.roomId));

    final draftConfig = ref.watch(draftRoomConfigProvider(widget.roomId));
    final isHost = roomAsync.value?.hostId == myId;
    final streamDebugMode = configAsync.value?['debug_mode'] as bool? ?? false;

    if (_pendingDebugMode != null && _pendingDebugMode == streamDebugMode) {
      Future.microtask(() => setState(() => _pendingDebugMode = null));
    }
    final debugMode = _pendingDebugMode ?? streamDebugMode;

    if (widget.showDebugMode && isHost && !_didInitDebug) {
      _didInitDebug = true;
      if (!streamDebugMode) {
        Future.microtask(() => _setDebugMode(true));
      }
    }

    ref.listen(gameRoomProvider(widget.roomId), (_, next) {
      next.whenData((room) {
        if (room.status == GameRoomStatus.starting && mounted) {
          context.go('/game/${widget.roomId}');
        }
      });
    });

    final room = roomAsync.value;
    final players = playersAsync.value ?? [];
    final config = configAsync.value;
    final screenW = MediaQuery.of(context).size.width;
    final isLargeScreen = screenW >= 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.go('/dashboard'),
        ),
        actions: [
          if (room != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatRoomCode(room.roomCode),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          letterSpacing: 3,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy room code',
                    onPressed: () => _copyRoomCode(room.roomCode),
                  ),
                  IconButton(
                    icon: const Icon(Icons.link, size: 18),
                    tooltip: 'Copy invite link',
                    onPressed: () => _copyInviteLink(room.roomCode),
                  ),
                ],
              ),
            ),
          ],
          if (isHost)
            PopupMenuButton<String>(
              tooltip: 'Lobby options',
              onSelected: (v) {
                if (v == 'delete') _confirmDeleteGame();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete game')),
              ],
            ),
        ],
      ),
      body: roomAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) {
          if (isLargeScreen) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left panel: Players
                Expanded(
                  flex: 1,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            'Players',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: SingleChildScrollView(
                            child: _buildPlayersList(players, myId, isHost),
                          ),
                        ),
                        if (widget.showDebugMode) ...[
                          const Divider(height: 1),
                          SwitchListTile(
                            dense: true,
                            value: debugMode,
                            onChanged: isHost ? (v) => _setDebugMode(v) : null,
                            title: const Text('Debug mode', style: TextStyle(fontSize: 12)),
                            secondary: const Icon(Icons.bug_report, size: 18),
                          ),
                          if (debugMode && isHost)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: OutlinedButton.icon(
                                onPressed: _addingBot ? null : _debugAddPlayer,
                                icon: _addingBot
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.person_add, size: 16),
                                label: const Text('Add Bot', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                // Center: Settings
                Expanded(
                  flex: 2,
                  child: isHost
                      ? SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Text(
                                  'Game Settings',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              const Divider(height: 1),
                              LobbySettingsSheet(
                                roomId: widget.roomId,
                                isHost: true,
                              ),
                            ],
                          ),
                        )
                      : const Center(
                          child: Text('Waiting for host to configure the game…',
                              style: TextStyle(color: Colors.grey)),
                        ),
                ),
                const VerticalDivider(width: 1),
                // Right panel: Non-default rules
                Expanded(
                  flex: 1,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                          child: Text(
                            'Custom Rules',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: _buildNonDefaultRules(draftConfig ?? config, isHost: isHost),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // Small screen: stacked layout
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Players section
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Players', style: Theme.of(context).textTheme.titleSmall),
                ),
                const Divider(height: 1),
                playersAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Error: $e'),
                  ),
                  data: (ps) => _buildPlayersList(ps, myId, isHost),
                ),
                const Divider(height: 1),
                // Non-default rules
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Custom Rules', style: Theme.of(context).textTheme.titleSmall),
                ),
                _buildNonDefaultRules(config, isHost: isHost),
                const Divider(height: 1),
                // Settings
                if (isHost) ...[
                  ExpansionTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Game Settings'),
                    subtitle: const Text('Rules, economy & win conditions'),
                    children: [
                      LobbySettingsSheet(
                        roomId: widget.roomId,
                        isHost: true,
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                ],
                if (widget.showDebugMode) ...[
                  SwitchListTile(
                    value: debugMode,
                    onChanged: isHost ? (v) => _setDebugMode(v) : null,
                    title: const Text('Debug mode'),
                    subtitle: const Text(
                        'Cycle turns on one device, force dice, assign properties'),
                    secondary: const Icon(Icons.bug_report),
                  ),
                  if (debugMode && isHost)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: OutlinedButton.icon(
                        onPressed: _addingBot ? null : _debugAddPlayer,
                        icon: _addingBot
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.person_add, size: 18),
                        label: const Text('Add Bot Player'),
                      ),
                    ),
                ],
                const SizedBox(height: 80), // Space for bottom bar
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: _startGame,
            child: const Text('Start Game'),
          ),
        ),
      ),
    );
  }
}
