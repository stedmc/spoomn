import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/game_service.dart';

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
    final data = await Supabase.instance.client
        .from('room_players')
        .select('room_id, game_rooms!inner(*)')
        .isFilter('left_at', null)
        .inFilter('game_rooms.status', ['lobby', 'active', 'paused']);

    setState(() {
      _games = (data as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spoomn')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._games.map((g) => _GameCard(game: g)),
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
            ),
    );
  }

  Future<void> _createRoom() async {
    if (_creatingRoom) return;
    setState(() => _creatingRoom = true);
    try {
      final service = ref.read(gameServiceProvider);
      final result = await service.createRoom(maxPlayers: 8, playMode: 'realtime');
      if (!mounted) return;
      final roomId = (result['room'] as Map<String, dynamic>)['id'] as String;
      context.go('/lobby/$roomId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _creatingRoom = false);
    }
  }

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
          decoration: const InputDecoration(hintText: 'Room code (e.g. K7X2MQ)'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim().toUpperCase()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim().toUpperCase()),
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
  const _GameCard({required this.game});

  final Map<String, dynamic> game;

  @override
  Widget build(BuildContext context) {
    final room = game['game_rooms'] as Map<String, dynamic>;
    return Card(
      child: ListTile(
        title: Text(room['room_code'] as String),
        subtitle: Text('${room['status']} · ${room['player_count']} players'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          final roomId = room['id'] as String;
          final status = room['status'] as String;
          context.go(status == 'lobby' ? '/lobby/$roomId' : '/game/$roomId');
        },
      ),
    );
  }
}
