import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/gallery_providers.dart';

/// Popup button for selecting grid column count.
class GridSizeButton extends ConsumerWidget {
  final int gridSize;
  const GridSizeButton({super.key, required this.gridSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<int>(
      initialValue: gridSize,
      icon: const Icon(Icons.grid_view),
      tooltip: 'Grid size (pinch to zoom)',
      onSelected: (v) => ref.read(gridSizeProvider.notifier).setSize(v),
      itemBuilder: (_) => [2, 3, 4, 5, 6]
          .map(
            (n) => PopupMenuItem(
              value: n,
              child: Row(
                children: [
                  Icon(
                    Icons.grid_on,
                    size: 18,
                    color: n == gridSize
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text('$n columns'),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
