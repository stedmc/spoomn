import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/settings_provider.dart';

class GameSettingsSheet extends ConsumerWidget {
  const GameSettingsSheet({super.key});

  static const _sizes = [
    ('Small', 10.0),
    ('Medium', 12.0),
    ('Large', 14.0),
    ('Extra Large', 16.0),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSize = ref.watch(boardFontSizeProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          const Text('Board font size'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (label, size) in _sizes)
                ChoiceChip(
                  label: Text(label),
                  selected: currentSize == size,
                  onSelected: (_) =>
                      ref.read(boardFontSizeProvider.notifier).set(size),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Exit to home'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => context.go('/'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

