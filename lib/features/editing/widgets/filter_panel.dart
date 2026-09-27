import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/edit/filter_preset.dart';
import '../providers/edit_session_provider.dart';

/// Filter selection panel with preview strip and intensity slider.
class FilterPanel extends ConsumerWidget {
  final String photoId;

  const FilterPanel({super.key, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(editSessionProvider(photoId));
    final session = controller.state;
    final currentFilterId =
        session.recipe.filterOperation?.filterPresetId;
    final currentIntensity =
        session.recipe.filterOperation?.filterIntensity ?? 1.0;

    return Container(
      color: Colors.black,
      height: 200,
      child: Column(
        children: [
          // Filter preset strip
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: FilterPresets.all.length,
              itemBuilder: (context, index) {
                final preset = FilterPresets.all[index];
                final isSelected = preset.id == currentFilterId;
                return _FilterChip(
                  preset: preset,
                  isSelected: isSelected,
                  onTap: () {
                    if (isSelected) {
                      controller.removeFilter();
                    } else {
                      controller.setFilter(preset.id, currentIntensity);
                    }
                  },
                );
              },
            ),
          ),
          // Intensity slider
          if (currentFilterId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'Intensity',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: currentIntensity,
                      min: 0.0,
                      max: 1.0,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white24,
                      onChanged: (v) {
                        controller.setFilterIntensity(v);
                      },
                      onChangeEnd: (_) => controller.commitFilter(),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${(currentIntensity * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final FilterPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _categoryColor(preset.category),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.white24,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.photo_filter,
                  color: isSelected ? Colors.white : Colors.white54,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              preset.name,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.white70,
                fontSize: 10,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'Natural' => Colors.green.shade900,
      'Portrait' => Colors.pink.shade900,
      'Cinematic' => Colors.indigo.shade900,
      'B&W' => Colors.grey.shade800,
      'Vintage' => Colors.brown.shade800,
      'Vibrant' => Colors.purple.shade900,
      _ => Colors.blueGrey.shade900,
    };
  }
}
