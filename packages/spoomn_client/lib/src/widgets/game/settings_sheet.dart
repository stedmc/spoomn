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
    final currentScheme = ref.watch(boardColorSchemeProvider);
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
          const SizedBox(height: 16),
          const Text('Colour scheme'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scheme in BoardColorScheme.all)
                _SchemeTile(
                  scheme: scheme,
                  selected: currentScheme.id == scheme.id,
                  onTap: () =>
                      ref.read(boardColorSchemeProvider.notifier).set(scheme),
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

class _SchemeTile extends StatelessWidget {
  const _SchemeTile({
    required this.scheme,
    required this.selected,
    required this.onTap,
  });

  final BoardColorScheme scheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _SchemeSwatch(scheme: scheme),
            ),
            const SizedBox(height: 4),
            Text(
              scheme.displayName,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SchemeSwatch extends StatelessWidget {
  const _SchemeSwatch({required this.scheme});

  final BoardColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final colors = [
      scheme.brown,
      scheme.lightBlue,
      scheme.pink,
      scheme.orange,
      scheme.red,
      scheme.yellow,
      scheme.green,
      scheme.darkBlue,
    ];
    return SizedBox(
      width: 72,
      height: 24,
      child: Row(
        children: [
          for (final c in colors)
            Expanded(child: ColoredBox(color: c, child: const SizedBox.expand())),
        ],
      ),
    );
  }
}
