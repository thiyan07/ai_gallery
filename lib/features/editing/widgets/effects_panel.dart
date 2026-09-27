import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/edit_session_provider.dart';

/// Effects panel with blur, grain, and fade controls.
class EffectsPanel extends ConsumerWidget {
  final String photoId;

  const EffectsPanel({super.key, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(editSessionProvider(photoId));
    final session = controller.state;
    final recipe = session.recipe;

    return Container(
      color: Colors.black,
      height: 240,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildGroupHeader('Blur'),
          _buildSlider(
            label: 'Blur',
            value: recipe.blurOperation?.blurStrength ?? 0.0,
            displayValue:
                '${((recipe.blurOperation?.blurStrength ?? 0.0) * 100).round()}',
            onChanged: (v) {
              final radius = recipe.blurOperation?.blurRadius ?? 5.0;
              controller.setBlur(radius, v);
            },
            onChangeEnd: (_) => controller.commitDrawing(),
          ),
          if ((recipe.blurOperation?.blurStrength ?? 0.0) > 0)
            _buildSlider(
              label: 'Radius',
              value:
                  (recipe.blurOperation?.blurRadius ?? 5.0) / 20.0,
              displayValue:
                  '${(recipe.blurOperation?.blurRadius ?? 5.0).round()}',
              onChanged: (v) {
                final strength =
                    recipe.blurOperation?.blurStrength ?? 0.5;
                controller.setBlur(v * 20.0, strength);
              },
              onChangeEnd: (_) => controller.commitDrawing(),
            ),
          const SizedBox(height: 12),
          _buildGroupHeader('Grain'),
          _buildSlider(
            label: 'Intensity',
            value: recipe.grainOperation?.grainIntensity ?? 0.0,
            displayValue:
                '${((recipe.grainOperation?.grainIntensity ?? 0.0) * 100).round()}',
            onChanged: (v) {
              final size = recipe.grainOperation?.grainSize ?? 0.5;
              controller.setGrain(v, size);
            },
            onChangeEnd: (_) => controller.commitDrawing(),
          ),
          if ((recipe.grainOperation?.grainIntensity ?? 0.0) > 0)
            _buildSlider(
              label: 'Size',
              value: recipe.grainOperation?.grainSize ?? 0.5,
              displayValue:
                  '${((recipe.grainOperation?.grainSize ?? 0.5) * 100).round()}',
              onChanged: (v) {
                final intensity =
                    recipe.grainOperation?.grainIntensity ?? 0.5;
                controller.setGrain(intensity, v);
              },
              onChangeEnd: (_) => controller.commitDrawing(),
            ),
          const SizedBox(height: 12),
          _buildGroupHeader('Fade'),
          _buildSlider(
            label: 'Fade',
            value: recipe.fadeOperation?.fadeIntensity ?? 0.0,
            displayValue:
                '${((recipe.fadeOperation?.fadeIntensity ?? 0.0) * 100).round()}',
            onChanged: (v) => controller.setFade(v),
            onChangeEnd: (_) => controller.commitDrawing(),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required String displayValue,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    final isNeutral = value == 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                color: isNeutral ? Colors.white54 : Colors.white,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              activeColor: isNeutral ? Colors.white54 : Colors.blue,
              inactiveColor: Colors.white12,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$displayValue',
              style: TextStyle(
                color: isNeutral ? Colors.white38 : Colors.white70,
                fontSize: 11,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
