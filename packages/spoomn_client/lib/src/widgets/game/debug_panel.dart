import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoomn_core/spoomn_core.dart';

import '../../services/game_service.dart';
import 'game_constants.dart';

class GameDebugPanel extends ConsumerStatefulWidget {
  const GameDebugPanel({
    super.key,
    required this.roomId,
    required this.players,
    required this.actingAs,
    required this.onActingAsChanged,
  });

  final String roomId;
  final List<RoomPlayer> players;
  final String actingAs;
  final ValueChanged<String?> onActingAsChanged;

  @override
  ConsumerState<GameDebugPanel> createState() => _GameDebugPanelState();
}

class _GameDebugPanelState extends ConsumerState<GameDebugPanel> {
  String? _teleportTarget;
  final _squareController = TextEditingController(text: '0');

  @override
  void dispose() {
    _squareController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _teleportTarget ??= widget.actingAs;

    return Container(
      color: Colors.grey.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.bug_report, size: 13, color: Colors.orange),
              SizedBox(width: 4),
              Text(
                'Debug Mode',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Acting as:', style: TextStyle(fontSize: 12, color: Colors.white70)),
              const SizedBox(width: 6),
              Expanded(
                child: _debugDropdown<String>(
                  value: widget.actingAs.isEmpty ? null : widget.actingAs,
                  items: widget.players
                      .map((p) => DropdownMenuItem(
                            value: p.playerId,
                            child: Text(
                              p.displayName ?? 'Guest',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ))
                      .toList(),
                  onChanged: widget.onActingAsChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Move:', style: TextStyle(fontSize: 12, color: Colors.white70)),
              const SizedBox(width: 6),
              Expanded(
                child: _debugDropdown<String>(
                  value: (_teleportTarget?.isEmpty ?? true) ? null : _teleportTarget,
                  items: widget.players
                      .map((p) => DropdownMenuItem(
                            value: p.playerId,
                            child: Text(
                              p.displayName ?? 'Guest',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _teleportTarget = v),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 44,
                child: TextField(
                  controller: _squareController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    border: OutlineInputBorder(),
                    hintText: '0-39',
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 30,
                child: FilledButton(
                  onPressed: _teleport,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Go', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _teleport() async {
    final sq = int.tryParse(_squareController.text);
    if (sq == null || sq < 0 || sq > 39) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Square must be 0–39')),
      );
      return;
    }
    try {
      await ref.read(gameServiceProvider).submitAction(
        widget.roomId,
        GameAction.debugTeleport,
        {'player_id': _teleportTarget ?? widget.actingAs, 'square': sq},
      );
    } on GameServiceException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  DropdownButton<T> _debugDropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
        items: items,
        onChanged: onChanged,
      );
}
