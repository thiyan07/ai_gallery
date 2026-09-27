import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/edit/edit_operation.dart';
import '../providers/edit_session_provider.dart';

/// Per-channel HSL adjustment panel with colored channel selectors.
///
/// Provides 8 named color channels (Red through Magenta), each with
/// Hue shift, Saturation, and Luminance sliders.
class HslPanel extends ConsumerStatefulWidget {
  final String photoId;

  const HslPanel({super.key, required this.photoId});

  @override
  ConsumerState<HslPanel> createState() => _HslPanelState();
}

class _HslPanelState extends ConsumerState<HslPanel> {
  String _selectedChannel = 'red';

  static const _channels = [
    ('red', Color(0xFFE53935)),
    ('orange', Color(0xFFFF9800)),
    ('yellow', Color(0xFFFFEB3B)),
    ('green', Color(0xFF4CAF50)),
    ('aqua', Color(0xFF00BCD4)),
    ('blue', Color(0xFF2196F3)),
    ('purple', Color(0xFF9C27B0)),
    ('magenta', Color(0xFFE91E63)),
  ];

  static const _paramLabels = {
    'hue': 'Hue',
    'saturation': 'Saturation',
    'luminance': 'Luminance',
  };

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(editSessionProvider(widget.photoId));
    final session = controller.state;
    final hslOp = session.recipe.operations
        .where((op) => op.type == EditOperationType.hsl)
        .fold<EditOperation?>(
          null,
          (_, op) => op,
        );
    final channels = hslOp?.hslChannels ?? {};

    return Container(
      color: Colors.black,
      height: 240,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          _buildChannelSelector(),
          const SizedBox(height: 8),
          Expanded(
            child: _buildSliders(channels, controller),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelSelector() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _channels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (name, color) = _channels[index];
          final isSelected = name == _selectedChannel;
          return GestureDetector(
            onTap: () => setState(() => _selectedChannel = name),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected ? color.withAlpha(60) : Colors.white10,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? color : Colors.white24,
                  width: isSelected ? 2.5 : 1.0,
                ),
              ),
              child: Center(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSliders(
    Map<String, Map<String, double>> allChannels,
    EditSessionController controller,
  ) {
    final channelValues = allChannels[_selectedChannel] ?? {};
    final hue = channelValues['hue'] ?? 0.0;
    final sat = channelValues['saturation'] ?? 0.0;
    final lum = channelValues['luminance'] ?? 0.0;

    return Column(
      children: [
        _buildSlider(
          label: _paramLabels['hue']!,
          value: hue,
          min: -1.0,
          max: 1.0,
          displayValue: '${(hue * 180).round()}°',
          onChanged: (v) => _updateChannel('hue', v, controller),
          onChangeEnd: (_) => controller.commitAdjustment(),
        ),
        _buildSlider(
          label: _paramLabels['saturation']!,
          value: sat,
          min: -1.0,
          max: 1.0,
          displayValue: '${(sat * 100).round()}%',
          onChanged: (v) => _updateChannel('saturation', v, controller),
          onChangeEnd: (_) => controller.commitAdjustment(),
        ),
        _buildSlider(
          label: _paramLabels['luminance']!,
          value: lum,
          min: -1.0,
          max: 1.0,
          displayValue: '${(lum * 100).round()}%',
          onChanged: (v) => _updateChannel('luminance', v, controller),
          onChangeEnd: (_) => controller.commitAdjustment(),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: Colors.white24,
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              displayValue,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  void _updateChannel(
    String param,
    double value,
    EditSessionController controller,
  ) {
    final recipe = controller.state.recipe;
    final existing = recipe.operations
        .where((op) => op.type == EditOperationType.hsl)
        .fold<EditOperation?>(
          null,
          (_, op) => op,
        );

    Map<String, Map<String, double>> channels =
        Map<String, Map<String, double>>.from(
      existing?.hslChannels ?? {},
    );

    final currentChannel = Map<String, double>.from(
      channels[_selectedChannel] ?? {'hue': 0, 'saturation': 0, 'luminance': 0},
    );
    currentChannel[param] = value.clamp(-1.0, 1.0);
    channels[_selectedChannel] = currentChannel;

    final newOp = EditOperation.hsl(channels: channels);
    final ops = List<EditOperation>.from(recipe.operations)
      ..removeWhere((op) => op.type == EditOperationType.hsl)
      ..add(newOp);
    final newRecipe = recipe.copyWith(
      operations: ops,
      updatedAt: DateTime.now(),
    );
    controller.replaceRecipe(newRecipe);
  }
}
