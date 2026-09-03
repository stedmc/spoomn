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

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool? _pendingDebugMode;
  bool _addingBot = false;
  bool _didInitDebug = false;

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
    } on GameServiceException catch (e) {
      setState(() => _pendingDebugMode = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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

  Future<void> _startGame() async {
    try {
      await ref.read(gameServiceProvider).startRoom(widget.roomId);
      // Navigation handled by ref.listen(gameRoomProvider) when status -> starting.
    } on GameServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(gameRoomProvider(widget.roomId));
    final playersAsync = ref.watch(roomPlayersProvider(widget.roomId));
    final myId = ref.watch(currentUserIdProvider);
    final configAsync = ref.watch(roomConfigProvider(widget.roomId));

    final isHost = roomAsync.valueOrNull?.hostId == myId;
    final streamDebugMode = configAsync.valueOrNull?['debug_mode'] as bool? ?? false;

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

    final screenW = MediaQuery.of(context).size.width;
    final isLargeScreen = screenW >= 600;

    return Scaffold(
      appBar: AppBar(title: const Text('Lobby')),
      body: roomAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (room) {
          Widget content = SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('Room Code', style: Theme.of(context).textTheme.labelMedium),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatRoomCode(room.roomCode),
                            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            tooltip: 'Copy room code',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: room.roomCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Room code copied'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
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
                  data: (players) => ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: players.length,
                    itemBuilder: (context, i) {
                      final p = players[i];
                      final isMe = p.playerId == myId;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                              p.isConnected ? Icons.person : Icons.person_outline),
                        ),
                        title: Text(p.displayName ?? 'Guest'),
                        subtitle: Text(p.isConnected ? 'Connected' : 'Disconnected'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isMe)
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: 'Edit name',
                                onPressed: () =>
                                    _editName(context, p.displayName ?? ''),
                              ),
                            if (isHost && !isMe)
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 18),
                                tooltip: 'Remove player',
                                onPressed: () => _removePlayer(p.playerId),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (isHost) ...[
                  const Divider(height: 1),
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
                ],
                const Divider(height: 1),
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
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _startGame,
                    child: const Text('Start Game'),
                  ),
                ),
              ],
            ),
          );

          if (isLargeScreen) {
            content = Center(
              child: SizedBox(width: screenW * 0.6, child: content),
            );
          }

          return content;
        },
      ),
    );
  }
}
