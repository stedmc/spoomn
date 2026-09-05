import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/game_service.dart';

class _RoomCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final chars = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final raw = chars.length > 6 ? chars.substring(0, 6) : chars;
    final formatted = raw.length <= 3 ? raw : '${raw.substring(0, 3)} - ${raw.substring(3)}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<Map<String, dynamic>> _games = [];
  bool _loading = true;
  bool _creatingRoom = false;

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  Future<void> _loadGames() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final data = await Supabase.instance.client
        .from('room_players')
        .select('room_id, game_rooms!inner(*)')
        .eq('player_id', userId)
        .isFilter('left_at', null)
        .inFilter('game_rooms.status', ['lobby', 'active', 'paused']);

    setState(() {
      _games = (data as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isLargeScreen = screenW >= 600;

    Widget listView = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._games.map((g) => _GameCard(
              game: g,
              currentUserId: Supabase.instance.client.auth.currentUser?.id,
              onDelete: _confirmDeleteGame,
            )),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _creatingRoom ? null : _createRoom,
          child: _creatingRoom
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('New Game'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _joinWithCode,
          child: const Text('Join with Code'),
        ),
      ],
    );

    if (isLargeScreen) {
      listView = Center(child: SizedBox(width: screenW * 0.6, child: listView));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spoomn'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : listView,
    );
  }

  Future<void> _createRoom() async {
    if (_creatingRoom) return;
    setState(() => _creatingRoom = true);
    try {
      final service = ref.read(gameServiceProvider);
      final isDebug = GoRouterState.of(context).uri.queryParameters['gamemode'] == 'debug';
      final result = await service.createRoom(
        maxPlayers: 8,
        playMode: 'realtime',
        config: isDebug ? const {'debug_mode': true} : const {},
      );
      if (!mounted) return;
      final roomId = (result['room'] as Map<String, dynamic>)['id'] as String;
      context.go('/lobby/$roomId${isDebug ? '?gamemode=debug' : ''}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _creatingRoom = false);
    }
  }

  Future<void> _confirmDeleteGame(String roomId) async {
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
      await ref.read(gameServiceProvider).deleteRoom(roomId);
      await _loadGames();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  String _rawCode(String formatted) =>
      formatted.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<void> _joinWithCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Game'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [_RoomCodeFormatter()],
          decoration: const InputDecoration(hintText: 'e.g. K7X - 2MQ'),
          onSubmitted: (v) => Navigator.of(ctx).pop(_rawCode(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_rawCode(controller.text)),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (code == null || code.isEmpty || !mounted) return;

    try {
      final service = ref.read(gameServiceProvider);
      final result = await service.joinRoom(code);
      if (!mounted) return;
      final roomId = (result['room'] as Map<String, dynamic>)['id'] as String;
      context.go('/lobby/$roomId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.currentUserId,
    required this.onDelete,
  });

  final Map<String, dynamic> game;
  final String? currentUserId;
  final Future<void> Function(String roomId) onDelete;

  @override
  Widget build(BuildContext context) {
    final room = game['game_rooms'] as Map<String, dynamic>;
    final roomId = room['id'] as String;
    final isHost = currentUserId != null && room['host_id'] == currentUserId;
    return Card(
      child: ListTile(
        title: Text(room['room_code'] as String),
        subtitle: Text('${room['status']} · ${room['player_count']} players'),
        trailing: isHost
            ? PopupMenuButton<String>(
                tooltip: 'Game options',
                onSelected: (v) {
                  if (v == 'delete') onDelete(roomId);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete game')),
                ],
              )
            : const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          final status = room['status'] as String;
          context.go(status == 'lobby' ? '/lobby/$roomId' : '/game/$roomId');
        },
      ),
    );
  }
}
