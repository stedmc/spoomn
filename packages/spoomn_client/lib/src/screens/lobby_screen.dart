import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../providers/providers.dart';
import '../services/game_service.dart';

// ignore_for_file: use_build_context_synchronously

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool? _pendingDebugMode;
  bool _addingBot = false;

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

    ref.listen(gameRoomProvider(widget.roomId), (_, next) {
      next.whenData((room) {
        if (room.status == GameRoomStatus.starting && mounted) {
          context.go('/game/${widget.roomId}');
        }
      });
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Lobby')),
      body: roomAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (room) {
          final myId = ref.watch(currentUserIdProvider);
          final isHost = myId == room.hostId;
          final configAsync = ref.watch(roomConfigProvider(widget.roomId));
          final streamDebugMode = configAsync.valueOrNull?['debug_mode'] as bool? ?? false;
          // Clear pending once stream catches up
          if (_pendingDebugMode != null && _pendingDebugMode == streamDebugMode) {
            Future.microtask(() => setState(() => _pendingDebugMode = null));
          }
          final debugMode = _pendingDebugMode ?? streamDebugMode;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Room Code', style: Theme.of(context).textTheme.labelMedium),
                    Text(
                      room.roomCode,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            letterSpacing: 8,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: playersAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (players) => ListView.builder(
                    itemCount: players.length,
                    itemBuilder: (context, i) {
                      final p = players[i];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(p.isConnected ? Icons.person : Icons.person_outline),
                        ),
                        title: Text(p.displayName ?? 'Guest'),
                        subtitle: Text(p.isConnected ? 'Connected' : 'Disconnected'),
                      );
                    },
                  ),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: debugMode,
                onChanged: isHost ? (v) => _setDebugMode(v) : null,
                title: const Text('Debug mode'),
                subtitle: const Text('Cycle turns on one device, force dice, assign properties'),
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
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _startGame,
                  child: const Text('Start Game'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
