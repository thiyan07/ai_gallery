import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/edit/frame_config.dart';
import '../providers/edit_session_provider.dart';

/// Frame/border selection and customization panel.
class FramePanel extends ConsumerWidget {
  final String photoId;

  const FramePanel({super.key, required this.photoId});

  static const _presetFrames = [
    _FramePreset('None', 0.0, 0xFFFFFFFF),
    _FramePreset('White', 0.03, 0xFFFFFFFF),
    _FramePreset('Black', 0.03, 0xFF000000),
    _FramePreset('Thin White', 0.015, 0xFFFFFFFF),
    _FramePreset('Thin Black', 0.015, 0xFF000000),
    _FramePreset('Thick White', 0.06, 0xFFFFFFFF),
    _FramePreset('Thick Black', 0.06, 0xFF000000),
    _FramePreset('Warm', 0.03, 0xFFD4A574),
    _FramePreset('Cool', 0.03, 0xFF74A5D4),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(editSessionProvider(photoId));
    final session = controller.state;
    final frameConfig = session.recipe.frameConfig;

    return Container(
      color: Colors.black,
      height: 200,
      child: Column(
        children: [
          // Frame presets
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: _presetFrames.length,
              itemBuilder: (context, index) {
                final preset = _presetFrames[index];
                final isActive = frameConfig.width == preset.width &&
                    frameConfig.color == preset.color;
                return _FrameChip(
                  preset: preset,
                  isActive: isActive,
                  onTap: () {
                    if (preset.width == 0.0) {
                      controller.removeFrame();
                    } else {
                      controller.setFrame(FrameConfig(
                        width: preset.width,
                        color: preset.color,
                      ));
                    }
                  },
                );
              },
            ),
          ),
          // Width slider
          if (frameConfig.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 60,
                        child: Text(
                          'Width',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: frameConfig.width,
                          min: 0.005,
                          max: 0.15,
                          activeColor: Colors.white,
                          inactiveColor: Colors.white24,
                          onChanged: (v) {
                            controller.setFrame(
                                frameConfig.copyWith(width: v));
                          },
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${(frameConfig.width * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  // Opacity slider
                  Row(
                    children: [
                      const SizedBox(
                        width: 60,
                        child: Text(
                          'Opacity',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: frameConfig.opacity,
                          min: 0.1,
                          max: 1.0,
                          activeColor: Colors.white,
                          inactiveColor: Colors.white24,
                          onChanged: (v) {
                            controller.setFrame(
                                frameConfig.copyWith(opacity: v));
                          },
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${(frameConfig.opacity * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FramePreset {
  final String name;
  final double width;
  final int color;

  const _FramePreset(this.name, this.width, this.color);
}

class _FrameChip extends StatelessWidget {
  final _FramePreset preset;
  final bool isActive;
  final VoidCallback onTap;

  const _FrameChip({
    required this.preset,
    required this.isActive,
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
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive ? Colors.blue : Colors.white24,
                  width: isActive ? 2 : 1,
                ),
              ),
              child: preset.width > 0
                  ? Container(
                      margin: EdgeInsets.all(preset.width * 100),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Color(preset.color),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )
                  : const Icon(
                      Icons.crop_free,
                      color: Colors.white54,
                      size: 24,
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              preset.name,
              style: TextStyle(
                color: isActive ? Colors.blue : Colors.white70,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
